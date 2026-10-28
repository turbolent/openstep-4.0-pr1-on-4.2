/* Run the stock DR2 Applications menu as an ordinary OPENSTEP application. */
#import <AppKit/AppKit.h>
#import <AppKit/obsoleteSpeaker.h>
#import <AppKit/psops.h>
#import <objc/objc-class.h>
#include <libc.h>
#include "contexts.h"

extern NSString *_NXGetWorkspaceName(void);

enum {
    WorkspaceTimeoutMilliseconds = 1000,
    ApplicationRecordFields = 4,
    ApplicationRunning = 2,
    ApplicationUnhideEvent = 7,
    ApplicationHideEvent = 10,
    ProcessLineCapacity = 8192
};
static const float ApplicationIconSize = 16;
static const NSTimeInterval RefreshInterval = 1;
static NSString *const ShowNamesKey = @"ShowActiveApplicationName";

@interface NSObject (WorkspaceMenuPrivate)
- (NSMatrix *)itemMatrix;
- (void)addApplication:(id)application;
- (void)removeApplication:(id)application;
- (void)insertItem:(id)item atIndex:(unsigned)index;
- initTextCell:(NSString *)title;
- (void)setImagePosition:(NSCellImagePosition)position;
- (void)_setAvoidsActivation:(BOOL)flag;
@end

@interface DR2RunningApplication : NSObject {
    NSString *appName;
    NSString *appPath;
    NSImage *appIcon;
    int handle;
    int processID;
}
- initWithFields:(NSArray *)fields;
- (const char *)name;
- (NSString *)displayName;
- (NSString *)path;
- (int)sequenceNumber;
- (NSImage *)smallIcon;
- (BOOL)isWorkspaceManager;
- (int)state;
- (int)processID;
- (void)setProcessID:(int)value;
- (void)activate;
@end

static Speaker *workspaceSpeaker(void) {
    Speaker *speaker = [[[Speaker alloc] init] autorelease];
    [speaker setSendPort:NXPortFromName(_NXGetWorkspaceName(), @"")];
    [speaker setSendTimeout:WorkspaceTimeoutMilliseconds];
    [speaker setReplyTimeout:WorkspaceTimeoutMilliseconds];
    return speaker;
}

@implementation DR2RunningApplication
- initWithFields:(NSArray *)fields {
    self = [super init];
    appName = [[fields objectAtIndex:0] copy];
    appPath = [[fields objectAtIndex:1] copy];
    handle = [[fields objectAtIndex:3] intValue];
    appIcon = [[[NSWorkspace sharedWorkspace] iconForFile:appPath] copy];
    [appIcon setScalesWhenResized:YES];
    [appIcon setSize:NSMakeSize(ApplicationIconSize, ApplicationIconSize)];
    return self;
}
- (const char *)name {
    return [appName cString];
}
- (NSString *)displayName {
    if ([self isWorkspaceManager])
        return @"Workspace Manager";
    return appName;
}
- (NSString *)path {
    return appPath;
}
- (int)sequenceNumber {
    return handle;
}
- (NSImage *)smallIcon {
    return appIcon;
}
- (BOOL)isWorkspaceManager {
    return [appName isEqual:@"WM"];
}
- (int)state {
    return ApplicationRunning;
}
- (int)processID {
    return processID;
}
- (void)setProcessID:(int)value {
    processID = value;
}
- (void)activate {
    if ([workspaceSpeaker() selectorRPC:@"activateAppWithHandle:" paramTypes:"i", handle])
        NSBeep();
}
- (void)dealloc {
    [appName release];
    [appPath release];
    [appIcon release];
    [super dealloc];
}
@end

