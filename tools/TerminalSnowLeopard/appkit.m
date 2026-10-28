/* Native windows host one Snow Leopard shell controller each. */
static NSMutableDictionary *snowPanelFileTypes;
static NSArray *snowPanelExtensions(NSArray *types) {
    NSArray *declarations =
        [[[NSBundle mainBundle] infoDictionary] objectForKey:@"UTExportedTypeDeclarations"];
    NSMutableArray *extensions = [NSMutableArray array];
    unsigned i, j;
    for (i = 0; i < [types count]; i++) {
        NSString *type = [types objectAtIndex:i];
        id matches = nil;
        for (j = 0; j < [declarations count]; j++) {
            NSDictionary *definition = [declarations objectAtIndex:j];
            if ([[definition objectForKey:@"UTTypeIdentifier"] isEqual:type]) {
                matches = [[definition objectForKey:@"UTTypeTagSpecification"]
                    objectForKey:@"public.filename-extension"];
                break;
            }
        }
        if ([matches isKindOfClass:[NSString class]])
            [extensions addObject:matches];
        else if ([matches isKindOfClass:[NSArray class]])
            [extensions addObjectsFromArray:matches];
        else if ([type hasPrefix:@"public."] || [type hasPrefix:@"com.apple."])
            return nil; /* Native file panels cannot filter content-based types. */
        else
            [extensions addObject:type];
    }
    return [extensions count] ? extensions : nil;
}
@implementation NSWorkspace (SnowFileTypes)
- (NSString *)typeOfFile:(NSString *)path error:(NSError **)error {
    struct stat info;
    NSArray *declarations;
    NSString *extension;
    unsigned i;
    if (error)
        *error = nil;
    if (stat([path fileSystemRepresentation], &info) != 0) {
        if (error)
            *error = [NSError errorWithDomain:@"NSPOSIXErrorDomain" code:errno userInfo:nil];
        return nil;
    }
    if ((info.st_mode & S_IFMT) == S_IFDIR)
        return @"public.directory";
    extension = [[path pathExtension] lowercaseString];
    declarations =
        [[[NSBundle mainBundle] infoDictionary] objectForKey:@"UTExportedTypeDeclarations"];
    for (i = 0; i < [declarations count]; i++) {
        NSDictionary *definition = [declarations objectAtIndex:i];
        id extensions = [[definition objectForKey:@"UTTypeTagSpecification"]
            objectForKey:@"public.filename-extension"];
        if (([extensions isKindOfClass:[NSString class]] && [extensions isEqual:extension]) ||
            ([extensions isKindOfClass:[NSArray class]] && [extensions containsObject:extension]))
            return [definition objectForKey:@"UTTypeIdentifier"];
    }
    return access([path fileSystemRepresentation], X_OK) == 0 ? @"public.unix-executable"
                                                              : @"public.data";
}
@end
static IMP snowNativeOpenPanelModal;
static int snowOpenPanelModal(id panel, SEL selector, id path, id file, NSArray *types) {
    return ((int (*)(id, SEL, id, id, id))snowNativeOpenPanelModal)(panel, selector, path, file,
                                                                    snowPanelExtensions(types));
}
@implementation NSSavePanel (SnowFileTypes)
- (void)setAllowedFileTypes:(NSArray *)types {
    NSValue *key = [NSValue valueWithPointer:self];
    if (!snowPanelFileTypes)
        snowPanelFileTypes = [[NSMutableDictionary alloc] init];
    if (types)
        [snowPanelFileTypes setObject:[[types snowCopy] autorelease] forKey:key];
    else
        [snowPanelFileTypes removeObjectForKey:key];
    if (![self isKindOfClass:[NSOpenPanel class]]) {
        NSArray *extensions = snowPanelExtensions(types);
        [self setRequiredFileType:[extensions count] ? [extensions objectAtIndex:0] : nil];
    }
}
- (NSArray *)allowedFileTypes {
    return [snowPanelFileTypes objectForKey:[NSValue valueWithPointer:self]];
}
@end
@implementation NSOpenPanel (SnowModalFileTypes)
- (int)runModal {
    return [self runModalForDirectory:[self directory] file:nil types:[self allowedFileTypes]];
}
@end
@implementation NSControl (SnowFormatter)
- (void)setFormatter:(NSFormatter *)formatter {
    [[self cell] setFormatter:formatter];
}
- (id)formatter {
    return [[self cell] formatter];
}
@end
@implementation NSView (SnowSubviews)
- (void)setSubviews:(NSArray *)views {
    NSArray *previous = [[self subviews] snowCopy];
    NSArray *replacement = [views snowCopy];
    unsigned i;
    for (i = 0; i < [previous count]; i++)
        [[previous objectAtIndex:i] removeFromSuperview];
    for (i = 0; i < [replacement count]; i++)
        [self addSubview:[replacement objectAtIndex:i]];
    [previous release];
    [replacement release];
    [self setNeedsDisplay:YES];
}
@end
@implementation NSTabView (SnowSelectedIdentifier)
- (id)selectedIdentifier {
    return [[self selectedTabViewItem] identifier];
}
- (void)setSelectedIdentifier:(id)identifier {
    unsigned i;
    for (i = 0; i < [self numberOfTabViewItems]; i++) {
        NSTabViewItem *item = [self tabViewItemAtIndex:i];
        if ([[item identifier] isEqual:identifier]) {
            [self selectTabViewItem:item];
            break;
        }
    }
}
@end
void SnowShowSystemInfoPanel(NSDictionary *options) {
    NSRunAlertPanel(
        @"Terminal",
        @"Mac OS X Snow Leopard Terminal for OPENSTEP 4.2.\nCopyright 1995-2010 Apple Inc.", @"OK",
        nil, nil);
}
/* OPENSTEP places popup behavior in the control. Keep the Cocoa cell's
 * 128-byte base layout for TTPopUpButtonCell and delegate its menu tracking
 * to a native popup control when a custom cell is used outside a nib. */
