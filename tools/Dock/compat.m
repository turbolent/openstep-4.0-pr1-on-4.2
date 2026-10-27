#import <AppKit/AppKit.h>
#import <AppKit/obsoleteSpeaker.h>
#include <stdarg.h>
#include <libc.h>
#include <sys/wait.h>
#include <errno.h>
#include <mach-o/loader.h>

@interface NSExecutable : NSObject {
    NSString *_path;
    NSData *_cache;
    void *_reserved;
}
+ executableWithPath:(NSString *)path;
+ executable;
- initWithPath:(NSString *)path;
- (int)executableType;
- architecturesSupported;
- dataForSegment:(NSString *)segment section:(NSString *)section;
- applicationHeader;
@end

@interface NSButton (PR1Compatibility)
- (void)setType:(int)type;
@end
@implementation NSButton (PR1Compatibility)
- (void)setType:(int)type {
    [self setButtonType:(NSButtonType)type];
}
@end

@interface NSCursor (PR1Compatibility)
- initWithImage:(NSImage *)image;
@end
@implementation NSCursor (PR1Compatibility)
- initWithImage:(NSImage *)image {
    return [self initWithImage:image hotSpot:NSMakePoint(0, 0)];
}
@end

@interface NSTextView (PR1Compatibility)
- (void)setSelectionColor:(NSColor *)color;
- (NSColor *)selectionColor;
@end
@implementation NSTextView (PR1Compatibility)
- (void)setSelectionColor:(NSColor *)color {
    NSMutableDictionary *attributes = [[self selectedTextAttributes] mutableCopy];
    if (!attributes)
        attributes = [[NSMutableDictionary alloc] init];
    if (color)
        [attributes setObject:color forKey:NSBackgroundColorAttributeName];
    else
        [attributes removeObjectForKey:NSBackgroundColorAttributeName];
    [self setSelectedTextAttributes:attributes];
    [attributes release];
}
- (NSColor *)selectionColor {
    return [[self selectedTextAttributes] objectForKey:NSBackgroundColorAttributeName];
}
@end

@interface PR1LaunchMonitor : NSObject {
    int child;
    int polls;
    NSString *path;
}
- initWithChild:(int)pid path:(NSString *)item;
- (void)poll:(NSTimer *)timer;
@end
@implementation PR1LaunchMonitor
- initWithChild:(int)pid path:(NSString *)item {
    self = [super init];
    child = pid;
    path = [item copy];
    return self;
}
- (void)dealloc {
    [path release];
    [super dealloc];
}
- (void)poll:(NSTimer *)timer {
    union wait status;
    int result = wait4(child, &status, WNOHANG, NULL);
    if (result == 0) {
        if (++polls == 150)
            kill(child, SIGTERM);
        return;
    }
    if (result < 0 && errno == EINTR)
        return;
    [self retain];
    [timer invalidate];
    if (result > 0)
        NSLog(@"PR1Compat: open %@ returned %d", path, status.w_status);
    if (result > 0 && status.w_status)
        NSRunAlertPanel(@"Dock PR1", @"Could not open %@.", @"OK", nil, nil, path);
    [self release];
}
@end

static void PR1Open(NSString *path, BOOL hide, BOOL another) {
    int pid;
    NSString *helper;
    PR1LaunchMonitor *monitor;
    if ([path isEqual:@"/NextApps/Viewer.app"])
        path = NSHomeDirectory();
    if ([path isEqual:@"/NextApps/MailViewer.app"])
        path = @"/NextApps/Mail.app";
    if ([path isEqual:@"/NextApps/Clock.app"])
        path = @"/NextApps/Preferences.app";
    if (!path)
        return;
    helper = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"OpenItem"];
    pid = fork();
    if (pid == 0) {
        extern char **environ;
        char *env[256], *args[5];
        int i, n = 0;
        for (i = 0; environ[i] && n < 255; i++)
            if (strncmp(environ[i], "DYLD_", 5))
                env[n++] = environ[i];
        env[n] = 0;
        args[0] = (char *)[helper cString];
        args[1] = (char *)[path cString];
        args[2] = hide ? "1" : "0";
        args[3] = another ? "1" : "0";
        args[4] = 0;
        execve((char *)[helper cString], args, env);
        _exit(127);
    }
    if (pid > 0) {
        monitor = [[PR1LaunchMonitor alloc] initWithChild:pid path:path];
        [NSTimer scheduledTimerWithTimeInterval:0.2
                                         target:monitor
                                       selector:@selector(poll:)
                                       userInfo:nil
                                        repeats:YES];
        [monitor release];
    } else if (pid < 0) {
        NSRunAlertPanel(@"Dock PR1", @"Could not start the launch helper.", @"OK", nil, nil);
    }
}

@interface WMFilenamesLocalBlobController : NSObject
@end
@interface WMFilenamesLocalBlobController (PR1Compatibility)
@end
@implementation WMFilenamesLocalBlobController (PR1Compatibility)
- (void)_openFile:(NSString *)path
         shouldHideOtherApps:(char)hide
    shouldRunAnotherInstance:(char)another {
    PR1Open(path, hide, another);
}
@end

