/* Keep the DR2 file viewer separate from the native desktop manager. */
#import <AppKit/AppKit.h>
#import <AppKit/obsoleteSpeaker.h>
#import <objc/objc-class.h>
#include <sys/types.h>
#include <sys/vfs.h>
#include <unistd.h>
#include <errno.h>
#include "runtime-path.h"

@interface NodeViewerApplication : NSApplication
@end
@interface Viewer : NodeViewerApplication
- initializeUI;
- (void)noteMenusNeedUpdate:(id)sender;
- (BOOL)viewNode:(id)node;
- (BOOL)openNode:(id)node;
@end
@interface NSObject (DR2ViewerNodes)
- (NSString *)path;
+ fileNodeWithPath:(NSString *)path;
+ (void)saveDefaultsForAllWindows:(id)sender;
- registryLinesForWrapper:(id)node;
+ (void)bumpGeneration;
+ (void)flushChildrenNamesCache;
+ (void)validateDirDataCache;
@end

static IMP originalRegistryLines;
static IMP originalOperationCompleted;
static IMP originalRefreshHeuristic;
static BOOL refreshingCompletedOperation;

enum {
    MinimumLowSpace = 100 * 1024,
    MaximumLowSpace = 2 * 1024 * 1024,
    LowSpaceDivisor = 20
};

static long long freeSpace(id receiver, SEL selector, BOOL *low, NSString *directory,
                           NSString *file) {
    NSString *path = file ? [directory stringByAppendingPathComponent:file] : directory;
    struct statfs volume;
    long long available, threshold;
    if (low)
        *low = NO;
    /* A recycled selection may no longer exist before its browser redraws. */
    while (statfs([path cString], &volume)) {
        NSString *parent;
        if (errno != ENOENT && errno != ENOTDIR)
            return 0;
        parent = [path stringByDeletingLastPathComponent];
        if (![parent length] || [parent isEqual:path])
            return 0;
        path = parent;
    }
    available = (long long)volume.f_bavail * volume.f_bsize;
    threshold = (long long)volume.f_blocks * volume.f_bsize / LowSpaceDivisor;
    if (threshold < MinimumLowSpace)
        threshold = MinimumLowSpace;
    if (threshold > MaximumLowSpace)
        threshold = MaximumLowSpace;
    if (low)
        *low = available < threshold;
    return available;
}

static BOOL shouldRefreshWindow(id window, SEL selector) {
    if (refreshingCompletedOperation)
        return YES;
    return ((BOOL(*)(id, SEL))originalRefreshHeuristic)(window, selector);
}

static void operationCompleted(id receiver, SEL selector, id sender) {
    BOOL wasRefreshing = refreshingCompletedOperation;
    ((void (*)(id, SEL, id))originalOperationCompleted)(receiver, selector, sender);
    [NSClassFromString(@"CachingFileManager") bumpGeneration];
    [NSClassFromString(@"CachingFileManager") flushChildrenNamesCache];
    [NSClassFromString(@"ViewerFileNode") validateDirDataCache];
    /* Finish user operations without the background refresh's pointer/idle delay. */
    refreshingCompletedOperation = YES;
    NS_DURING
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ViewerNodeStructureChanged"
                                                            object:nil];
    NS_HANDLER
        refreshingCompletedOperation = wasRefreshing;
        [localException raise];
    NS_ENDHANDLER
    refreshingCompletedOperation = wasRefreshing;
}

static unsigned int registryLines(id receiver, SEL selector, NSMutableArray *lines, id name,
                                  NSString *type) {
    unsigned int count = ((unsigned int (*)(id, SEL, id, id, id))originalRegistryLines)(
        receiver, selector, lines, name, type);
    if (!name && [type isEqual:@"InspectorCommand"]) {
        id node = [NSClassFromString(@"ViewerFileNode")
            fileNodeWithPath:[[NSBundle mainBundle] bundlePath]];
        NSEnumerator *entries = [[receiver registryLinesForWrapper:node] objectEnumerator];
        NSDictionary *entry;
        /* Standalone Viewer has no Workspace registry of inspector commands. */
        while ((entry = [entries nextObject])) {
            if ([[entry objectForKey:@"type"] isEqual:type] && ![lines containsObject:entry]) {
                [lines addObject:entry];
                count++;
            }
        }
    }
    return count;
}

