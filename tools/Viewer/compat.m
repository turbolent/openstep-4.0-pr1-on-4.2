#import <AppKit/AppKit.h>
#import <AppKit/obsoleteSpeaker.h>
#import <objc/objc-class.h>
#include <libc.h>
#include <sys/wait.h>
#include <errno.h>

NSString *NSFilenamePboardType = @"NeXT filename pasteboard type";

@interface NSObject (ViewerPR1Dispatch)
- perform:(SEL)selector;
@end
@implementation NSObject (ViewerPR1Dispatch)
- perform:(SEL)selector { return [self performSelector:selector]; }
@end

/* Native tooltips replace this callback. Keep the guard in the app module so
 * dyld binds it before PR1's help module imports the removed NSHelpPanel. */
@interface NSViewBubbleHelper : NSObject
@end
@implementation NSViewBubbleHelper (PR142Compatibility)
+ (void)displayHelpText { }
@end

@interface NodeViewerApplication : NSApplication
@end
@interface Viewer : NodeViewerApplication
- initializeUI;
- (void)noteMenusNeedUpdate:(NSNotification *)notification;
- (void)openFindPanelWithString:(NSString *)string forTarget:(id)target;
@end
@interface NSObject (ViewerPortMethods)
- path;
- (char)openNode:(id)node;
- (char)viewNode:(id)node;
+ fileNodeWithPath:(NSString *)path;
+ (void)saveDefaultsForAllWindows:(id)sender;
+ (void)bumpGeneration;
+ (void)validateDirDataCache;
- selectedNodes;
- registryLinesForWrapper:(id)node;
@end

static IMP originalRegistryLines;
static unsigned int ViewerRegistryLines(id receiver, SEL selector,
    NSMutableArray *lines, id name, NSString *type) {
    unsigned int count = ((unsigned int (*)(id, SEL, id, id, id))originalRegistryLines)(
        receiver, selector, lines, name, type);
    if (!name && [type isEqual:@"InspectorCommand"]) {
        /* Standalone Viewer has no PR1 Workspace application cache. Read its
         * bundled inspector registrations without starting Workspace services. */
        id node = [NSClassFromString(@"ViewerFileNode")
            fileNodeWithPath:[[NSBundle mainBundle] bundlePath]];
        NSEnumerator *entries = [[receiver registryLinesForWrapper:node] objectEnumerator];
        NSDictionary *entry;
        while ((entry = [entries nextObject])) {
            if ([[entry objectForKey:@"type"] isEqual:type] && ![lines containsObject:entry]) {
                [lines addObject:entry];
                count++;
            }
        }
    }
    return count;
}

static IMP originalApplicationLines;
static unsigned int ViewerApplicationLines(id receiver, SEL selector,
    NSMutableArray *lines, NSString *directory, NSString *file) {
    unsigned int count = ((unsigned int (*)(id, SEL, id, id, id))originalApplicationLines)(
        receiver, selector, lines, directory, file);
    NSWorkspace *workspace;
    NSString *path, *application = nil, *type = nil;
    if (count) return count;
    workspace = [NSWorkspace sharedWorkspace];
    path = file ? [directory stringByAppendingPathComponent:file] : directory;
    if (![workspace getInfoForFile:path application:&application type:&type]
        || ![application length] || [type isEqual:NSDirectoryFileType]
        || [type isEqual:NSApplicationFileType] || [type isEqual:NSFilesystemFileType])
        return 0;
    application = [workspace fullPathForApplication:application];
    if (![application length]) return 0;
    /* The Tools inspector can use the native Workspace's document association
     * when no PR1 application registry is available. A nil array is a query. */
    [lines addObject:[NSDictionary dictionaryWithObject:application forKey:@"path"]];
    return 1;
}

