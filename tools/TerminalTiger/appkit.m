/* Tiger object services implemented with OPENSTEP AppKit. */
#import <AppKit/AppKit.h>
#import <objc/objc-class.h>
#include <stdio.h>
#include <string.h>
#include <ctype.h>

@interface NSString (TigerEncoding)
- (const char *)cStringUsingEncoding:(unsigned)encoding;
@end
@implementation NSString (TigerEncoding)
- initWithCString:(const char *)bytes encoding:(unsigned)encoding {
    return [self initWithData:[NSData dataWithBytes:bytes length:strlen(bytes)] encoding:encoding];
}
+ stringWithUTF8String:(const char *)bytes {
    return [[[self alloc] initWithCString:bytes encoding:NSUTF8StringEncoding] autorelease];
}
- initWithUTF8String:(const char *)bytes {
    return [self initWithCString:bytes encoding:NSUTF8StringEncoding];
}
- (const char *)UTF8String {
    return [self cStringUsingEncoding:NSUTF8StringEncoding];
}
- (const char *)cStringUsingEncoding:(unsigned)encoding {
    NSMutableData *bytes = [[self dataUsingEncoding:encoding] mutableCopy];
    unsigned char zero = 0;
    if (!bytes)
        return NULL;
    [bytes appendBytes:&zero length:1];
    [bytes autorelease];
    return [bytes bytes];
}
@end

@implementation NSMutableString (TigerReplacement)
- (unsigned)replaceOccurrencesOfString:(NSString *)old
                            withString:(NSString *)value
                               options:(unsigned)options
                                 range:(NSRange)range {
    unsigned count = 0, end = NSMaxRange(range);
    if (![old length])
        return 0;
    while (range.location < end) {
        NSRange found = [self rangeOfString:old options:options range:range];
        if (found.location == NSNotFound)
            break;
        [self replaceCharactersInRange:found withString:value];
        count++;
        end = end - found.length + [value length];
        if (options & NSBackwardsSearch)
            end = found.location;
        else
            range.location = found.location + [value length];
        range.length = end - range.location;
    }
    return count;
}
@end

extern BOOL TigerLoadNib(NSString *name, id owner);

/* Tiger's Inspector uses a borderless tab container, driven by its pop-up.
 * OPENSTEP predates NSTabView; implement that container with native views. */