@interface NSPopUpButtonCell : NSButtonCell {
    NSPopUpButton *snowPopup;
    char snowPopupReserved[56];
}
@end
@implementation NSPopUpButtonCell
- (NSPopUpButton *)snowPopup {
    if (!snowPopup)
        snowPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    return snowPopup;
}
- initTextCell:(NSString *)title pullsDown:(BOOL)flag {
    self = [super initTextCell:title];
    [[self snowPopup] setPullsDown:flag];
    return self;
}
- (void)setPullsDown:(BOOL)flag {
    [[self snowPopup] setPullsDown:flag];
}
- (BOOL)pullsDown {
    return [[self snowPopup] pullsDown];
}
- (NSArray *)itemArray {
    return [[self snowPopup] itemArray];
}
- (int)numberOfItems {
    return [[self snowPopup] numberOfItems];
}
- (void)addItemWithTitle:(NSString *)title {
    [[self snowPopup] addItemWithTitle:title];
}
- (void)removeAllItems {
    [[self snowPopup] removeAllItems];
}
- (void)selectItemAtIndex:(int)index {
    [[self snowPopup] selectItemAtIndex:index];
    [self setStringValue:[[self snowPopup] titleOfSelectedItem]];
}
- (int)indexOfSelectedItem {
    return [[self snowPopup] indexOfSelectedItem];
}
- (id)selectedItem {
    return [[self snowPopup] selectedItem];
}
- (BOOL)trackMouse:(NSEvent *)event
            inRect:(NSRect)rect
            ofView:(NSView *)view
      untilMouseUp:(BOOL)untilMouseUp {
    NSPopUpButton *popup = [self snowPopup];
    [popup setFrame:rect];
    [view addSubview:popup];
    [popup mouseDown:event];
    [self setStringValue:[popup titleOfSelectedItem]];
    [popup removeFromSuperview];
    [view setNeedsDisplay:YES];
    [NSApp sendAction:[self action] to:[self target] from:view];
    return YES;
}
- (void)dealloc {
    [snowPopup release];
    [super dealloc];
}
@end
@interface NSFont (SnowFontSizes)
+ (float)systemFontSize;
+ (float)smallSystemFontSize;
+ (void)initializeUserAndSystemFonts;
@end
static void SnowInitializeNibCell(id cell) {
    Class cls = NSClassFromString(@"TTSettingsSourceCell");
    if ([cell isKindOfClass:cls]) {
        NSTextFieldCell *title = [[NSTextFieldCell alloc] initTextCell:@""];
        NSTextFieldCell *badge = [[NSTextFieldCell alloc] initTextCell:@"Default"];
        NSImageCell *thumbnail = [[NSImageCell alloc] init];
        [title setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
        [badge setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
        [title setWraps:NO];
        [badge setWraps:NO];
        *(id *)((char *)cell + class_getInstanceVariable(cls, "_titleCell")->ivar_offset) = title;
        *(id *)((char *)cell + class_getInstanceVariable(cls, "_defaultCell")->ivar_offset) = badge;
        *(id *)((char *)cell + class_getInstanceVariable(cls, "_thumbnailCell")->ivar_offset) =
            thumbnail;
    }
}
static NSMenu *snowApplicationDockMenu;
static NSMutableDictionary *snowHiddenMenuItems;
static NSMutableDictionary *snowMenuDelegates;
static NSMutableDictionary *snowWindowControllers;
static NSMutableDictionary *snowWindowZoomStates;
static IMP snowNativeWindowDealloc;
static IMP snowNativeFrameString;
static BOOL snowFrameString(id window, SEL selector, id value) {
    value = snowDecodeDefault(value);
    if (![value isKindOfClass:[NSString class]])
        return NO;
    return ((BOOL(*)(id, SEL, id))snowNativeFrameString)(window, selector, value);
}
static void snowWindowDealloc(NSWindow *window, SEL selector) {
    NSValue *key = [NSValue valueWithPointer:window];
    [snowPanelFileTypes removeObjectForKey:key];
    [snowWindowControllers removeObjectForKey:key];
    [snowWindowZoomStates removeObjectForKey:key];
    ((void (*)(id, SEL))snowNativeWindowDealloc)(window, selector);
}
static id snowFontTarget;
static IMP snowNativeFontAction;
@implementation NSFontManager (SnowFontTarget)
- (void)setTarget:(id)target {
    snowFontTarget = target;
}
- (id)target {
    return snowFontTarget;
}
@end
static BOOL snowFontAction(NSFontManager *manager, SEL action) {
    if (snowFontTarget)
        return [NSApp sendAction:[manager action] to:snowFontTarget from:manager];
    return ((BOOL(*)(id, SEL))snowNativeFontAction)(manager, action);
}
static IMP snowNativeFirstResponder;
static IMP snowNativeOrderWindow;
static void snowOrderWindow(NSWindow *window, SEL action, int place, int relative) {
    if (place && [window isKindOfClass:NSClassFromString(@"TTWindow")]) {
        NSRect frame = [window frame], screen = [[NSScreen mainScreen] frame];
        if (NSMaxY(frame) > NSMaxY(screen))
            frame.origin.y = NSMaxY(screen) - frame.size.height;
        if (NSMaxX(frame) > NSMaxX(screen))
            frame.origin.x = NSMaxX(screen) - frame.size.width;
        if (frame.origin.y < screen.origin.y)
            frame.origin.y = screen.origin.y;
        if (frame.origin.x < screen.origin.x)
            frame.origin.x = screen.origin.x;
        [window setFrameOrigin:frame.origin];
    }
    ((void (*)(id, SEL, int, int))snowNativeOrderWindow)(window, action, place, relative);
}
static NSView *snowTerminalInView(NSView *view) {
    NSArray *children;
    unsigned i;
    if ([view isKindOfClass:NSClassFromString(@"TTView")])
        return view;
    children = [view subviews];
    for (i = 0; i < [children count]; i++) {
        NSView *found = snowTerminalInView([children objectAtIndex:i]);
        if (found)
            return found;
    }
    return nil;
}
static BOOL snowMakeFirstResponder(NSWindow *window, SEL action, id responder) {
    if ([responder isKindOfClass:NSClassFromString(@"TTTabView")]) {
        NSView *terminal = snowTerminalInView(responder);
        if (terminal)
            responder = terminal;
    }
    return ((BOOL(*)(id, SEL, id))snowNativeFirstResponder)(window, action, responder);
}
static NSMutableArray *snowHelpSearchHandlers;
static BOOL snowHelpBookSearchEnabled = YES;
/* OPENSTEP has no system-wide display zoom service. */
BOOL UAZoomEnabled(void) {
    return NO;
}
void UAZoomChangeFocus(void *focus, void *window, unsigned options) {}
@implementation NSApplication (SnowHelpSearch)
/* OPENSTEP has no Help-menu search field. Preserve registration ownership. */
- (void)registerUserInterfaceItemSearchHandler:(id)handler {
    if (!snowHelpSearchHandlers)
        snowHelpSearchHandlers = [[NSMutableArray alloc] init];
    if (handler && ![snowHelpSearchHandlers containsObject:handler])
        [snowHelpSearchHandlers addObject:handler];
}
- (void)unregisterUserInterfaceItemSearchHandler:(id)handler {
    [snowHelpSearchHandlers removeObjectIdenticalTo:handler];
}
- (void)setDefaultHelpBookSearchEnabled:(BOOL)enabled {
    snowHelpBookSearchEnabled = enabled;
}
- (BOOL)defaultHelpBookSearchEnabled {
    return snowHelpBookSearchEnabled;
}
@end
@implementation NSInputManager (SnowMouseInput)
/* The native input manager handles keyboard composition only. */
- (BOOL)wantsToHandleMouseEvents {
    return NO;
}
- (BOOL)handleMouseEvent:(NSEvent *)event {
    return NO;
}
@end
@implementation NSEvent (SnowMouseLocation)
+ (NSPoint)mouseLocation {
    NSWindow *window = [NSApp keyWindow];
    if (!window)
        window = [NSApp mainWindow];
    if (!window && [[NSApp windows] count])
        window = [[NSApp windows] objectAtIndex:0];
    return window ? [window convertBaseToScreen:[window mouseLocationOutsideOfEventStream]]
                  : NSZeroPoint;
}
@end
@implementation NSWindow (SnowWindowController)
- (void)setWindowController:(id)controller {
    NSValue *key = [NSValue valueWithPointer:self];
    if (!snowWindowControllers)
        snowWindowControllers = [[NSMutableDictionary alloc] init];
    if (controller)
        [snowWindowControllers setObject:[NSValue valueWithNonretainedObject:controller]
                                  forKey:key];
    else
        [snowWindowControllers removeObjectForKey:key];
}
- (id)windowController {
    return [[snowWindowControllers objectForKey:[NSValue valueWithPointer:self]]
        nonretainedObjectValue];
}
@end
@interface NSObject (SnowStandardWindowFrame)
- (NSRect)windowWillUseStandardFrame:(NSWindow *)window defaultFrame:(NSRect)frame;
@end
@interface NSScreen (SnowVisibleFrameDeclaration)
- (NSRect)visibleFrame;
@end
@implementation NSWindow (SnowWindowZoom)
- (void)performZoom:(id)sender {
    NSValue *key = [NSValue valueWithPointer:self];
    NSDictionary *saved = [snowWindowZoomStates objectForKey:key];
    NSScreen *screen = [self screen];
    NSRect current = [self frame], standard = [screen ? screen : [NSScreen mainScreen] frame];
    id delegate = [self delegate];
    if (saved && NSEqualRects(current, [[saved objectForKey:@"standard"] rectValue])) {
        [self setFrame:[[saved objectForKey:@"previous"] rectValue] display:YES];
        [snowWindowZoomStates removeObjectForKey:key];
        return;
    }
    if ([delegate respondsToSelector:@selector(windowWillUseStandardFrame:defaultFrame:)])
        standard = [delegate windowWillUseStandardFrame:self defaultFrame:standard];
    {
        NSRect available = [screen ? screen : [NSScreen mainScreen] visibleFrame];
        if (standard.size.width > available.size.width)
            standard.size.width = available.size.width;
        if (standard.size.height > available.size.height)
            standard.size.height = available.size.height;
        if (standard.origin.x + standard.size.width > available.origin.x + available.size.width)
            standard.origin.x = available.origin.x + available.size.width - standard.size.width;
        if (standard.origin.y + standard.size.height > available.origin.y + available.size.height)
            standard.origin.y = available.origin.y + available.size.height - standard.size.height;
        if (standard.origin.x < available.origin.x)
            standard.origin.x = available.origin.x;
        if (standard.origin.y < available.origin.y)
            standard.origin.y = available.origin.y;
    }
    if (!snowWindowZoomStates)
        snowWindowZoomStates = [[NSMutableDictionary alloc] init];
    [snowWindowZoomStates
        setObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSValue valueWithRect:current],
                                                             @"previous",
                                                             [NSValue valueWithRect:standard],
                                                             @"standard", nil]
           forKey:key];
    [self setFrame:standard display:YES];
}
@end
@implementation NSApplication (SnowWindowActions)
- (void)hideOtherApplications:(id)sender {
    [[NSWorkspace sharedWorkspace] hideOtherApplications];
}
- (void)_cycleWindows:(id)sender {
    NSArray *windows = [self windows];
    unsigned i, count = [windows count],
                current = [windows indexOfObjectIdenticalTo:[self keyWindow]];
    if (!count)
        return;
    if (current == NSNotFound)
        current = count - 1;
    for (i = 1; i <= count; i++) {
        NSWindow *window = [windows objectAtIndex:(current + i) % count];
        if ([window isKindOfClass:NSClassFromString(@"TTWindow")] && [window isVisible] &&
            ![window isMiniaturized]) {
            [window makeKeyAndOrderFront:sender];
            break;
        }
    }
}
@end
@implementation NSWindowController (SnowWindowAssociation)
- initWithWindowNibName:(NSString *)name owner:(id)owner {
    id original = self;
    /* Cocoa's nib initializer goes through initWithWindow:. Stock
     * subclasses use that entry point to register their shared controller. */
    self = [self initWithWindow:nil];
    if (self) {
        [tigerNibName release];
        tigerNibName = [name snowCopy];
        tigerOwner = owner == original ? self : owner;
    }
    return self;
}
- (void)setWindow:(NSWindow *)window {
    if (tigerWindow == window)
        return;
    [tigerWindow setWindowController:nil];
    [window retain];
    [tigerWindow release];
    tigerWindow = window;
    [window setWindowController:self];
}
- (void)dealloc {
    /* A closed native window can outlive its controller. Clear its weak
     * association before releasing the controller's ownership. */
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if ([tigerWindow delegate] == self)
        [tigerWindow setDelegate:nil];
    [tigerWindow setWindowController:nil];
    [tigerWindow release];
    [tigerNibName release];
    [super dealloc];
}
@end
@implementation NSCell (SnowLineBreak)
- (void)setTitle:(NSString *)title {
    [self setStringValue:title];
}
- (NSString *)title {
    return [self stringValue];
}
/* Native cells draw against OPENSTEP's control palette. */
- (void)setBackgroundStyle:(unsigned)style {
}
- (unsigned)backgroundStyle {
    return 0;
}
- (unsigned)interiorBackgroundStyle {
    return [self isHighlighted] ? 1 : 0;
}
- (void)setLineBreakMode:(unsigned)mode {
    [self setWraps:mode < 2];
}
- (unsigned)lineBreakMode {
    return [self wraps] ? 0 : 2;
}
@end
/* A transparent placeholder keeps hidden controls in native autoresizing.
 * Its ownership follows the superview, rather than a global retained cache. */