@interface ViewerLaunchMonitor : NSObject {
    int child;
    int polls;
    NSString *path;
    BOOL changesFiles;
    NSString *fileOperation;
}
- initWithChild:(int)pid path:(NSString *)item;
- (void)poll:(NSTimer *)timer;
- (void)refreshFilesWhenDone:(NSString *)operation;
@end
@implementation ViewerLaunchMonitor
- initWithChild:(int)pid path:(NSString *)item {
    self = [super init]; child = pid; path = [item copy]; return self;
}
- (void)dealloc { [path release]; [fileOperation release]; [super dealloc]; }
- (void)refreshFilesWhenDone:(NSString *)operation { changesFiles = YES; fileOperation = [operation copy]; }
- (void)poll:(NSTimer *)timer {
    union wait status;
    int result = wait4(child, &status, WNOHANG, NULL);
    if (result == 0) { if (!changesFiles && ++polls == 150) kill(child, SIGTERM); return; }
    if (result < 0 && errno == EINTR) return;
    [self retain]; [timer invalidate];
    NSLog(@"ViewerCompat: %@ %@ status=%d", changesFiles ? fileOperation : @"open", path,
        result > 0 ? status.w_status : -1);
    if (changesFiles) {
        [NSClassFromString(@"CachingFileManager") bumpGeneration];
        [NSClassFromString(@"ViewerFileNode") validateDirDataCache];
        [[NSNotificationQueue defaultQueue] enqueueNotification:
            [NSNotification notificationWithName:@"ViewerNodeStructureChanged" object:nil]
            postingStyle:NSPostASAP];
    }
    if (result > 0 && status.w_status) {
        if (changesFiles) NSRunAlertPanel(@"Viewer PR1", @"Could not %@ all selected files. Check free space and permissions; any completed operations have been kept.", @"OK", nil, nil, fileOperation);
        else NSRunAlertPanel(@"Viewer PR1", @"Could not open %@.", @"OK", nil, nil, path);
    }
    [self release];
}
@end

static IMP originalFileApply;
static char ViewerFileApply(id receiver, SEL selector, NSString *operation, id nodes, id argument, id options) {
    NSArray *selected;
    NSString *helper;
    char **args;
    unsigned int count, i;
    int pid;
    ViewerLaunchMonitor *monitor;
    if (![operation isEqual:@"duplicate"] && ![operation isEqual:@"recycle"])
        return ((char (*)(id, SEL, id, id, id, id))originalFileApply)(receiver, selector, operation, nodes, argument, options);
    selected = [nodes selectedNodes]; count = [selected count];
    if (!count) return NO;
    helper = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"OpenItem"];
    args = calloc(count + 3, sizeof(char *));
    if (!args) return NO;
    args[0] = (char *)[helper cString];
    args[1] = [operation isEqual:@"duplicate"] ? "--duplicate" : "--recycle";
    for (i = 0; i < count; i++) args[i + 2] = (char *)[[[selected objectAtIndex:i] path] cString];
    pid = fork();
    if (pid == 0) {
        extern char **environ;
        char *env[256]; int n = 0, j;
        for (j = 0; environ[j] && n < 255; j++)
            if (strncmp(environ[j], "DYLD_", 5)) env[n++] = environ[j];
        env[n] = 0;
        execve(args[0], args, env); _exit(127);
    }
    free(args);
    if (pid < 0) return NO;
    monitor = [[ViewerLaunchMonitor alloc] initWithChild:pid path:@"selected files"];
    [monitor refreshFilesWhenDone:operation];
    [NSTimer scheduledTimerWithTimeInterval:0.2 target:monitor selector:@selector(poll:)
        userInfo:nil repeats:YES];
    [monitor release];
    return YES;
}