/* DR2 split menu cells and menu views into classes absent from OPENSTEP 4.2. */
@interface DR2SeparatorItem : NSMenuItem
@end
@implementation DR2SeparatorItem
- (BOOL)isSeparatorItem {
    return YES;
}
@end
@implementation NSMenuItem (DR2Construction)
+ (id)separatorItem {
    id item = [[[DR2SeparatorItem alloc] initTextCell:@"----------------"] autorelease];
    [item setEnabled:NO];
    return item;
}
+ (NSString *)_userKeyEquivalentForTitle:(NSString *)title {
    return @"";
}
+ (unsigned)_userKeyEquivalentModifierMaskForTitle:(NSString *)title {
    return 0;
}
- (BOOL)isSeparatorItem {
    return NO;
}
- initWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)key {
    self = [self initTextCell:title];
    [self setAction:action];
    [self setKeyEquivalent:key];
    [self setImagePosition:NSImageLeft];
    return self;
}
@end
@interface NSMenuView : NSMatrix
@end
@implementation NSMenuView
@end
@implementation NSMatrix (DR2MenuView)
- (void)_setAllowsTearOffs:(BOOL)flag {
}
@end
@implementation NSMenu (DR2Construction)
- menuRepresentation {
    return [self itemMatrix];
}
- tearOffMenuRepresentation {
    return [self itemMatrix];
}
- (void)addItem:(id)item {
    [self insertItem:item atIndex:[[self itemArray] count]];
}
- (void)insertItem:(id)item atIndex:(unsigned)index {
    [self insertItemWithTitle:@"" action:NULL keyEquivalent:@"" atIndex:index];
    [[self itemMatrix] putCell:item atRow:index column:0];
    [self sizeToFit];
}
- (unsigned)numberOfItems {
    return [[self itemArray] count];
}
- itemAtIndex:(unsigned)index {
    return [[self itemArray] objectAtIndex:index];
}
- (unsigned)indexOfItem:(id)item {
    return [[self itemArray] indexOfObjectIdenticalTo:item];
}
@end

@interface DR2StatusItem : NSObject {
    NSMenu *menu;
}
- (NSMenu *)menu;
@end
static DR2StatusItem *applicationsItem;
@implementation DR2StatusItem
- (void)setMenu:(NSMenu *)value {
    [value retain];
    [menu release];
    menu = value;
}
- (NSMenu *)menu {
    return menu;
}
- (void)setTitle:(NSString *)value {
}
- (void)setImage:(NSImage *)value {
}
- (void)setHighlightMode:(BOOL)flag {
}
- (void)dealloc {
    [menu release];
    [super dealloc];
}
@end
@interface NSStatusBar : NSObject
@end
@implementation NSStatusBar
+ systemStatusBar {
    static NSStatusBar *bar;
    if (!bar)
        bar = [[self alloc] init];
    return bar;
}
- _statusItemWithLength:(float)length withPriority:(int)priority {
    applicationsItem = [[DR2StatusItem alloc] init];
    return [applicationsItem autorelease];
}
- (void)removeStatusItem:(id)item {
    if (applicationsItem == item)
        applicationsItem = nil;
}
@end

@interface DR2MenuBridge : NSObject {
    id controller;
    NSMenu *menu;
    NSMutableDictionary *applications;
    DR2RunningApplication *activeApplication;
    int activeContext;
    BOOL showNames;
    NSPanel *processPanel;
    NSBrowser *processBrowser;
    NSTextField *processPath;
    NSButton *activateButton;
    NSArray *processRows;
}
- initWithController:(id)value;
- (void)refresh:(id)sender;
- (void)updateMenu;
- (void)reloadProcesses;
- (void)showProcessesPanel:(id)sender;
- (void)switchActiveApplication:(id)sender;
- (void)hideActiveApp:(id)sender;
- (void)hideOtherApps:(id)sender;
- (void)showAllApps:(id)sender;
- (void)toggleShowAppNames:(id)sender;
- (void)selectProcess:(id)sender;
- (void)activateProcess:(id)sender;
@end

static void postApplicationEvent(int context, int subtype) {
    int success;
    PSposteventbycontext(NSAppKitDefined, 0, 0, 0, 0, 0, subtype, 0, 0, context, &success);
    if (!success)
        NSBeep();
}