static NSMutableDictionary *snowHiddenViews;
@interface SnowHiddenView : NSView {
  @public
    NSView *content;
}
@end
@implementation SnowHiddenView
- (void)dealloc {
    if (content)
        [snowHiddenViews removeObjectForKey:[NSValue valueWithPointer:content]];
    [content release];
    [super dealloc];
}
@end
@implementation NSView (SnowFocusRing)
- (BOOL)isHidden {
    return [snowHiddenViews objectForKey:[NSValue valueWithPointer:self]] != nil;
}
- (BOOL)isHiddenOrHasHiddenAncestor {
    return [self isHidden] || [[self superview] isHiddenOrHasHiddenAncestor];
}
- (void)setHidden:(BOOL)hidden {
    NSValue *key = [NSValue valueWithPointer:self];
    SnowHiddenView *placeholder = [[snowHiddenViews objectForKey:key] nonretainedObjectValue];
    if (hidden && !placeholder && [self superview]) {
        NSView *parent = [self superview];
        placeholder = [[SnowHiddenView alloc] initWithFrame:[self frame]];
        [placeholder setAutoresizingMask:[self autoresizingMask]];
        placeholder->content = [self retain];
        if (!snowHiddenViews)
            snowHiddenViews = [[NSMutableDictionary alloc] init];
        [snowHiddenViews setObject:[NSValue valueWithNonretainedObject:placeholder] forKey:key];
        [parent replaceSubview:self with:placeholder];
        [placeholder release];
        [parent setNeedsDisplay:YES];
    } else if (!hidden && placeholder) {
        NSView *parent = [placeholder superview];
        [self retain];
        [self setFrame:[placeholder frame]];
        [parent replaceSubview:placeholder with:self];
        [parent setNeedsDisplay:YES];
        [self release];
    }
}
- (void)translateRectsNeedingDisplayInRect:(NSRect)rect by:(NSSize)delta {
    /* Native AppKit keeps one damage region. Repaint both positions after
     * the stock renderer scrolls its backing store. */
    [self setNeedsDisplayInRect:NSUnionRect(rect, NSOffsetRect(rect, delta.width, delta.height))];
}
- (float)_autoscrollScreenEdgeFactorFromPoint:(NSPoint)point {
    NSRect screen = [[[self window] screen] frame];
    point = [[self window] convertBaseToScreen:point];
    /* Continue selecting while the pointer rests against the display edge. */
    return point.y <= NSMinY(screen) + 1 ? 14 : 0;
}
- (void)getRectsBeingDrawn:(const NSRect **)rects count:(int *)count {
    static NSRect visible;
    visible = [self visibleRect];
    if (rects)
        *rects = &visible;
    if (count)
        *count = 1;
}
- (BOOL)needsToDrawRect:(NSRect)rect {
    return NSIntersectsRect(rect, [self visibleRect]);
}
/* OPENSTEP uses an outline while the window frame is being resized. */
- (BOOL)inLiveResize {
    return NO;
}
/* Native controls draw their focus indicator as part of their border. */
- (void)setFocusRingType:(unsigned)type {
}
- (unsigned)focusRingType {
    return 2;
}
@end
@implementation NSResponder (SnowMenuValidation)
- (BOOL)validateMenuItem:(id)item {
    if ([item action] == @selector(undo:))
        return [[self undoManager] canUndo];
    if ([item action] == @selector(redo:))
        return [[self undoManager] canRedo];
    return [self respondsToSelector:[item action]];
}
@end
@implementation NSSplitView (SnowDivider)
/* OPENSTEP supplies one divider appearance, drawn by the native split view. */
- (void)setDividerStyle:(unsigned)style {
}
- (unsigned)dividerStyle {
    return 1;
}
@end
static NSMutableDictionary *snowTableDragMasks;
@implementation NSTableView (SnowDragging)
- (void)setDraggingSourceOperationMask:(unsigned)mask forLocal:(BOOL)local {
    NSString *key = [NSString stringWithFormat:@"%x:%d", (unsigned)self, local != 0];
    if (!snowTableDragMasks)
        snowTableDragMasks = [[NSMutableDictionary alloc] init];
    [snowTableDragMasks setObject:[NSNumber numberWithUnsignedInt:mask] forKey:key];
}
- (unsigned)draggingSourceOperationMaskForLocal:(BOOL)local {
    return [[snowTableDragMasks
        objectForKey:[NSString stringWithFormat:@"%x:%d", (unsigned)self, local != 0]]
        unsignedIntValue];
}
@end
@implementation NSScroller (SnowControlSize)
- (void)setDoubleValue:(double)value {
    [self setFloatValue:value knobProportion:[self knobProportion]];
}
- (double)doubleValue {
    return [self floatValue];
}
- (void)setKnobProportion:(float)proportion {
    [self setFloatValue:[self floatValue] knobProportion:proportion];
}
+ (float)scrollerWidthForControlSize:(unsigned)size {
    return [self scrollerWidth];
}
- (void)setControlSize:(unsigned)size {
}
- (unsigned)controlSize {
    return 0;
}
@end
@implementation NSWindow (SnowWindowFrame)
/* OPENSTEP has one desktop; Spaces and full-screen collection flags do not
 * alter the native window manager's ordering or visibility rules. */