@interface DR2RuntimeListener : Listener
@end
@implementation DR2RuntimeListener
- (int)checkInAs:(NSString *)name {
    if ([name isEqual:@"Viewer"])
        name = @"ViewerDR2Runtime";
    return [super checkInAs:name];
}
@end

static BOOL openNative(NSString *path) {
    NSTask *task;
    if (![path length])
        return NO;
    task = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/open"
                                    arguments:[NSArray arrayWithObject:path]];
    return task != nil;
}

@implementation Viewer (DR2RuntimeDesktop)
- (void)setAppListener:(Listener *)listener {
    if ([listener isKindOfClass:NSClassFromString(@"WorkspaceReplyListener")])
        listener = [[DR2RuntimeListener alloc] init];
    [super setAppListener:listener];
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    NSEnumerator *names = [[NSArray
        arrayWithObjects:@"ViewerSelectionChanged", @"ViewerNodeAttributesChanged",
                         @"ViewerNodeStructureChanged", @"ViewerRecyclerChange",
                         @"ViewerDiskMounted", @"ViewerDiskUnmounted", nil] objectEnumerator];
    NSString *name;
    if (!originalRegistryLines) {
        Method method = class_getInstanceMethod(NSClassFromString(@"FileInfo"),
                                                @selector(addLinesTo:for:type:));
        originalRegistryLines = method->method_imp;
        method->method_imp = (IMP)registryLines;
        method = class_getInstanceMethod(NSClassFromString(@"Device"),
                                         @selector(freeSpaceAndLow:forDir:file:));
        method->method_imp = (IMP)freeSpace;
        method = class_getInstanceMethod(NSClassFromString(@"FileMover"),
                                         @selector(operationCompleted:));
        originalOperationCompleted = method->method_imp;
        method->method_imp = (IMP)operationCompleted;
        method = class_getInstanceMethod(NSClassFromString(@"WMWindow"),
                                         @selector(heuristicForRealUpdate));
        originalRefreshHeuristic = method->method_imp;
        method->method_imp = (IMP)shouldRefreshWindow;
    }
    /* Register file operations without starting Workspace's desktop services. */
    [NSClassFromString(@"FileMover") initialize];
    while ((name = [names nextObject]))
        [center addObserver:self selector:@selector(noteMenusNeedUpdate:) name:name object:nil];
    [[NSUserDefaults standardUserDefaults]
        registerDefaults:[NSDictionary
                             dictionaryWithObjectsAndKeys:@"Yes", @"WMInitializeViewersWithToolbar",
                                                          nil]];
    [self initializeUI];
    [self setDelegate:self];
    [[self appListener] setDelegate:self];
    [self noteMenusNeedUpdate:nil];
    [self activateIgnoringOtherApps:YES];
}
- (BOOL)application:(NSApplication *)application openFile:(NSString *)path {
    if (![path length])
        return NO;
    return [self openNode:[NSClassFromString(@"ViewerFileNode") fileNodeWithPath:path]];
}
- (BOOL)openNode:(id)node {
    BOOL directory = NO;
    NSString *path = [node path];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory])
        return NO;
    if (directory && ![[path pathExtension] isEqual:@"app"])
        return [self viewNode:node];
    return openNative(path);
}
- (void)terminate:(id)sender {
    [NSClassFromString(@"NodeWindow") saveDefaultsForAllWindows:sender];
    [[NSUserDefaults standardUserDefaults] synchronize];
    ((void (*)(id, SEL, id))class_getInstanceMethod([NSApplication class], _cmd)->method_imp)(
        self, _cmd, sender);
}
@end

@interface ViewerServices : NSObject
@end
@implementation ViewerServices (DR2RuntimeDesktop)
- (void)checkInWorkspaceManager {
}
- (BOOL)checkOutWorkspaceManager {
    return YES;
}
- (BOOL)willQuitCauseLogout {
    return NO;
}
- (BOOL)appOpenNode:(id)node {
    return openNative([node path]);
}
@end