@interface NSTabViewItem : NSObject {
    id tigerIdentifier;
    NSString *tigerLabel;
    NSView *tigerView;
    id tigerInitialResponder;
}
- initWithIdentifier:(id)identifier;
- (id)identifier;
- (void)setView:(NSView *)view;
- (NSView *)view;
- (void)setLabel:(NSString *)label;
- (NSString *)label;
- (id)initialFirstResponder;
- (void)setInitialFirstResponder:(id)responder;
@end
@implementation NSTabViewItem
- initWithIdentifier:(id)identifier {
    self = [super init];
    tigerIdentifier = [identifier retain];
    return self;
}
- (id)identifier {
    return tigerIdentifier;
}
- (void)setIdentifier:(id)identifier {
    [identifier retain];
    [tigerIdentifier release];
    tigerIdentifier = identifier;
}
- (void)setView:(NSView *)view {
    [view retain];
    [tigerView release];
    tigerView = view;
}
- (NSView *)view {
    return tigerView;
}
- (void)setLabel:(NSString *)label {
    [label retain];
    [tigerLabel release];
    tigerLabel = label;
}
- (NSString *)label {
    return tigerLabel;
}
- (id)initialFirstResponder {
    return tigerInitialResponder;
}
- (void)setInitialFirstResponder:(id)responder {
    tigerInitialResponder = responder;
}
- (void)dealloc {
    [tigerIdentifier release];
    [tigerLabel release];
    [tigerView release];
    [super dealloc];
}
@end
@interface NSTabView : NSView {
    NSMutableArray *tigerTabs;
    NSTabViewItem *tigerSelectedTab;
    id tigerTabDelegate;
}
- (void)addTabViewItem:(NSTabViewItem *)item;
- (void)selectTabViewItem:(NSTabViewItem *)item;
- (void)selectTabViewItemAtIndex:(int)index;
- (void)setTabViewType:(int)type;
@end
@implementation NSTabView
- initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    tigerTabs = [[NSMutableArray alloc] init];
    return self;
}
- (void)addTabViewItem:(NSTabViewItem *)item {
    [tigerTabs addObject:item];
}
- (NSArray *)tabViewItems {
    return tigerTabs;
}
- (int)numberOfTabViewItems {
    return [tigerTabs count];
}
- (id)tabViewItemAtIndex:(int)index {
    return [tigerTabs objectAtIndex:index];
}
- (id)selectedTabViewItem {
    return tigerSelectedTab;
}
- (int)indexOfTabViewItemWithIdentifier:(id)identifier {
    unsigned i;
    for (i = 0; i < [tigerTabs count]; i++)
        if ([[[tigerTabs objectAtIndex:i] identifier] isEqual:identifier])
            return i;
    return NSNotFound;
}
- (void)selectTabViewItemWithIdentifier:(id)identifier {
    int index = [self indexOfTabViewItemWithIdentifier:identifier];
    if (index != NSNotFound)
        [self selectTabViewItemAtIndex:index];
}
- (void)selectTabViewItemAtIndex:(int)index {
    [self selectTabViewItem:[tigerTabs objectAtIndex:index]];
}
- (void)selectTabViewItem:(NSTabViewItem *)item {
    SEL selector = sel_getUid("tabView:didSelectTabViewItem:");
    if (tigerSelectedTab == item)
        return;
    [[tigerSelectedTab view] removeFromSuperview];
    tigerSelectedTab = item;
    if (item) {
        [[item view] setFrame:[self bounds]];
        [[item view] setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [self addSubview:[item view]];
        if ([item initialFirstResponder])
            [[self window] makeFirstResponder:[item initialFirstResponder]];
    }
    [self setNeedsDisplay:YES];
    if ([tigerTabDelegate respondsToSelector:selector])
        [tigerTabDelegate performSelector:selector withObject:self withObject:item];
}
- (void)setTabViewType:
    (int)type { /* The supplied Inspector archive uses no visible tabs or border. */
}
- (NSRect)contentRect {
    return [self bounds];
}
- (void)setDelegate:(id)delegate {
    tigerTabDelegate = delegate;
}
- (id)delegate {
    return tigerTabDelegate;
}
- (void)dealloc {
    [tigerTabs release];
    [super dealloc];
}
@end

static IMP tigerNativeLoadNib;
static BOOL tigerBundleLoadNib(id bundle, SEL selector, NSString *name, id owner) {
    if (TigerLoadNib(name, owner))
        return YES;
    return ((BOOL(*)(id, SEL, id, id))tigerNativeLoadNib)(bundle, selector, name, owner);
}
static void tigerInitializeNibLoading(void) {
    Method method = class_getClassMethod([NSBundle class], @selector(loadNibNamed:owner:));
    tigerNativeLoadNib = method->method_imp;
    method->method_imp = (IMP)tigerBundleLoadNib;
}

/* Cocoa owns attached submenus; OPENSTEP stores them as cell targets without
 * retaining them. Tiger's dynamically created Library menu is autoreleased. */
static NSMutableDictionary *tigerMenuChildren;
static IMP tigerNativeSetSubmenu, tigerNativeRemoveMenuItem, tigerNativeMenuDealloc;
static void tigerSetSubmenu(id menu, SEL selector, id submenu, id item) {
    NSValue *key = [NSValue valueWithPointer:menu], *itemKey = [NSValue valueWithPointer:item];
    NSMutableDictionary *children = [tigerMenuChildren objectForKey:key];
    id previous = [[children objectForKey:itemKey] retain];
    if (submenu && !children) {
        children = [NSMutableDictionary dictionary];
        [tigerMenuChildren setObject:children forKey:key];
    }
    if (submenu) {
        [children setObject:submenu forKey:itemKey];
        ((void (*)(id, SEL, id, id))tigerNativeSetSubmenu)(menu, selector, submenu, item);
    } else {
        /* The native implementation dereferences a nil submenu. */
        [item setTarget:nil];
        [item setAction:NULL];
        [children removeObjectForKey:itemKey];
    }
    [previous release];
}
static void tigerRemoveMenuItem(id menu, SEL selector, id item) {
    NSValue *key = [NSValue valueWithPointer:item];
    NSMutableDictionary *children =
        [tigerMenuChildren objectForKey:[NSValue valueWithPointer:menu]];
    ((void (*)(id, SEL, id))tigerNativeRemoveMenuItem)(menu, selector, item);
    [children removeObjectForKey:key];
}
static void tigerMenuDealloc(id menu, SEL selector) {
    NSValue *key = [[NSValue valueWithPointer:menu] retain];
    ((void (*)(id, SEL))tigerNativeMenuDealloc)(menu, selector);
    [tigerMenuChildren removeObjectForKey:key];
    [key release];
}
static void tigerInitializeMenuOwnership(void) {
    Method method;
    tigerMenuChildren = [[NSMutableDictionary alloc] init];
    method = class_getInstanceMethod([NSMenu class], @selector(setSubmenu:forItem:));
    tigerNativeSetSubmenu = method->method_imp;
    method->method_imp = (IMP)tigerSetSubmenu;
    method = class_getInstanceMethod([NSMenu class], @selector(removeItem:));
    tigerNativeRemoveMenuItem = method->method_imp;
    method->method_imp = (IMP)tigerRemoveMenuItem;
    method = class_getInstanceMethod([NSMenu class], @selector(dealloc));
    tigerNativeMenuDealloc = method->method_imp;
    method->method_imp = (IMP)tigerMenuDealloc;
}

@implementation NSMenu (TigerItems)
- (int)numberOfItems {
    return [[self itemArray] count];
}
- (id)itemAtIndex:(int)index {
    return [[self itemArray] objectAtIndex:index];
}
- (int)indexOfItem:(id)item {
    unsigned index = [[self itemArray] indexOfObjectIdenticalTo:item];
    return index == NSNotFound ? -1 : (int)index;
}
- (int)indexOfItemWithTarget:(id)target andAction:(SEL)action {
    NSArray *items = [self itemArray];
    unsigned i;
    for (i = 0; i < [items count]; i++) {
        id item = [items objectAtIndex:i];
        if ((!target || [item target] == target) && [item action] == action)
            return i;
    }
    return -1;
}
- (int)indexOfItemWithTag:(int)tag {
    return [self indexOfItem:[self itemWithTag:tag]];
}
- (int)indexOfItemWithTitle:(NSString *)title {
    return [self indexOfItem:[self itemWithTitle:title]];
}
- (void)removeItemAtIndex:(int)index {
    [self removeItem:[self itemAtIndex:index]];
}
@end

@implementation NSPopUpButton (TigerSelection)
- (int)indexOfItemWithTag:(int)tag {
    unsigned i;
    NSArray *items = [self itemArray];
    for (i = 0; i < [items count]; i++)
        if ([[items objectAtIndex:i] tag] == tag)
            return i;
    return -1;
}
- (BOOL)selectItemWithTag:(int)tag {
    int index = [self indexOfItemWithTag:tag];
    if (index < 0)
        return NO;
    [self selectItemAtIndex:index];
    return YES;
}
@end

/* OPENSTEP's combo box predates automatic prefix completion. */
@interface TigerCompletingComboBox : NSComboBox {
    BOOL tigerCompletes;
    unsigned tigerPreviousLength;
}
- (void)setCompletes:(BOOL)flag;
@end
@implementation TigerCompletingComboBox
- (void)setCompletes:(BOOL)flag {
    tigerCompletes = flag;
    tigerPreviousLength = 0;
}
- (BOOL)completes {
    return tigerCompletes;
}
- (void)textDidChange:(NSNotification *)notification {
    NSText *editor = [self currentEditor];
    NSString *prefix = [editor string];
    unsigned length = [prefix length], i;
    NSRange selection = [editor selectedRange];
    if (tigerCompletes && length > tigerPreviousLength && selection.location == length &&
        !selection.length && ![self usesDataSource]) {
        for (i = 0; i < [self numberOfItems]; i++) {
            NSString *candidate = [[self itemObjectValueAtIndex:i] description];
            if ([candidate hasPrefix:prefix] && [candidate length] > length) {
                [editor setString:candidate];
                [editor setSelectedRange:NSMakeRange(length, [candidate length] - length)];
                break;
            }
        }
    }
    tigerPreviousLength = length;
    [super textDidChange:notification];
}
@end

/* Present Tiger sheets as OPENSTEP modal windows, preserving completion
 * callbacks and return codes. Native AppKit continues servicing modal timers. */
static void tigerPanelFinished(id delegate, SEL selector, id panel, int result, void *info) {
    if (selector && [delegate respondsToSelector:selector])
        ((void (*)(id, SEL, id, int, void *))[delegate methodForSelector:selector])(
            delegate, selector, panel, result, info);
}
@implementation NSApplication (TigerSheets)
- (void)beginSheet:(NSWindow *)sheet
    modalForWindow:(NSWindow *)parent
     modalDelegate:(id)delegate
    didEndSelector:(SEL)selector
       contextInfo:(void *)info {
    int result;
    [sheet center];
    result = [self runModalForWindow:sheet];
    [sheet orderOut:nil];
    tigerPanelFinished(delegate, selector, sheet, result, info);
}
- (void)endSheet:(NSWindow *)sheet returnCode:(int)code {
    [self stopModalWithCode:code];
}
- (void)endSheet:(NSWindow *)sheet {
    [self stopModalWithCode:NSOKButton];
}
@end
@implementation NSSavePanel (TigerSheets)
/* OPENSTEP always displays filename extensions. */
- (void)setCanSelectHiddenExtension:(BOOL)flag {
}
- (void)setExtensionHidden:(BOOL)flag {
}
- (BOOL)isExtensionHidden {
    return NO;
}
- (void)beginSheetForDirectory:(NSString *)path
                          file:(NSString *)name
                modalForWindow:(NSWindow *)parent
                 modalDelegate:(id)delegate
                didEndSelector:(SEL)selector
                   contextInfo:(void *)info {
    int result = [self runModalForDirectory:path file:name];
    tigerPanelFinished(delegate, selector, self, result, info);
}
@end
@implementation NSPrintPanel (TigerSheets)
- (void)beginSheetWithPrintInfo:(NSPrintInfo *)printInfo
                 modalForWindow:(NSWindow *)parent
                       delegate:(id)delegate
                 didEndSelector:(SEL)selector
                    contextInfo:(void *)info {
    int result = [self runModal];
    tigerPanelFinished(delegate, selector, self, result, info);
}
@end

/* Keep Tiger's 40-byte NSWindowController base layout. */
@interface NSWindowController : NSObject {
    NSWindow *tigerWindow;
    NSString *tigerNibName;
    id tigerOwner;
    char tigerReserved[24];
}
- initWithWindowNibName:(NSString *)name;
- initWithWindowNibName:(NSString *)name owner:(id)owner;
- initWithWindow:(NSWindow *)window;
- (NSWindow *)window;
- (void)setWindow:(NSWindow *)window;
- (void)windowDidLoad;
- (void)windowWillLoad;
- (void)loadWindow;
- (void)showWindow:(id)sender;
@end
@implementation NSWindowController
- initWithWindowNibName:(NSString *)name {
    return [self initWithWindowNibName:name owner:self];
}
- initWithWindowNibName:(NSString *)name owner:(id)owner {
    self = [super init];
    tigerNibName = [name copy];
    tigerOwner = owner;
    return self;
}
- initWithWindow:(NSWindow *)window {
    self = [super init];
    [self setWindow:window];
    return self;
}
- (NSWindow *)window {
    if (!tigerWindow && tigerNibName) {
        [self windowWillLoad];
        [self loadWindow];
        [self windowDidLoad];
    }
    return tigerWindow;
}
- (void)setWindow:(NSWindow *)window {
    [window retain];
    [tigerWindow release];
    tigerWindow = window;
}
- (void)windowDidLoad {
}
- (void)windowWillLoad {
}
- (void)loadWindow {
    if (!TigerLoadNib(tigerNibName, tigerOwner))
        [NSException raise:NSInvalidArgumentException
                    format:@"Unsupported Tiger nib: %@", tigerNibName];
}
- (BOOL)isWindowLoaded {
    return tigerWindow != nil;
}
- (NSString *)windowNibName {
    return tigerNibName;
}
- (void)showWindow:(id)sender {
    [[self window] makeKeyAndOrderFront:sender];
}
- (void)close {
    [tigerWindow close];
}
- (void)setShouldCascadeWindows:(BOOL)flag {
}
- (void)setDocumentEdited:(BOOL)flag {
    [[self window] setDocumentEdited:flag];
}
- (void)setWindowFrameAutosaveName:(NSString *)name {
    [[self window] setFrameAutosaveName:name];
}
- (void)dealloc {
    [tigerWindow release];
    [tigerNibName release];
    [super dealloc];
}
@end

/* Tiger archives reserve 15 pixels for a scroller and its corner resize grip.
 * OPENSTEP scrollers are wider and the window has a separate bottom resize
 * border. Adapt the initial frames; the nib's autoresizing masks keep them
 * aligned when the terminal window or its split panes change size. */
static void TigerLayoutTerminalPane(NSView *text, NSScroller *scroller, NSButton *splitButton,
                                    BOOL fillBottom) {
    NSRect bounds = [[scroller superview] bounds], frame = [scroller frame];
    NSRect textFrame = [text frame];
    float top = NSMaxY(frame);
    frame.size.width = [NSScroller scrollerWidth];
    frame.origin.x = NSMaxX(bounds) - frame.size.width;
    if (splitButton) {
        NSRect buttonFrame = [splitButton frame];
        buttonFrame.origin.x = NSMaxX(bounds) - buttonFrame.size.width;
        buttonFrame.origin.y = NSMaxY(bounds) - buttonFrame.size.height;
        [splitButton setFrame:buttonFrame];
        top = buttonFrame.origin.y;
    }
    if (fillBottom)
        frame.origin.y = NSMinY(bounds);
    frame.size.height = top - frame.origin.y;
    [scroller setFrame:frame];
    textFrame.size.width = frame.origin.x - textFrame.origin.x;
    [text setFrame:textFrame];
}

/* Prefer public setters; IB also connects private object instance variables. */
static void TigerOutlet(id object, const char *name, id value) {
    char setter[256];
    SEL selector;
    Ivar ivar;
    if (!object)
        return;
    sprintf(setter, "set%c%s:", toupper(name[0]), name + 1);
    selector = sel_getUid(setter);
    if ([object respondsToSelector:selector]) {
        [object performSelector:selector withObject:value];
        return;
    }
    ivar = class_getInstanceVariable([object class], name);
    if (!ivar)
        [NSException raise:NSInvalidArgumentException
                    format:@"Missing Tiger outlet %s on %@", name, [object class]];
    *(id *)((char *)object + ivar->ivar_offset) = value;
}

static void volatile tigerException(NSException *exception) {
    fprintf(stderr, "TIGER EXCEPTION %s: %s\n", [[exception name] cString],
            [[exception reason] cString]);
    exit(1);
}

int TigerApplicationMain(int argc, char **argv) {
    NSAutoreleasePool *pool;
    extern void _objcInit(void);
    _objcInit();
    TigerInitializeCABI();
    pool = [[NSAutoreleasePool alloc] init];
    tigerInitializeNibLoading();
    NSSetUncaughtExceptionHandler(tigerException);
    [NSApplication class];
    [NSClassFromString(@"TerminalApp") sharedApplication];
    NSSetUncaughtExceptionHandler(tigerException);
    tigerInitializeMenuOwnership();
    TigerLoadNib(@"Terminal", NSApp);
    TigerInitializeGraphics();
    TigerInitializeStructReturns();
    TigerInitializeRunLoop();
    TigerInitializeServices();
    [NSApp setDelegate:NSApp];
    [NSApp run];
    [pool release];
    return 0;
}