- (void)setCollectionBehavior:(unsigned)behavior {
}
- (unsigned)collectionBehavior {
    return 0;
}
- (void)setContentResizeIncrements:(NSSize)size {
    [self setResizeIncrements:size];
}
- (NSSize)contentResizeIncrements {
    return [self resizeIncrements];
}
- (void)setContentMinSize:(NSSize)size {
    [self setMinSize:[NSWindow frameRectForContentRect:NSMakeRect(0, 0, size.width, size.height)
                                             styleMask:[self styleMask]]
                         .size];
}
- (void)setContentMaxSize:(NSSize)size {
    [self setMaxSize:[NSWindow frameRectForContentRect:NSMakeRect(0, 0, size.width, size.height)
                                             styleMask:[self styleMask]]
                         .size];
}
- (NSSize)contentMinSize {
    NSSize size = [self minSize];
    return [NSWindow contentRectForFrameRect:NSMakeRect(0, 0, size.width, size.height)
                                   styleMask:[self styleMask]]
        .size;
}
- (NSSize)contentMaxSize {
    NSSize size = [self maxSize];
    return [NSWindow contentRectForFrameRect:NSMakeRect(0, 0, size.width, size.height)
                                   styleMask:[self styleMask]]
        .size;
}
- (NSRect)contentRectForFrameRect:(NSRect)rect {
    return [NSWindow contentRectForFrameRect:rect styleMask:[self styleMask]];
}
- (NSRect)frameRectForContentRect:(NSRect)rect {
    return [NSWindow frameRectForContentRect:rect styleMask:[self styleMask]];
}
/* OPENSTEP's application windows are opaque. */
- (void)setOpaque:(BOOL)opaque {
}
- (BOOL)isOpaque {
    return YES;
}
/* The native window manager owns the shape of OPENSTEP window frames. */
- (void)setBottomCornerRounded:(BOOL)rounded {
}
@end
@interface NSMenu (SnowMenus)
- (void)insertItem:(id)item atIndex:(unsigned)index;
- (NSMatrix *)itemMatrix;
@end
static IMP snowNativeMenuCellDealloc, snowNativeMenuCellKeyEquivalent, snowButtonCellKeyEquivalent;
static NSString *snowDeallocatingMenuCellKey = @"SnowDeallocatingMenuCell";
static void snowMenuCellKeyEquivalent(id cell, SEL action, NSString *key) {
    id dying =
        [[[NSThread currentThread] threadDictionary] objectForKey:snowDeallocatingMenuCellKey];
    IMP implementation = [dying pointerValue] == cell ? snowButtonCellKeyEquivalent
                                                      : snowNativeMenuCellKeyEquivalent;
    ((void (*)(id, SEL, id))implementation)(cell, action, key);
}
static void snowMenuCellDealloc(id cell, SEL action) {
    NSMutableDictionary *thread = [[NSThread currentThread] threadDictionary];
    id previous = [[thread objectForKey:snowDeallocatingMenuCellKey] retain];
    /* NSButtonCell's teardown sends setKeyEquivalent: back to NSMenuCell.
     * Do not reinsert the dying cell into AppKit's shortcut dictionary. */
    [thread setObject:[NSValue valueWithPointer:cell] forKey:snowDeallocatingMenuCellKey];
    ((void (*)(id, SEL))snowNativeMenuCellDealloc)(cell, action);
    if (previous)
        [thread setObject:previous forKey:snowDeallocatingMenuCellKey];
    else
        [thread removeObjectForKey:snowDeallocatingMenuCellKey];
    [previous release];
}
static void snowInitializeMenuCells(void) {
    Class cls = NSClassFromString(@"NSMenuCell");
    Method method;
    method = class_getInstanceMethod(cls, @selector(dealloc));
    snowNativeMenuCellDealloc = method->method_imp;
    method->method_imp = (IMP)snowMenuCellDealloc;
    method = class_getInstanceMethod(cls, @selector(setKeyEquivalent:));
    snowNativeMenuCellKeyEquivalent = method->method_imp;
    method->method_imp = (IMP)snowMenuCellKeyEquivalent;
    snowButtonCellKeyEquivalent =
        class_getInstanceMethod([NSButtonCell class], @selector(setKeyEquivalent:))->method_imp;
}
static NSMenu *snowFindMenu(NSMenu *menu, id sought) {
    NSArray *items = [menu itemArray];
    unsigned i;
    if ([items containsObject:sought])
        return menu;
    for (i = 0; i < [items count]; i++) {
        id submenu = [[items objectAtIndex:i] target];
        NSMenu *found;
        if (![submenu isKindOfClass:[NSMenu class]])
            continue;
        found = snowFindMenu(submenu, sought);
        if (found)
            return found;
    }
    return nil;
}
@implementation NSApplication (SnowDockMenu)
- (void)setDockMenu:(NSMenu *)menu {
    [menu retain];
    [snowApplicationDockMenu release];
    snowApplicationDockMenu = menu;
}
- (NSMenu *)dockMenu {
    return snowApplicationDockMenu;
}
@end
@implementation NSMenuItem (SnowMenus)
- (NSMenu *)menu {
    NSMenu *menu = snowFindMenu([NSApp mainMenu], self);
    return menu ? menu : snowFindMenu(snowApplicationDockMenu, self);
}
- (void)setHidden:(BOOL)hidden {
    NSValue *key = [NSValue valueWithPointer:self];
    NSDictionary *record = [snowHiddenMenuItems objectForKey:key];
    if (hidden && !record) {
        NSMenu *menu = [self menu];
        id submenu = [self submenu];
        unsigned index;
        if (!menu)
            return;
        index = [menu indexOfItem:self];
        if (!snowHiddenMenuItems)
            snowHiddenMenuItems = [[NSMutableDictionary alloc] init];
        record = [NSDictionary
            dictionaryWithObjectsAndKeys:self, @"item", [NSValue valueWithNonretainedObject:menu],
                                         @"menu", [NSNumber numberWithUnsignedInt:index], @"index",
                                         submenu ? submenu : [NSNull null], @"submenu", nil];
        [snowHiddenMenuItems setObject:record forKey:key];
        [menu removeItem:self];
    } else if (!hidden && record) {
        NSMenu *menu = [[record objectForKey:@"menu"] nonretainedObjectValue];
        unsigned index = [[record objectForKey:@"index"] unsignedIntValue];
        id submenu = [record objectForKey:@"submenu"];
        if (index > (unsigned)[menu numberOfItems])
            index = [menu numberOfItems];
        [menu insertItem:self atIndex:index];
        if (submenu != [NSNull null])
            [menu setSubmenu:submenu forItem:self];
        [snowHiddenMenuItems removeObjectForKey:key];
    }
}
- (BOOL)isHidden {
    return [snowHiddenMenuItems objectForKey:[NSValue valueWithPointer:self]] != nil;
}
- (NSMenu *)submenu {
    NSEnumerator *parents = [tigerMenuChildren objectEnumerator];
    NSDictionary *children;
    id value;
    NSValue *key = [NSValue valueWithPointer:self];
    while ((children = [parents nextObject]))
        if ((value = [children objectForKey:key]))
            return value;
    return nil;
}
- (void)setSubmenu:(NSMenu *)submenu {
    if (submenu) {
        [self setTarget:submenu];
        [self setAction:@selector(submenuAction:)];
    } else {
        [self setTarget:nil];
        [self setAction:NULL];
    }
}
- (BOOL)isSeparatorItem {
    return [[self title] isEqual:@"-"];
}
+ (id)separatorItem {
    return [[[self alloc] initWithTitle:@"-" action:NULL keyEquivalent:@""] autorelease];
}
- initWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)key {
    NSMenu *temporary = [[NSMenu alloc] initWithTitle:@""];
    id result = [(id)[temporary addItemWithTitle:title action:action keyEquivalent:key] retain];
    [temporary removeItem:result];
    [temporary release];
    [self release];
    return result;
}
@end
@implementation NSMenu (SnowMenus)
- (void)insertItem:(id)item atIndex:(unsigned)index {
    [self insertItemWithTitle:@"" action:NULL keyEquivalent:@"" atIndex:index];
    [[self itemMatrix] putCell:item atRow:index column:0];
    [self sizeToFit];
}
- (void)addItem:(id)item {
    [self insertItem:item atIndex:[self numberOfItems]];
}
- (void)setDelegate:(id)delegate {
    NSValue *key = [NSValue valueWithPointer:self];
    if (!snowMenuDelegates)
        snowMenuDelegates = [[NSMutableDictionary alloc] init];
    if (delegate)
        [snowMenuDelegates setObject:[NSValue valueWithNonretainedObject:delegate] forKey:key];
    else
        [snowMenuDelegates removeObjectForKey:key];
}
- (id)delegate {
    return
        [[snowMenuDelegates objectForKey:[NSValue valueWithPointer:self]] nonretainedObjectValue];
}
@end
static void SnowReplaceMethod(Class cls, const char *name, IMP implementation) {
    Method method = class_getInstanceMethod(cls, sel_getUid(name));
    if (!method)
        [NSException raise:NSInternalInconsistencyException
                    format:@"Missing Snow Leopard method %s", name];
    method->method_imp = implementation;
}
/* Keep OPENSTEP's -1 menu result in its own AppKit call sites. */
@implementation NSMenu (SnowSearchSemantics)
- (int)snowIndexOfItem:(id)item {
    return [[self itemArray] indexOfObjectIdenticalTo:item];
}
- (int)snowIndexOfItemWithTarget:(id)target andAction:(SEL)action {
    NSArray *items = [self itemArray];
    unsigned i;
    for (i = 0; i < [items count]; i++) {
        id item = [items objectAtIndex:i];
        if ((!target || [item target] == target) && [item action] == action)
            return i;
    }
    return NSNotFound;
}
@end
@implementation NSPopUpButton (SnowSearchSemantics)
- (int)snowIndexOfItem:(id)item {
    return [[self itemArray] indexOfObjectIdenticalTo:item];
}
- (int)snowIndexOfItemWithTarget:(id)target andAction:(SEL)action {
    NSArray *items = [self itemArray];
    unsigned i;
    for (i = 0; i < [items count]; i++) {
        id item = [items objectAtIndex:i];
        if ((!target || [item target] == target) && [item action] == action)
            return i;
    }
    return NSNotFound;
}
@end
static IMP snowNativeMenuUpdate;
static void snowMenuUpdate(NSMenu *menu, SEL action) {
    id delegate = [menu delegate];
    NSMutableDictionary *thread = [[NSThread currentThread] threadDictionary];
    NSValue *key = [NSValue valueWithPointer:menu];
    NSMutableArray *updating = [thread objectForKey:@"SnowUpdatingMenus"];
    if (delegate && [delegate respondsToSelector:@selector(menuNeedsUpdate:)] &&
        ![updating containsObject:key]) {
        if (!updating) {
            updating = [NSMutableArray array];
            [thread setObject:updating forKey:@"SnowUpdatingMenus"];
        }
        [updating addObject:key];
        NS_DURING
            [delegate performSelector:@selector(menuNeedsUpdate:) withObject:menu];
        NS_HANDLER
            [updating removeObject:key];
            [localException raise];
        NS_ENDHANDLER
        [updating removeObject:key];
    }
    ((void (*)(id, SEL))snowNativeMenuUpdate)(menu, action);
}
static void snowUseSuperclassMethod(Class cls, const char *name) {
    Method method = class_getInstanceMethod(cls->super_class, sel_getUid(name));
    if (!method)
        [NSException raise:NSInternalInconsistencyException
                    format:@"Missing native method %s", name];
    SnowReplaceMethod(cls, name, method->method_imp);
}
@implementation NSTabView (SnowContainer)
- (void)removeTabViewItem:(NSTabViewItem *)item {
    if (tigerSelectedTab == item)
        [self selectTabViewItem:nil];
    [tigerTabs removeObjectIdenticalTo:item];
}
- (int)indexOfTabViewItem:(NSTabViewItem *)item {
    return [tigerTabs indexOfObjectIdenticalTo:item];
}
- (NSFont *)font {
    return [NSFont systemFontOfSize:12];
}
- (void)setFont:(NSFont *)font {
}
- (void)setControlSize:(int)size {
}
@end
static NSMutableDictionary *snowNativeTabTypes;
@implementation NSTabView (SnowVisibleTabs)
- (BOOL)snowShowsTabs {
    NSNumber *type = [snowNativeTabTypes objectForKey:[NSValue valueWithPointer:self]];
    return type && [type intValue] >= -1 && [type intValue] < 4;
}
- (NSRect)contentRect {
    NSRect rect = [self bounds];
    if ([self snowShowsTabs]) {
        NSNumber *type = [snowNativeTabTypes objectForKey:[NSValue valueWithPointer:self]];
        if ([type intValue] != -1) {
            rect.origin.x += 10;
            rect.origin.y += 10;
            rect.size.width -= 20;
            rect.size.height -= 10;
        }
        rect.size.height -= 28;
    }
    return rect;
}
- (void)setTabViewType:(int)type {
    if (!snowNativeTabTypes)
        snowNativeTabTypes = [[NSMutableDictionary alloc] init];
    [snowNativeTabTypes setObject:[NSNumber numberWithInt:type]
                           forKey:[NSValue valueWithPointer:self]];
    [[tigerSelectedTab view] setFrame:[self contentRect]];
    [self setNeedsDisplay:YES];
}
- (void)selectTabViewItem:(NSTabViewItem *)item {
    SEL will = @selector(tabView:willSelectTabViewItem:), did = @selector(tabView:
                                                              didSelectTabViewItem:);
    if (tigerSelectedTab == item)
        return;
    if ([tigerTabDelegate respondsToSelector:will])
        [tigerTabDelegate performSelector:will withObject:self withObject:item];
    [[tigerSelectedTab view] removeFromSuperview];
    tigerSelectedTab = item;
    if (item) {
        [[item view] setFrame:[self contentRect]];
        [[item view] setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [self addSubview:[item view]];
        if ([item initialFirstResponder])
            [[self window] makeFirstResponder:[item initialFirstResponder]];
    }
    [self setNeedsDisplay:YES];
    if ([tigerTabDelegate respondsToSelector:did])
        [tigerTabDelegate performSelector:did withObject:self withObject:item];
    SnowCommitBindingTarget(self, @"selectedIndex",
                            [NSNumber numberWithInt:[tigerTabs indexOfObjectIdenticalTo:item]]);
}
- (void)drawRect:(NSRect)dirty {
    unsigned i, count = [tigerTabs count];
    NSRect bounds = [self bounds];
    if (![self snowShowsTabs] || !count)
        return;
    NSDrawGrayBezel(bounds, dirty);
    for (i = 0; i < count; i++) {
        NSRect rect = NSMakeRect(bounds.origin.x + i * bounds.size.width / count,
                                 NSMaxY(bounds) - 28, bounds.size.width / count, 28);
        id item = [tigerTabs objectAtIndex:i];
        NSButtonCell *button = [[[NSButtonCell alloc] initTextCell:[item label]] autorelease];
        [button setButtonType:NSPushOnPushOffButton];
        [button setFont:[NSFont systemFontOfSize:12]];
        [button setState:item == tigerSelectedTab];
        [button drawWithFrame:rect inView:self];
    }
}
- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    NSRect bounds = [self bounds];
    if ([self snowShowsTabs] && point.y >= NSMaxY(bounds) - 28 && [tigerTabs count] &&
        bounds.size.width > 0) {
        unsigned index = (point.x - bounds.origin.x) * [tigerTabs count] / bounds.size.width;
        if (index < [tigerTabs count])
            [self selectTabViewItemAtIndex:index];
    } else
        [super mouseDown:event];
}
@end
static NSMutableDictionary *snowTabParents;
@implementation NSTabViewItem (SnowContainer)
- (id)tabView {
    return [[snowTabParents objectForKey:[NSValue valueWithPointer:self]] nonretainedObjectValue];
}
@end
static void snowContainerAdd(id object, SEL action, id item) {
    IMP native = class_getInstanceMethod([NSTabView class], @selector(addTabViewItem:))->method_imp;
    if (!snowTabParents)
        snowTabParents = [[NSMutableDictionary alloc] init];
    [snowTabParents setObject:[NSValue valueWithNonretainedObject:object]
                       forKey:[NSValue valueWithPointer:item]];
    ((void (*)(id, SEL, id))native)(object, action, item);
}
static NSSize snowContainerSize(id object, SEL action, NSSize size) {
    return size;
}
static void snowContainerFrame(NSView *view, SEL action, NSRect frame) {
    NSView *parent = [view superview];
    IMP native = class_getInstanceMethod([NSView class], @selector(setFrame:))->method_imp;
    /* Cocoa's content view starts at the window origin. OPENSTEP reserves
     * a frame border and resize bar, so use the parent's local bounds. */
    if (parent && parent == [[view window] contentView])
        frame = [parent bounds];
    ((void (*)(id, SEL, NSRect))native)(view, action, frame);
}
static IMP snowNativeViewDraw;
static IMP snowNativeCursorRects;
static unsigned snowMouseCursorOffset;
static void snowCursorRects(NSView *view, SEL action) {
    ((void (*)(id, SEL))snowNativeCursorRects)(view, action);
    if ([view isKindOfClass:NSClassFromString(@"TTView")]) {
        NSCursor *cursor = *(id *)((char *)view + snowMouseCursorOffset);
        [view addCursorRect:[view visibleRect] cursor:cursor ? cursor : [NSCursor IBeamCursor]];
    }
}