@implementation DR2MenuBridge
- initWithController:(id)value {
    self = [super init];
    controller = [value retain];
    menu = [[applicationsItem menu] retain];
    applications = [[NSMutableDictionary alloc] init];
    showNames = [[NSUserDefaults standardUserDefaults] objectForKey:ShowNamesKey]
                    ? [[NSUserDefaults standardUserDefaults] boolForKey:ShowNamesKey]
                    : YES;
    [menu setAutoenablesItems:NO];
    return self;
}
- (DR2RunningApplication *)applicationForProcess:(int)pid {
    NSEnumerator *enumerator = [applications objectEnumerator];
    DR2RunningApplication *app;
    if (pid <= 0)
        return nil;
    while ((app = [enumerator nextObject])) {
        if ([app processID] == pid)
            return app;
    }
    return nil;
}
- (void)readProcessIDs {
    /* Workspace's public list has launch handles but no process IDs.
     * Resolve its app paths only when that list changes. */
    FILE *stream = popen("/bin/ps -axww", "r");
    char line[ProcessLineCapacity];
    if (!stream)
        return;
    while (fgets(line, sizeof(line), stream)) {
        int pid, offset = 0;
        NSEnumerator *enumerator;
        DR2RunningApplication *app;
        if (sscanf(line, "%d %*s %*s %*s %n", &pid, &offset) != 1 || !offset || pid <= 0)
            continue;
        enumerator = [applications objectEnumerator];
        while ((app = [enumerator nextObject])) {
            const char *path = [[app path] cString];
            unsigned length = strlen(path);
            if (!strncmp(line + offset, path, length) && line[offset + length] == '/')
                [app setProcessID:pid];
        }
    }
    pclose(stream);
}
- (void)updateMenu {
    NSArray *items = [menu itemArray];
    NSString *title =
        showNames && activeApplication ? [activeApplication displayName] : @"Workspace DR2";
    unsigned i;
    if (![[menu title] isEqual:title])
        [menu setTitle:title];
    for (i = 0; i < [items count]; i++) {
        id item = [items objectAtIndex:i];
        SEL action = [item action];
        if (action == @selector(switchActiveApplication:)) {
            [item setTarget:self];
            [item setState:[item representedObject] == activeApplication];
        } else if (action == @selector(hideActiveApp:)) {
            [item setTarget:self];
            [item setTitle:activeApplication
                               ? [@"Hide " stringByAppendingString:[activeApplication displayName]]
                               : @"Hide"];
            [item setEnabled:activeApplication != nil];
        } else if (action == @selector(hideOtherApps:)) {
            [item setTarget:self];
            [item setEnabled:activeApplication != nil];
        } else if (action == @selector(showAllApps:) || action == @selector(showProcessesPanel:)) {
            [item setTarget:self];
            [item setEnabled:YES];
        } else if (action == @selector(toggleShowAppNames:)) {
            [item setTarget:self];
            [item setTitle:showNames ? @"Hide Active App Name" : @"Show Active App Name"];
        }
    }
    [menu sizeToFit];
    [[menu itemMatrix] display];
}
- (void)refresh:(id)sender {
    char *paths = NULL;
    NSMutableArray *current = [NSMutableArray array];
    NSArray *records, *previous;
    DR2RunningApplication *active;
    unsigned i;
    int context, pid;
    BOOL changed = NO;
    if ([workspaceSpeaker() selectorRPC:@"getActiveAppPaths:" paramTypes:"C", &paths] || !paths)
        return;
    records = [[NSString stringWithCString:paths] componentsSeparatedByString:@"\t"];
    for (i = 0; i < [records count]; i++) {
        NSArray *fields = [[records objectAtIndex:i] componentsSeparatedByString:@"\n"];
        NSString *path;
        DR2RunningApplication *app;
        if ([fields count] != ApplicationRecordFields)
            continue;
        path = [fields objectAtIndex:1];
        [current addObject:path];
        app = [applications objectForKey:path];
        if (app && [app sequenceNumber] == [[fields objectAtIndex:3] intValue])
            continue;
        if (app)
            [controller removeApplication:app];
        app = [[DR2RunningApplication alloc] initWithFields:fields];
        [applications setObject:app forKey:path];
        [controller addApplication:app];
        [app release];
        changed = YES;
    }
    previous = [applications allKeys];
    for (i = 0; i < [previous count]; i++) {
        NSString *path = [previous objectAtIndex:i];
        if (![current containsObject:path]) {
            [controller removeApplication:[applications objectForKey:path]];
            [applications removeObjectForKey:path];
            changed = YES;
        }
    }
    if (changed)
        [self readProcessIDs];
    DR2ActiveProcess(&context, &pid);
    active = [self applicationForProcess:pid];
    /* A newly registered app may not have appeared in ps on the first pass. */
    if (pid > 0 && pid != getpid() && !active && !changed) {
        [self readProcessIDs];
        active = [self applicationForProcess:pid];
    }
    /* Opening this app's menu or panel must not change the Hide target. */
    if (pid != getpid() && active != activeApplication) {
        [active retain];
        [activeApplication release];
        activeApplication = active;
        activeContext = context;
        changed = YES;
    }
    if (activeApplication &&
        [applications objectForKey:[activeApplication path]] != activeApplication) {
        [activeApplication release];
        activeApplication = nil;
        changed = YES;
    }
    if (changed) {
        [self updateMenu];
        if (processPanel && [processPanel isVisible])
            [self reloadProcesses];
    }
}
- (void)switchActiveApplication:(id)sender {
    [[sender representedObject] activate];
}
- (void)hideActiveApp:(id)sender {
    int pid;
    DR2ContextProcess(activeContext, &pid);
    if (activeApplication && pid == [activeApplication processID])
        postApplicationEvent(activeContext, ApplicationHideEvent);
}
- (void)sendEventToApplications:(int)subtype except:(int)excludedContext {
    int count, *windows, i;
    NSMutableSet *visited = [NSMutableSet set];
    PScountwindowlist(0, &count);
    if (count <= 0)
        return;
    windows = calloc(count, sizeof(*windows));
    if (!windows)
        return;
    PSwindowlist(0, count, windows);
    for (i = 0; i < count; i++) {
        int context, pid;
        NSNumber *key;
        if (!windows[i])
            continue;
        DR2WindowProcess(windows[i], &context, &pid);
        key = [NSNumber numberWithInt:context];
        if (context && context != excludedContext && pid != getpid() &&
            [self applicationForProcess:pid] && ![visited containsObject:key]) {
            [visited addObject:key];
            postApplicationEvent(context, subtype);
        }
    }
    free(windows);
}
- (void)hideOtherApps:(id)sender {
    if (activeApplication)
        [self sendEventToApplications:ApplicationHideEvent except:activeContext];
}
- (void)showAllApps:(id)sender {
    [self sendEventToApplications:ApplicationUnhideEvent except:0];
}
- (void)toggleShowAppNames:(id)sender {
    showNames = !showNames;
    [[NSUserDefaults standardUserDefaults] setBool:showNames forKey:ShowNamesKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self updateMenu];
}
- (void)reloadProcesses {
    DR2RunningApplication *selection = [[processBrowser selectedCell] representedObject];
    NSString *selectedPath = [[selection path] retain];
    NSArray *keys = [[applications allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *rows = [NSMutableArray array];
    unsigned i;
    int selectedRow = -1;
    for (i = 0; i < [keys count]; i++) {
        DR2RunningApplication *app = [applications objectForKey:[keys objectAtIndex:i]];
        [rows addObject:app];
        if ([[app path] isEqual:selectedPath])
            selectedRow = i;
    }
    [rows retain];
    [processRows release];
    processRows = rows;
    [processBrowser loadColumnZero];
    if (selectedRow >= 0)
        [processBrowser selectRow:selectedRow inColumn:0];
    [selectedPath release];
    [self selectProcess:nil];
}
- (void)browser:(NSBrowser *)browser createRowsForColumn:(int)column inMatrix:(NSMatrix *)matrix {
    unsigned i;
    [matrix renewRows:[processRows count] columns:1];
    for (i = 0; i < [processRows count]; i++) {
        DR2RunningApplication *app = [processRows objectAtIndex:i];
        id cell = [matrix cellAtRow:i column:0];
        [cell setStringValue:[NSString stringWithFormat:@"%@   (PID %d)", [app displayName],
                                                        [app processID]]];
        [cell setRepresentedObject:app];
        [cell setLeaf:YES];
        [cell setLoaded:YES];
    }
}
- (void)selectProcess:(id)sender {
    DR2RunningApplication *app = [[processBrowser selectedCell] representedObject];
    [processPath setStringValue:app ? [app path] : @""];
    [activateButton setEnabled:app != nil];
}
- (void)activateProcess:(id)sender {
    [[[processBrowser selectedCell] representedObject] activate];
}
- (void)showProcessesPanel:(id)sender {
    if (!processPanel) {
        NSView *content;
        processPanel =
            [[NSPanel alloc] initWithContentRect:NSMakeRect(260, 260, 480, 280)
                                       styleMask:NSTitledWindowMask | NSClosableWindowMask
                                         backing:NSBackingStoreBuffered
                                           defer:NO];
        [processPanel setTitle:@"Processes"];
        [processPanel setReleasedWhenClosed:NO];
        content = [processPanel contentView];
        processBrowser = [[NSBrowser alloc] initWithFrame:NSMakeRect(12, 78, 456, 190)];
        [processBrowser setMaxVisibleColumns:1];
        [processBrowser setHasHorizontalScroller:NO];
        [processBrowser setAllowsMultipleSelection:NO];
        [processBrowser setTitle:@"Running Applications" ofColumn:0];
        [processBrowser setDelegate:self];
        [processBrowser setTarget:self];
        [processBrowser setAction:@selector(selectProcess:)];
        [processBrowser setDoubleAction:@selector(activateProcess:)];
        [content addSubview:processBrowser];
        processPath = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 48, 456, 22)];
        [processPath setEditable:NO];
        [processPath setSelectable:YES];
        [content addSubview:processPath];
        activateButton = [[NSButton alloc] initWithFrame:NSMakeRect(360, 10, 108, 28)];
        [activateButton setTitle:@"Activate"];
        [activateButton setTarget:self];
        [activateButton setAction:@selector(activateProcess:)];
        [content addSubview:activateButton];
    }
    [self reloadProcesses];
    [NSApp activateIgnoringOtherApps:YES];
    [processPanel makeKeyAndOrderFront:nil];
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSWindow *window = [[menu itemMatrix] window];
    [window setHidesOnDeactivate:NO];
    [window _setAvoidsActivation:YES];
    [self refresh:nil];
    [self updateMenu];
    [NSTimer scheduledTimerWithTimeInterval:RefreshInterval
                                     target:self
                                   selector:@selector(refresh:)
                                   userInfo:nil
                                    repeats:YES];
}
@end

int WorkspaceDR2Main(int argc, char **argv) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    Class processMenu = NSClassFromString(@"ProcessMenu");
    id controller;
    NSMenu *menu;
    DR2MenuBridge *bridge;
    /* ProcessMenu has no own ivars; DR2's NSMenu instance was smaller. */
    processMenu->instance_size = [NSMenu class]->instance_size;
    [NSApplication sharedApplication];
    controller = [[NSClassFromString(@"ProcessMenuController") alloc] init];
    menu = [applicationsItem menu];
    [menu setTitle:@"Workspace DR2"];
    [[menu addItemWithTitle:@"Quit" action:@selector(terminate:)
              keyEquivalent:@"q"] setTarget:NSApp];
    [NSApp setMainMenu:menu];
    bridge = [[DR2MenuBridge alloc] initWithController:controller];
    [NSApp setDelegate:bridge];
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp run];
    [pool release];
    return 0;
}