static BOOL ViewerOpen(NSString *path, NSString *application) {
    NSString *helper;
    int pid;
    ViewerLaunchMonitor *monitor;
    if (!path) return NO;
    helper = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"OpenItem"];
    pid = fork();
    if (pid == 0) {
        extern char **environ;
        char *env[256], *args[6]; int i, n = 0;
        for (i = 0; environ[i] && n < 255; i++)
            if (strncmp(environ[i], "DYLD_", 5)) env[n++] = environ[i];
        env[n] = 0;
        args[0] = (char *)[helper cString]; args[1] = (char *)[path cString];
        args[2] = "0"; args[3] = "0";
        args[4] = application ? (char *)[application cString] : 0; args[5] = 0;
        execve(args[0], args, env); _exit(127);
    }
    if (pid < 0) return NO;
    monitor = [[ViewerLaunchMonitor alloc] initWithChild:pid path:path];
    [NSTimer scheduledTimerWithTimeInterval:0.2 target:monitor selector:@selector(poll:)
        userInfo:nil repeats:YES];
    [monitor release];
    return YES;
}
@interface NSApplication (ViewerNativeLaunch)
- _replyToLaunch;
@end
@implementation Viewer (PR142Compatibility)
- (void)toolConnectionDied:(NSNotification *)notification {
    /* PR1's tool manager waits for the old connection-death notification. */
    [[NSNotificationCenter defaultCenter] postNotificationName:@"NSConnectionDeath"
        object:[notification object]];
}
- (void)attachCheckForDiskMenuItem { }
- (void)attachEncryptionMenuItem { }
- (void)checkDisks:(id)sender { ViewerOpen(@"--check-disks", nil); }
- (void)showFindPanel:(id)sender { [self openFindPanelWithString:@"" forTarget:nil]; }
- _replyToLaunch {
    return ((id (*)(id, SEL))class_getInstanceMethod([NSApplication class], _cmd)->method_imp)(self, _cmd);
}
- (void)setAppListener:(Listener *)listener {
    if ([listener isKindOfClass:NSClassFromString(@"WorkspaceReplyListener")])
        listener = [[Listener alloc] init];
    [super setAppListener:listener];
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    NSArray *changes = [NSArray arrayWithObjects:@"ViewerSelectionChanged", @"ViewerDiskMounted",
        @"ViewerDiskUnmounted", @"ViewerNodeAttributesChanged", @"ViewerNodeStructureChanged",
        @"ViewerRecyclerChange", nil];
    NSEnumerator *names = [changes objectEnumerator];
    NSString *name;
    [center addObserver:self selector:@selector(toolConnectionDied:)
        name:NSConnectionDidDieNotification object:nil];
    if (!originalRegistryLines) {
        Method lines = class_getInstanceMethod(NSClassFromString(@"FileInfo"),
            @selector(addLinesTo:for:type:));
        originalRegistryLines = lines->method_imp;
        lines->method_imp = (IMP)ViewerRegistryLines;
    }
    if (!originalApplicationLines) {
        Method lines = class_getInstanceMethod(NSClassFromString(@"FileInfo"),
            @selector(addLinesTo:forDir:file:));
        originalApplicationLines = lines->method_imp;
        lines->method_imp = (IMP)ViewerApplicationLines;
    }
    /* These local services were previously lost with the Workspace startup code. */
    [NSClassFromString(@"FileMover") initialize];
    if (!originalFileApply) {
        Method apply = class_getClassMethod(NSClassFromString(@"FileMover"),
            @selector(doApply:forNodePathSet:withArgument:options:));
        originalFileApply = apply->method_imp;
        apply->method_imp = (IMP)ViewerFileApply;
    }
    while ((name = [names nextObject]))
        [center addObserver:self selector:@selector(noteMenusNeedUpdate:) name:name object:nil];
    NSLog(@"ViewerCompat: initializing UI");
    [self initializeUI];
    [[self appListener] setDelegate:self];
    [self setDelegate:self];
    {
        NSMenu *menu = [self mainMenu];
        id item = [[menu itemArray] lastObject];
        [menu setTitle:@"Viewer PR1"];
        if ([item action] == @selector(terminate:)) [item setTitle:@"Quit"];
    }
    [self activateIgnoringOtherApps:YES];
    [self noteMenusNeedUpdate:nil];
    NSLog(@"ViewerCompat: ready");
}
- (BOOL)application:(NSApplication *)app openFile:(NSString *)path {
    return [self openNode:[NSClassFromString(@"ViewerFileNode") fileNodeWithPath:path]];
}
- (char)openNode:(id)node {
    BOOL directory = NO;
    NSString *path = [node path];
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory]) return NO;
    if (directory && ![[path pathExtension] isEqual:@"app"])
        return [self viewNode:node];
    return ViewerOpen(path, nil);
}
- (char)openNode:(id)node withProgram:(id)program {
    return ViewerOpen([node path], [program isKindOfClass:[NSString class]] ? program : [program path]);
}
- (char)openNode:(id)node andFind:(NSString *)text { return [self openNode:node]; }
- (void)terminate:(id)sender {
    [NSClassFromString(@"NodeWindow") saveDefaultsForAllWindows:sender];
    [[NSUserDefaults standardUserDefaults] synchronize];
    ((void (*)(id,SEL,id))class_getInstanceMethod([NSApplication class], _cmd)->method_imp)(self, _cmd, sender);
}
@end

@interface ViewerServices : NSObject
@end
@implementation ViewerServices (PR142Compatibility)
- (void)checkInWorkspaceManager { }
- (char)checkOutWorkspaceManager { return YES; }
- (char)willQuitCauseLogout { return NO; }
- (char)appOpenNode:(id)node { return ViewerOpen([node path], nil); }
- (char)appOpenNode:(id)node withAppNode:(id)application named:(NSString *)name {
    return ViewerOpen([node path], application ? [application path] : name);
}
- (char)appOpenNode:(id)node andFind:(NSString *)text { return ViewerOpen([node path], nil); }
- (char)activateAppForNode:(id)node mustBeIdle:(char)idle { return ViewerOpen([node path], nil); }
@end