/* Tiny profile previews do not need the stock renderer's two scaled terminal
 * screens. Native bitmap fonts cannot safely follow that Quartz drawing path. */
static NSMutableDictionary *snowProfileThumbnails;
static id snowProfileThumbnail(id controller, SEL action, NSSize size, id profile) {
    NSColor *background = [profile valueForKey:@"BackgroundColor"];
    NSColor *foreground = [profile valueForKey:@"TextColor"];
    NSFont *font = [profile valueForKey:@"Font"];
    NSString *key;
    NSArray *signature;
    NSDictionary *cached;
    NSImage *image;
    float fontSize, lineHeight, y;
    unsigned i;
    NSArray *lines = [NSArray arrayWithObjects:@"Last login", @"host:~ user$ ls",
                                               @"Applications  Documents", @"host:~ user$", nil];
    if (size.width <= 0 || size.height <= 0)
        return nil;
    if (!background)
        background = [NSColor whiteColor];
    if (!foreground)
        foreground = [NSColor blackColor];
    if (!font)
        font = [NSFont userFixedPitchFontOfSize:10];
    key = [NSString stringWithFormat:@"%x:%g:%g", (unsigned)profile, size.width, size.height];
    signature = [NSArray arrayWithObjects:background, foreground, font, nil];
    if (!snowProfileThumbnails)
        snowProfileThumbnails = [[NSMutableDictionary alloc] init];
    cached = [snowProfileThumbnails objectForKey:key];
    if ([[cached objectForKey:@"signature"] isEqual:signature])
        return [cached objectForKey:@"image"];
    image = [[[NSImage alloc] initWithSize:size] autorelease];
    fontSize = size.height / 6;
    if (fontSize < 4)
        fontSize = 4;
    if (fontSize > 10)
        fontSize = 10;
    font = [NSFont fontWithName:[font fontName] size:fontSize];
    if (!font)
        font = [NSFont fontWithName:@"Courier" size:fontSize];
    lineHeight = fontSize + 1;
    y = size.height - lineHeight - 2;
    [image lockFocus];
    [[background colorWithAlphaComponent:1] set];
    NSRectFill(NSMakeRect(0, 0, size.width, size.height));
    for (i = 0; i < [lines count] && y >= 0; i++, y -= lineHeight)
        [[lines objectAtIndex:i]
               drawAtPoint:NSMakePoint(2, y)
            withAttributes:[NSDictionary
                               dictionaryWithObjectsAndKeys:font, NSFontAttributeName, foreground,
                                                            NSForegroundColorAttributeName, nil]];
    [image unlockFocus];
    /* Bound the cache when profiles are renamed or removed. */
    if ([snowProfileThumbnails count] >= 64)
        [snowProfileThumbnails removeAllObjects];
    [snowProfileThumbnails
        setObject:[NSDictionary
                      dictionaryWithObjectsAndKeys:signature, @"signature", image, @"image", nil]
           forKey:key];
    return image;
}
static IMP snowNativeSelectionDraw;
static void snowDrawSelection(id view, SEL action, id ranges, id color) {
    ((void (*)(id, SEL, id, id))snowNativeSelectionDraw)(view, action, ranges,
                                                         snowTextSelectionColor(color));
}
static unsigned snowDirtyLinesOffset;
static IMP snowNativePaneGeometry;
static unsigned snowSplitButtonOffset, snowCloseButtonOffset;
static void snowPaneGeometry(NSView *pane, SEL action) {
    NSButton *split = *(id *)((char *)pane + snowSplitButtonOffset);
    NSButton *close = *(id *)((char *)pane + snowCloseButtonOffset);
    NSScroller *scroller;
    NSRect frame;
    float width = [NSScroller scrollerWidth];
    if (split) {
        [split setImage:nil];
        [split setTitle:@"+"];
        [split setFrameSize:NSMakeSize(width, width)];
    }
    if (close) {
        [close setImage:nil];
        [close setTitle:@"-"];
        [close setFrameSize:NSMakeSize(width, width)];
    }
    ((void (*)(id, SEL))snowNativePaneGeometry)(pane, action);
    scroller = [pane performSelector:@selector(scroller)];
    frame = [scroller frame];
    frame.size.height += frame.origin.y;
    frame.origin.y = 0;
    [scroller setFrame:frame];
}
static void snowViewDraw(id view, SEL action, NSRect rect) {
    /* An ancestor can erase OPENSTEP's backing store while the stock row
     * cache is clean. Redraw all visible rows whenever AppKit asks. */
    *(BOOL *)((char *)view + snowDirtyLinesOffset) = YES;
    ((void (*)(id, SEL, NSRect))snowNativeViewDraw)(view, action, rect);
}
static NSRect snowContainerEmptyRect(id object, SEL action) {
    return NSZeroRect;
}
static void snowContainerNoAction(id object, SEL action, ...) {}
static BOOL snowContainerNo(id object, SEL action) {
    return NO;
}
static void snowSecureInputUnavailable(id object, SEL action, id sender) {
    NSRunAlertPanel(@"Secure Keyboard Entry",
                    @"OPENSTEP does not provide a secure keyboard input service.", @"OK", nil, nil);
}
static void snowClearSecureInput(id object, SEL action, ...) {
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"SecureKeyboardEntry"];
}
/* Import bundled profiles without constructing the Preferences window. */
static id snowImportDefaultProfiles(id object, SEL action, BOOL overwrite) {
    id manager = [NSClassFromString(@"TTProfileManager") sharedProfileManager];
    NSString *directory = [[NSBundle mainBundle] pathForResource:@"Initial Settings" ofType:nil];
    NSArray *files = [[NSFileManager defaultManager] directoryContentsAtPath:directory];
    unsigned i;
    NSDictionary *settings = [NSDictionary
        dictionaryWithContentsOfFile:[directory stringByAppendingPathComponent:@"settings.plist"]];
    for (i = 0; i < [files count]; i++) {
        NSString *file = [files objectAtIndex:i];
        NSDictionary *values;
        id profile;
        NSString *name;
        if (![[file pathExtension] isEqual:@"terminal"])
            continue;
        values = [NSDictionary
            dictionaryWithContentsOfFile:[directory stringByAppendingPathComponent:file]];
        name = [values objectForKey:@"name"];
        if (!values || !name)
            continue;
        if (!overwrite && [manager profileWithName:name])
            continue;
        profile = [[[NSClassFromString(@"TTProfile") alloc]
            initWithPropertyListRepresentation:values] autorelease];
        if (profile)
            [manager setProfile:profile forName:name];
    }
    return [manager profileWithName:[settings objectForKey:@"Default Settings"]];
}
static void snowNewShellWithProfile(id object, SEL action, id sender, id profile) {
    /* The original first loads Preferences merely to finish field editing.
     * Create the stock window directly when no preferences editor is open. */
    [object performSelector:@selector(newWindowControllerWithProfile:) withObject:profile];
}
static IMP snowNativeShellArgs;
static IMP snowNativeShellPath;
static unsigned snowShellArgsOffset, snowCommandAsShellOffset;
static id snowShellPath(id cls, SEL selector, NSString *path) {
    if ([path isEqual:@"/usr/bin/login"] && access("/bin/login", X_OK) == 0)
        return @"/bin/login";
    return ((id(*)(id, SEL, id))snowNativeShellPath)(cls, selector, path);
}
static id snowShellArgs(id shell, SEL selector, NSString *command) {
    NSString *program = ((id(*)(id, SEL, id))snowNativeShellArgs)(shell, selector, command);
    char **arguments = (char **)((char *)shell + snowShellArgsOffset);
    if ([command length] && [[program lastPathComponent] isEqual:@"login"] && arguments[3]) {
        unsigned i;
        /* OPENSTEP login ignores a command following the user name. The
         * desktop user is already authenticated; execute that program. */
        program = [NSString stringWithUTF8String:arguments[3]];
        for (i = 0; i < 252 && arguments[i + 3]; i++)
            arguments[i] = arguments[i + 3];
        arguments[i] = NULL;
        if (!*(BOOL *)((char *)shell + snowCommandAsShellOffset))
            arguments[0] = (char *)[[NSString stringWithFormat:@"-%@", [program lastPathComponent]]
                UTF8String];
    } else if ([[program lastPathComponent] isEqual:@"login"]) {
        struct passwd *account = getpwuid(getuid());
        const char *path =
            account && account->pw_shell && account->pw_shell[0] ? account->pw_shell : "/bin/sh";
        /* The desktop has already established the user's identity and
         * groups. Preserve those credentials and start a login shell. */
        program = [NSString stringWithUTF8String:path];
        arguments[0] =
            (char *)[[NSString stringWithFormat:@"-%@", [program lastPathComponent]] UTF8String];
        arguments[1] = NULL;
    }
    return program;
}
static int snowPTYAvailable(const char *path) {
    struct stat info;
    unsigned i;
    int available = 1;
    if (stat(path, &info) != 0)
        return 1;
    [tigerProcessLock lock];
    if (tigerRefreshProcesses() < 0)
        available = 0;
    else
        for (i = 0; i < tigerProcessCount; i++)
            if (tigerProcesses[i].tty == info.st_rdev) {
                available = 0;
                break;
            }
    [tigerProcessLock unlock];
    /* A detached GUI app can retain an old slave after its master closes.
     * OPENSTEP allows reopening that master; avoid mixing the sessions. */
    return available;
}
static void snowNewTabAsWindow(id object, SEL action, id sender) {
    [NSApp performSelector:@selector(newShell:) withObject:sender];
}
static IMP snowNativeWindowValidation;
static BOOL snowValidateWindowMenu(id controller, SEL selector, id item) {
    SEL action = [item action];
    if (action == @selector(mergeAllWindows:) || action == @selector(moveTabToNewWindow:) ||
        action == @selector(toggleTabBarShown:) || action == @selector(selectPreviousTab:) ||
        action == @selector(selectNextTab:))
        return NO;
    return ((BOOL(*)(id, SEL, id))snowNativeWindowValidation)(controller, selector, item);
}
static void SnowInitializeSingleWindow(void) {
    Class cls = NSClassFromString(@"TTTabView");
    const char *native[] = {"initWithFrame:",
                            "dealloc",
                            "setDelegate:",
                            "delegate",
                            "selectedTabViewItem",
                            "selectTabViewItem:",
                            "removeTabViewItem:",
                            "contentRect",
                            "setFrame:",
                            "drawRect:",
                            "isFlipped"};
    const char *inactive[] = {"setShowTabIfOnlyOne:",     "setTabViewOnBottom:",
                              "setOverflowTabMenuImage:", "initTabFrame",
                              "removeTabViewTooltips",    "registerForDragEvents",
                              "unregisterForDragEvents",  "viewWillMoveToWindow:",
                              "windowDidChangeKey:",      "viewDidEndLiveResize"};
    unsigned i;
    tigerPTYAvailable = snowPTYAvailable;
    snowNativeFontAction =
        class_getInstanceMethod([NSFontManager class], @selector(sendAction))->method_imp;
    SnowReplaceMethod([NSFontManager class], "sendAction", (IMP)snowFontAction);
    snowNativeFirstResponder =
        class_getInstanceMethod([NSWindow class], @selector(makeFirstResponder:))->method_imp;
    SnowReplaceMethod([NSWindow class], "makeFirstResponder:", (IMP)snowMakeFirstResponder);
    snowNativeOrderWindow =
        class_getInstanceMethod([NSWindow class], @selector(orderWindow:relativeTo:))->method_imp;
    SnowReplaceMethod([NSWindow class], "orderWindow:relativeTo:", (IMP)snowOrderWindow);
    for (i = 0; i < sizeof(native) / sizeof(*native); i++)
        snowUseSuperclassMethod(cls, native[i]);
    for (i = 0; i < sizeof(inactive) / sizeof(*inactive); i++)
        SnowReplaceMethod(cls, inactive[i], (IMP)snowContainerNoAction);
    SnowReplaceMethod(cls, "addTabViewItem:", (IMP)snowContainerAdd);
    SnowReplaceMethod(cls, "setFrame:", (IMP)snowContainerFrame);
    SnowReplaceMethod(cls, "contentSizeForFrameSize:", (IMP)snowContainerSize);
    SnowReplaceMethod(cls, "frameSizeForContentSize:", (IMP)snowContainerSize);
    SnowReplaceMethod(cls, "tabFrame", (IMP)snowContainerEmptyRect);
    SnowReplaceMethod(cls, "showTabIfOnlyOne", (IMP)snowContainerNo);
    SnowReplaceMethod(cls, "tabViewOnBottom", (IMP)snowContainerNo);
    cls = NSClassFromString(@"TTPane");
    snowSplitButtonOffset = class_getInstanceVariable(cls, "_splitButton")->ivar_offset;
    snowCloseButtonOffset = class_getInstanceVariable(cls, "_closeButton")->ivar_offset;
    snowNativePaneGeometry = class_getInstanceMethod(cls, sel_getUid("updateGeometry"))->method_imp;
    SnowReplaceMethod(cls, "updateGeometry", (IMP)snowPaneGeometry);
    cls = NSClassFromString(@"TTApplication");
    SnowReplaceMethod(cls, "setSecureKeyboardEntry:", (IMP)snowClearSecureInput);
    SnowReplaceMethod(cls, "setSecureKeyboardEntryFromDefaults", (IMP)snowClearSecureInput);
    SnowReplaceMethod(cls, "toggleSecureKeyboardEntry:", (IMP)snowSecureInputUnavailable);
    /* The stock resign handler only disables WindowServer secure input. */
    SnowReplaceMethod(cls, "applicationDidResignActive:", (IMP)snowClearSecureInput);
    SnowReplaceMethod(cls,
                      "importDefaultSettingsOverwritingExisting:", (IMP)snowImportDefaultProfiles);
    SnowReplaceMethod(cls, "newShell:withProfile:", (IMP)snowNewShellWithProfile);
    SnowReplaceMethod(cls, "newTab:", (IMP)snowNewTabAsWindow);
    cls = NSClassFromString(@"TTShell");
    snowShellArgsOffset = class_getInstanceVariable(cls, "_shellArgs")->ivar_offset;
    snowCommandAsShellOffset = class_getInstanceVariable(cls, "_commandAsShell")->ivar_offset;
    snowNativeShellArgs = class_getInstanceMethod(cls, sel_getUid("initShellArgs:"))->method_imp;
    SnowReplaceMethod(cls, "initShellArgs:", (IMP)snowShellArgs);
    snowNativeShellPath = class_getClassMethod(cls, sel_getUid("pathForExecutable:"))->method_imp;
    SnowReplaceMethod(*(Class *)cls, "pathForExecutable:", (IMP)snowShellPath);
    SnowReplaceMethod(NSClassFromString(@"TTWindowController"), "newTab:", (IMP)snowNewTabAsWindow);
    {
        Class controller = NSClassFromString(@"TTWindowController");
        Method validation = class_getInstanceMethod(controller, @selector(validateMenuItem:));
        snowNativeWindowValidation = validation->method_imp;
        validation->method_imp = (IMP)snowValidateWindowMenu;
    }
}
@interface NSNib : NSObject {
    NSString *snowNibName;
}
- initWithNibNamed:(NSString *)name bundle:(NSBundle *)bundle;
- (BOOL)instantiateNibWithOwner:(id)owner topLevelObjects:(NSArray **)objects;
@end
@implementation NSNib
- initWithNibNamed:(NSString *)name bundle:(NSBundle *)bundle {
    self = [super init];
    snowNibName = [name snowCopy];
    return self;
}
- (BOOL)instantiateNibWithOwner:(id)owner topLevelObjects:(NSArray **)objects {
    if (objects)
        *objects = [NSArray array];
    return TigerLoadNib(snowNibName, owner);
}
- (void)dealloc {
    [snowNibName release];
    [super dealloc];
}
@end