@interface UserApplication : NSObject
@end
@interface UserApplication (PR1Compatibility)
@end
@implementation UserApplication (PR1Compatibility)
+ (void)launchManagerAndAutolaunchedApplication {
}
@end

@interface Workspace : NSApplication
- (void)_setupShelves;
- (void)_performDelayedAction:(id)sender;
- (void)forceArchiving;
@end
@interface NSApplication (PR1NativeLaunch)
- _replyToLaunch;
- appListenerPortName;
@end
@interface Workspace (PR1Compatibility)
@end
@implementation Workspace (PR1Compatibility)
- (void)setAppListener:(Listener *)listener {
    if ([listener isKindOfClass:NSClassFromString(@"WorkspaceRequestListener")])
        listener = [[Listener alloc] init];
    [super setAppListener:listener];
}
- (void)setAppSpeaker:(Speaker *)speaker {
    if ([speaker isKindOfClass:NSClassFromString(@"WorkspaceReplySpeaker")])
        speaker = [[Speaker alloc] init];
    [super setAppSpeaker:speaker];
}
- (void)sendEvent:(NSEvent *)event {
    [super sendEvent:event];
}
- _replyToLaunch {
    return [super _replyToLaunch];
}
- appListenerPortName {
    return [super appListenerPortName];
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Dock PR1"];
    [menu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    [self setMainMenu:menu];
    [menu release];
    [self _setupShelves];
    [NSTimer scheduledTimerWithTimeInterval:1.0
                                     target:self
                                   selector:@selector(_performDelayedAction:)
                                   userInfo:nil
                                    repeats:YES];
    NSLog(@"PR1Compat: Dock ready on OPENSTEP 4.2");
}
- (void)terminate:(id)sender {
    [self forceArchiving];
    [super terminate:sender];
}
@end

@interface NSWindow (PR1NativeDragging)
- _findDragTargetFrom:(id)sender;
@end
@interface WMTabWindow : NSWindow
@end
@implementation WMTabWindow (PR1Compatibility)
- _findDragTargetFrom:(id)sender {
    return [super _findDragTargetFrom:sender];
}
@end

@interface NSObject (PR1ShelfTypes)
+ acceptedPasteboardTypes;
@end
@interface WMShelf : NSView
- prototype;
@end
@implementation WMShelf (PR1Compatibility)
- (void)registerDraggedTypesForPrototype {
    NSArray *accepted = [[[self prototype] class] acceptedPasteboardTypes];
    NSMutableArray *types = accepted ? [accepted mutableCopy] : [[NSMutableArray alloc] init];
    /* The PR1 wildcard alone does not match a native 4.2 filename drag. */
    if (![types containsObject:NSFilenamesPboardType])
        [types addObject:NSFilenamesPboardType];
    [self unregisterDraggedTypes];
    [self registerForDraggedTypes:types];
    [types release];
}
@end

@interface NSObject (PR1ItemArchiving)
- (BOOL)shouldBeArchived;
- (BOOL)hasBeenModified;
- (BOOL)imageHasChanged;
- (BOOL)hasContainers;
- (void)setHasBeenModified:(BOOL)modified;
- (void)updateAttributesFromShelfItemWithImageArchiver:(id)images;
+ shelfItemContainerWithShelfItem:(id)item;
@end

@interface WMItemArchiver : NSObject {
    NSString *path;
    NSMutableArray *containers;
}
- containerForShelfItem:(id)item;
@end

@implementation WMItemArchiver (PR1Compatibility)
- (char)synchronizeWithoutArchivingWithShelfItems:(NSArray *)items withImageArchiver:(id)images {
    NSMutableArray *updated = [NSMutableArray array];
    NSEnumerator *enumerator = [items objectEnumerator];
    id item, container;
    BOOL changed = NO;
    while ((item = [enumerator nextObject])) {
        if (![item shouldBeArchived])
            continue;
        container = [self containerForShelfItem:item];
        if (!container) {
            container = [NSClassFromString(@"WMSIContainer") shelfItemContainerWithShelfItem:item];
            [container updateAttributesFromShelfItemWithImageArchiver:images];
            changed = YES;
        } else if ([item hasBeenModified] || ([images hasContainers] && [item imageHasChanged])) {
            [container updateAttributesFromShelfItemWithImageArchiver:images];
            changed = YES;
        }
        [item setHasBeenModified:NO];
        [updated addObject:container];
    }
    /* PR1 checked changed item attributes only, missing deletions and order changes. */
    if (![containers isEqualToArray:updated])
        changed = YES;
    if (changed) {
        [containers release];
        containers = [updated retain];
    }
    return changed;
}
@end

@implementation NSExecutable
+ executableWithPath:(NSString *)path {
    return [[[self alloc] initWithPath:path] autorelease];
}
+ executable {
    return [self executableWithPath:[[[NSProcessInfo processInfo] arguments] objectAtIndex:0]];
}
- initWithPath:(NSString *)path {
    BOOL directory = NO;
    NSBundle *bundle;
    NSString *name;
    self = [super init];
    if (!path) {
        [self release];
        return nil;
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory] &&
        directory) {
        bundle = [NSBundle bundleWithPath:path];
        name = [[bundle infoDictionary] objectForKey:@"NSExecutable"];
        if (!name)
            name = [[path lastPathComponent] stringByDeletingPathExtension];
        path = [path stringByAppendingPathComponent:name];
    }
    _path = [path copy];
    _cache = [[NSData dataWithContentsOfMappedFile:path] retain];
    if (!_cache) {
        [self release];
        return nil;
    }
    return self;
}
- (void)dealloc {
    [_path release];
    [_cache release];
    [super dealloc];
}
- _intelData {
    const unsigned char *bytes = [_cache bytes];
    unsigned length = [_cache length], i, n, pos, off, size;
    if (length < 28)
        return nil;
    if (!memcmp(bytes, "\312\376\272\276", 4)) {
        n = (bytes[4] << 24) | (bytes[5] << 16) | (bytes[6] << 8) | bytes[7];
        if (n > (length - 8) / 20)
            return nil;
        for (i = 0; i < n; i++) {
            pos = 8 + i * 20;
            if (bytes[pos] || bytes[pos + 1] || bytes[pos + 2] || bytes[pos + 3] != 7)
                continue;
            off = (bytes[pos + 8] << 24) | (bytes[pos + 9] << 16) | (bytes[pos + 10] << 8) |
                  bytes[pos + 11];
            size = (bytes[pos + 12] << 24) | (bytes[pos + 13] << 16) | (bytes[pos + 14] << 8) |
                   bytes[pos + 15];
            if (off > length || size > length - off || size < 28)
                return nil;
            return [_cache subdataWithRange:NSMakeRange(off, size)];
        }
        return nil;
    }
    return _cache;
}
- (int)executableType {
    NSData *data = [self _intelData];
    const struct mach_header *header = [data bytes];
    if (!data || [data length] < sizeof(*header))
        return 1;
    return header->magic == MH_MAGIC && header->cputype == 7 ? 0 : 1;
}
- architecturesSupported {
    return [self executableType] == 0 ? [NSArray arrayWithObject:@"i386"] : [NSArray array];
}
- dataForSegment:(NSString *)segment section:(NSString *)section {
    NSData *data = [self _intelData];
    const char *bytes = [data bytes];
    const struct mach_header *header;
    unsigned length = [data length], p, i, j;
    if ([self executableType] != 0)
        return nil;
    header = (const struct mach_header *)bytes;
    p = sizeof(*header);
    for (i = 0; i < header->ncmds; i++) {
        const struct load_command *command;
        if (p > length || length - p < sizeof(*command))
            return nil;
        command = (const struct load_command *)(bytes + p);
        if (command->cmdsize < sizeof(*command) || command->cmdsize > length - p)
            return nil;
        if (command->cmd == LC_SEGMENT && command->cmdsize >= sizeof(struct segment_command)) {
            const struct segment_command *seg = (const struct segment_command *)command;
            const struct section *sections = (const struct section *)(seg + 1);
            if (seg->nsects > (command->cmdsize - sizeof(*seg)) / sizeof(*sections))
                return nil;
            for (j = 0; j < seg->nsects; j++) {
                const struct section *s = sections + j;
                if (!strncmp(s->segname, [segment cString], 16) &&
                    !strncmp(s->sectname, [section cString], 16)) {
                    if (s->offset > length || s->size > length - s->offset)
                        return nil;
                    return [data subdataWithRange:NSMakeRange(s->offset, s->size)];
                }
            }
        }
        p += command->cmdsize;
    }
    return nil;
}
- applicationHeader {
    NSData *data = [self dataForSegment:@"__ICON" section:@"__header"];
    if (!data)
        return @"";
    return [[[NSString alloc] initWithData:data encoding:NSNEXTSTEPStringEncoding] autorelease];
}
@end

int NSRunLocalizedAlertPanel(NSString *table, NSString *title, NSString *format,
                             NSString *defaultButton, NSString *alternateButton,
                             NSString *otherButton, ...) {
    va_list args;
    NSString *message;
    int result;
    NSBundle *bundle = [NSBundle mainBundle];
    if (title)
        title = [bundle localizedStringForKey:title value:title table:table];
    if (format)
        format = [bundle localizedStringForKey:format value:format table:table];
    if (defaultButton)
        defaultButton = [bundle localizedStringForKey:defaultButton
                                                value:defaultButton
                                                table:table];
    if (alternateButton)
        alternateButton = [bundle localizedStringForKey:alternateButton
                                                  value:alternateButton
                                                  table:table];
    if (otherButton)
        otherButton = [bundle localizedStringForKey:otherButton value:otherButton table:table];
    va_start(args, otherButton);
    message = [[[NSString alloc] initWithFormat:format arguments:args] autorelease];
    va_end(args);
    result = NSRunAlertPanel(title, @"%@", defaultButton, alternateButton, otherButton, message);
    return result;
}