static NSWindow *snowControllerWindow(id controller, SEL selector) {
    NSWindowController *native = (NSWindowController *)controller;
    Ivar ivar = class_getInstanceVariable([NSWindowController class], "tigerWindow");
    NSWindow *window = *(id *)((char *)native + ivar->ivar_offset);
    if (!window) {
        [controller windowWillLoad];
        if (!TigerLoadNib([controller windowNibName], controller))
            [NSException raise:NSInvalidArgumentException
                        format:@"Unsupported window nib %@", [controller windowNibName]];
        [controller windowDidLoad];
        window = *(id *)((char *)native + ivar->ivar_offset);
    }
    return window;
}
static void snowInitializeGraphics(void) {
    Method method = class_getInstanceMethod([NSFont class], @selector(set));
    tigerNativeFontSet = method->method_imp;
    method->method_imp = (IMP)tigerFontSet;
    snowMouseCursorOffset =
        class_getInstanceVariable(NSClassFromString(@"TTView"), "_mouseCursor")->ivar_offset;
    method = class_getInstanceMethod([NSView class], @selector(resetCursorRects));
    snowNativeCursorRects = method->method_imp;
    method->method_imp = (IMP)snowCursorRects;
    SnowReplaceMethod(NSClassFromString(@"TTAppPrefsController"),
                      "thumbnailOfSize:forProfile:", (IMP)snowProfileThumbnail);
    snowDirtyLinesOffset =
        class_getInstanceVariable(NSClassFromString(@"TTView"), "_shouldDirtyAllLines")
            ->ivar_offset;
    method = class_getInstanceMethod(NSClassFromString(@"TTView"), @selector(drawRect:));
    snowNativeViewDraw = method->method_imp;
    method->method_imp = (IMP)snowViewDraw;
    method = class_getInstanceMethod(NSClassFromString(@"TTView"),
                                     @selector(drawSelectedTextRanges:withColor:));
    snowNativeSelectionDraw = method->method_imp;
    method->method_imp = (IMP)snowDrawSelection;
    method = class_getInstanceMethod([NSWindow class], @selector(dealloc));
    snowNativeWindowDealloc = method->method_imp;
    method->method_imp = (IMP)snowWindowDealloc;
    method = class_getInstanceMethod([NSWindow class], sel_getUid("_setFrameFromString:"));
    snowNativeFrameString = method->method_imp;
    method->method_imp = (IMP)snowFrameString;
    method = class_getInstanceMethod([NSOpenPanel class], @selector(runModalForDirectory:
                                                                                    file:types:));
    snowNativeOpenPanelModal = method->method_imp;
    method->method_imp = (IMP)snowOpenPanelModal;
}
extern void SnowInitializeStructReturns(void);
#ifdef SNOW_TESTING
static IMP snowUnknownSelector;
static IMP snowNativeRaise;
static void snowTraceRaise(id object, SEL action) {
    if ([[object reason] rangeOfString:@"beyond bounds"].location != NSNotFound ||
        [[object name] isEqual:@"DPSPostscriptErrorException"]) {
        void **frame = __builtin_frame_address(0);
        unsigned i;
        fprintf(stderr, "SNOW bounds exception: %s\n", [[object reason] cString]);
        for (i = 0; i < 24 && frame; i++) {
            void **next = frame[0];
            fprintf(stderr, "  return %p\n", frame[1]);
            if (next <= frame || (char *)next - (char *)frame > 1048576)
                break;
            frame = next;
        }
    }
    ((void (*)(id, SEL))snowNativeRaise)(object, action);
}
#endif
static void volatile snowException(NSException *exception) {
    void *frames[24];
    int count, i;
    fprintf(stderr, "Terminal: %s: %s\n", [[exception name] cString], [[exception reason] cString]);
    count = backtrace(frames, 24);
    for (i = 0; i < count; i++)
        fprintf(stderr, "  0x%08x\n", (unsigned)frames[i]);
    exit(1);
}
#ifdef SNOW_TESTING
static void snowLogUnknownSelector(id object, SEL action, SEL unknown) {
    void **frame = __builtin_frame_address(0);
    unsigned i;
    fprintf(stderr, "SNOW unknown %s on %s\n", sel_getName(unknown), object_getClassName(object));
    for (i = 0; i < 16 && frame; i++) {
        void **next = frame[0];
        fprintf(stderr, "  return %p\n", frame[1]);
        if (next <= frame || (char *)next - (char *)frame > 1048576)
            break;
        frame = next;
    }
    NSSetUncaughtExceptionHandler(snowException);
    ((void (*)(id, SEL, SEL))snowUnknownSelector)(object, action, unknown);
}
#endif
int SnowApplicationMain(int argc, char **argv, char **envp) {
    NSAutoreleasePool *pool;
    extern void _objcInit(void);
    _NXArgc = argc;
    _NXArgv = argv;
    _environ = envp;
    mach_init();
    cthread_init();
    _objcInit();
    pool = [[NSAutoreleasePool alloc] init];
    NSSetUncaughtExceptionHandler(snowException);
    TigerInitializeCABI();
    SnowInitializeRuntime();
    SnowInitializeFoundation();
    SnowInitializeFormatting();
    SnowInitializeStructReturns();
    SnowInitializeSingleWindow();
    snowInitializeMenuCells();
    SnowReplaceMethod([NSWindowController class], "window", (IMP)snowControllerWindow);
    tigerInitializeNibLoading();
    snowInitializeGraphics();
    TigerInitializeRunLoop();
    SnowInitializeMainThreadDispatch();
    SnowInitializeBindings();
#ifdef SNOW_TESTING
    {
        Method method =
            class_getInstanceMethod([NSObject class], @selector(doesNotRecognizeSelector:));
        snowUnknownSelector = method->method_imp;
        method->method_imp = (IMP)snowLogUnknownSelector;
        method = class_getInstanceMethod([NSException class], @selector(raise));
        snowNativeRaise = method->method_imp;
        method->method_imp = (IMP)snowTraceRaise;
    }
    fprintf(stderr, "SNOW creating application\n");
#endif
    [NSClassFromString(@"TTApplication") sharedApplication];
    /* Early compatibility setup can load fonts before NSApplication registers
     * OPENSTEP's system defaults. Restore the native font roles before menus
     * and window frames are built, including the bold title-bar font. */
    [NSFont initializeUserAndSystemFonts];
    NSSetUncaughtExceptionHandler(snowException);
    tigerInitializeMenuOwnership();
    {
        Method update = class_getInstanceMethod([NSMenu class], @selector(update));
        snowNativeMenuUpdate = update->method_imp;
        update->method_imp = (IMP)snowMenuUpdate;
    }

    TigerLoadNib(@"MainMenu", NSApp);
    [[NSApp mainMenu] setTitle:@"Terminal"];
    if ([[NSApp mainMenu] numberOfItems])
        [[[NSApp mainMenu] itemAtIndex:0] setTitle:@"Terminal"];
    [NSApp setDelegate:NSApp];

#ifdef SNOW_TESTING
    {
        extern void SnowStartTestControl(void);
        SnowStartTestControl();
    }
#endif
    [NSApp run];
    [pool release];
    return 0;
}
