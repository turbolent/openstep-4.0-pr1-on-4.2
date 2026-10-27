/* Decode DR2 nibs and adapt their controls to OPENSTEP 4.2 AppKit. */
#import <AppKit/AppKit.h>
#include <limits.h>
#import <objc/objc-class.h>
#include <stdarg.h>
#include <string.h>

@interface DR2AppKitRuntime : NSObject
@end

enum {
    ButtonImageSourceVersion = 3,
    LastLegacyPopupVersion = 24,
    MenuObjectVersion = 204,
    MenuItemCellObjectVersion = 207,
    LastLegacyScrollVersion = 225,
    SeparateMenuItemSubmenuVersion = 321,
    PopupPullsDownMask = 0x80000000U
};

@interface NSButtonImageSource : NSObject
- initWithCoder:(NSCoder *)coder;
@end
@implementation NSButtonImageSource
- initWithCoder:(NSCoder *)coder {
    id name = [coder decodeObject];
    NSButtonCell *cell;
    NSImage *image;
    if ([coder versionForClassName:@"NSButtonImageSource"] != ButtonImageSourceVersion ||
        (![name isEqual:@"NSSwitch"] && ![name isEqual:@"NSRadioButton"]))
        [NSException raise:NSInvalidArgumentException
                    format:@"Unsupported DR2 button image: %@", name];
    cell = [[NSButtonCell alloc] initTextCell:@""];
    [cell setButtonType:[name isEqual:@"NSSwitch"] ? NSSwitchButton : NSRadioButton];
    image = [[cell alternateImage] retain];
    [cell release];
    [self release];
    return image;
}
@end

/* DR2 moved popup menus from the control into two new cell subclasses. */
@interface NSMenuItemCell : NSButtonCell
@end
@implementation NSMenuItemCell
- initWithCoder:(NSCoder *)coder {
    id menuItem, menuView;
    self = [super initWithCoder:coder];
    if ([coder versionForClassName:@"NSMenuItemCell"] >= MenuItemCellObjectVersion)
        [coder decodeValuesOfObjCTypes:"@@", &menuItem, &menuView];
    return self;
}
@end

@interface NSPopUpButtonCell : NSMenuItemCell {
    NSMenu *archivedMenu;
    int archivedSelection;
    unsigned archivedFlags;
}
- (NSMenu *)archivedMenu;
- (int)archivedSelection;
- (BOOL)pullsDown;
@end
@implementation NSPopUpButtonCell
- initWithCoder:(NSCoder *)coder {
    int flags;
    NSMenu *menu;
    self = [super initWithCoder:coder];
    [coder decodeValuesOfObjCTypes:"i@i", &flags, &menu, &archivedSelection];
    archivedFlags = flags;
    archivedMenu = [menu retain];
    return self;
}
- (NSMenu *)archivedMenu { return archivedMenu; }
- (int)archivedSelection { return archivedSelection; }
- (BOOL)pullsDown { return (archivedFlags & PopupPullsDownMask) != 0; }
- (void)dealloc {
    [archivedMenu release];
    [super dealloc];
}
@end

@interface NSPopUpButton (DR2PopupDecoding)
- _initWithFrame:(NSRect)frame popUpList:(id)menu
      protoButton:(NSButton *)button pullsDown:(BOOL)flag;
@end
static IMP originalPopupDecode;
static id decodePopup(id receiver, SEL selector, NSCoder *coder) {
    int version = [coder versionForClassName:@"NSPopUpButton"];
    Method decodeButton;
    NSPopUpButtonCell *cell;
    NSArray *items;
    unsigned i;
    if (version <= LastLegacyPopupVersion || version == INT_MAX)
        return ((id (*)(id, SEL, id))originalPopupDecode)(receiver, selector, coder);

    decodeButton = class_getInstanceMethod([NSButton class], selector);
    receiver = ((id (*)(id, SEL, id))decodeButton->method_imp)(receiver, selector, coder);
    cell = [receiver cell];
    items = [[cell archivedMenu] itemArray];
    /* Preserve the decoded view and cell while installing native popup tracking. */
    [receiver _initWithFrame:[receiver frame] popUpList:nil
                 protoButton:receiver pullsDown:[cell pullsDown]];
    [receiver setFont:[cell font]];
    for (i = 0; i < [items count]; i++) {
        id source = [items objectAtIndex:i];
        id item;
        [receiver addItemWithTitle:[source title]];
        item = [receiver lastItem];
        [item setTag:[source tag]];
        [item setRepresentedObject:[source representedObject]];
        [item setEnabled:[source isEnabled]];
        [item setImage:[source image]];
        [item setKeyEquivalent:[source keyEquivalent]];
    }
    if ([cell archivedSelection] >= 0 && [cell archivedSelection] < [items count])
        [receiver selectItemAtIndex:[cell archivedSelection]];
    return receiver;
}

static IMP originalMenuDecode, originalMenuCellDecode;
/* Native menu cells do not retain their submenu targets. Keep the decoded
 * menus alive, then reconnect their cyclic references after nib loading. */
static NSMutableArray *decodedMenus;
void DR2FixSubmenus(void) {
    unsigned i, j;
    for (i = 0; i < [decodedMenus count]; i++) {
        NSMenu *menu = [decodedMenus objectAtIndex:i];
        NSArray *items = [menu itemArray];
        for (j = 0; j < [items count]; j++) {
            id item = [items objectAtIndex:j];
            id target = [item target];
            if ([target respondsToSelector:@selector(itemMatrix)]) {
                [menu setSubmenu:target forItem:item];
            }
        }
    }
}
static IMP originalScrollDecode, originalDecodeValues;
static unsigned decodingScroll;
static id decodeScroll(id receiver, SEL selector, NSCoder *coder) {
    id result;
    decodingScroll++;
    NS_DURING
    result = ((id(*)(id, SEL, id))originalScrollDecode)(receiver, selector, coder);
    NS_HANDLER
    decodingScroll--;
    [localException raise];
    NS_ENDHANDLER
    decodingScroll--;
    return result;
}
static void decodeValues(id receiver, SEL selector, const char *types, ...) {
    enum { MaximumValues = 32 };
    void *values[MaximumValues];
    const char *type = types;
    unsigned count = 0, size, align;
    va_list args;
    memset(values, 0, sizeof(values));
    va_start(args, types);
    while (*type && count < MaximumValues) {
        values[count++] = va_arg(args, void *);
        type = NSGetSizeAndAlignment(type, &size, &align);
    }
    va_end(args);
    if (*type)
        [NSException
             raise:NSInvalidArgumentException
            format:@"Archive has too many fields: %s (remaining %s)", types, type];
    if (decodingScroll && !strcmp(types, "ffi") &&
        [receiver versionForClassName:@"NSScrollView"] > LastLegacyScrollVersion) {
        float horizontalLine, horizontalPage;
        ((void (*)(id, SEL, const char *, ...))originalDecodeValues)(
            receiver, selector, "ffffi", &horizontalLine, values[0], &horizontalPage,
            values[1], values[2]);
    } else {
        ((void (*)(id, SEL, const char *, ...))originalDecodeValues)(
            receiver, selector, types, values[0], values[1], values[2], values[3],
            values[4], values[5], values[6], values[7], values[8], values[9],
            values[10], values[11], values[12], values[13], values[14], values[15],
            values[16], values[17], values[18], values[19], values[20], values[21],
            values[22], values[23], values[24], values[25], values[26], values[27],
            values[28], values[29], values[30], values[31]);
    }
}

@interface NSBundle (DR2ResourceLookup)
+ (NSArray *)pathsForResourcesOfType:(NSString *)type inDirectory:(NSString *)directory;
@end
@implementation NSBundle (DR2ResourceLookup)
+ (NSArray *)pathsForResourcesOfType:(NSString *)type
                         inDirectory:(NSString *)directory {
    NSMutableArray *result = [NSMutableArray array];
    NSArray *names = [[NSFileManager defaultManager] directoryContentsAtPath:directory];
    unsigned i;
    for (i = 0; i < [names count]; i++) {
        NSString *name = [names objectAtIndex:i];
        if (!type || [[name pathExtension] isEqual:type])
            [result addObject:[directory stringByAppendingPathComponent:name]];
    }
    return result;
}
@end

@interface NSFont (DR2ControlFont)
+ (NSFont *)controlContentFontOfSize:(float)size;
@end
@implementation NSFont (DR2ControlFont)
+ (NSFont *)controlContentFontOfSize:(float)size {
    return [self systemFontOfSize:size];
}
@end

@interface NSButtonCell (DR2Bezel)
- (void)setBezelStyle:(int)style;
- (void)setArrowPosition:(int)position;
- (void)setOnStateImage:(NSImage *)image;
- (void)setOffStateImage:(NSImage *)image;
- (void)setMixedStateImage:(NSImage *)image;
@end
@implementation NSButtonCell (DR2Bezel)
- (void)setBezelStyle:(int)style {
    [self setBezeled:style != 0];
}
- (void)setArrowPosition:(int)position {
    [self setImagePosition:position == 0 ? NSNoImage : NSImageRight];
}
- (void)setOnStateImage:(NSImage *)image {
    [self setAlternateImage:image];
}
- (void)setOffStateImage:(NSImage *)image {
    [self setImage:image];
}
- (void)setMixedStateImage:(NSImage *)image {
    [self setAlternateImage:image];
}
@end
@interface NSObject (DR2MenuPrivate)
- (NSMatrix *)itemMatrix;
@end

static id decodeMenu(id receiver, SEL selector, NSCoder *coder) {
    int version = [coder versionForClassName:@"NSMenu"];
    int flags;
    NSString *title;
    NSArray *items;
    id menuName;
    unsigned i;
    if (version < MenuObjectVersion || version == INT_MAX)
        return ((id(*)(id, SEL, id))originalMenuDecode)(receiver, selector, coder);
    receiver = [receiver initWithTitle:@""];
    if (!decodedMenus)
        decodedMenus = [[NSMutableArray alloc] init];
    [decodedMenus addObject:receiver];
    [coder decodeValuesOfObjCTypes:"i@@@", &flags, &title, &items, &menuName];
    [receiver setTitle:title ? title : @""];
    for (i = 0; i < [items count]; i++) {
        id item = [items objectAtIndex:i];
        [receiver addItemWithTitle:@"" action:NULL keyEquivalent:@""];
        [[receiver itemMatrix] putCell:item atRow:i column:0];
        if ([[item target] isKindOfClass:[NSMenu class]])
            [receiver setSubmenu:[item target] forItem:item];
    }
    [receiver sizeToFit];
    if ([menuName isEqual:@"_NSMainMenu"])
        [NSApp setMainMenu:receiver];
    else if ([menuName isEqual:@"_NSWindowsMenu"])
        [NSApp setWindowsMenu:receiver];
    else if ([menuName isEqual:@"_NSServicesMenu"])
        [NSApp setServicesMenu:receiver];
    return receiver;
}
static id decodeMenuCell(id receiver, SEL selector, NSCoder *coder) {
    int version = [coder versionForClassName:@"NSMenuItem"];
    int flags, state, tag;
    unsigned modifiers, keycode;
    id parent, title, key, image, on, off, mixed, represented, target, submenu;
    SEL action;
    if (version < MenuObjectVersion || version == INT_MAX)
        return ((id(*)(id, SEL, id))originalMenuCellDecode)(receiver, selector, coder);
    receiver = [receiver initTextCell:@""];
    parent = [coder decodeObject];
    [coder decodeValuesOfObjCTypes:"i@@IIi@@@@:i@", &flags, &title, &key, &modifiers,
                                   &keycode, &state, &image, &on, &off, &mixed, &action,
                                   &tag, &represented];
    target = [coder decodeObject];
    if (version >= SeparateMenuItemSubmenuVersion) {
        submenu = [coder decodeObject];
        if (submenu)
            target = submenu;
    }
    [receiver setTitle:title ? title : @""];
    [receiver setKeyEquivalent:key ? key : @""];
    [receiver setKeyEquivalentModifierMask:modifiers];
    [receiver setState:state];
    [receiver setTag:tag];
    [receiver setAction:action];
    [receiver setEnabled:YES];
    if (image)
        [receiver setImage:image];
    if (represented)
        [receiver setRepresentedObject:represented];
    [receiver setTarget:target];
    return receiver;
}

@implementation DR2AppKitRuntime
+ (void)load {
    Method method;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    method = class_getInstanceMethod([NSPopUpButton class], @selector(initWithCoder:));
    originalPopupDecode = method->method_imp;
    method->method_imp = (IMP)decodePopup;
    [NSUnarchiver decodeClassName:@"NSNibConnector" asClassName:@"NSIBConnector"];
    [NSUnarchiver decodeClassName:@"NSNibControlConnector"
                      asClassName:@"NSIBControlConnector"];
    [NSUnarchiver decodeClassName:@"NSNibOutletConnector"
                      asClassName:@"NSIBOutletConnector"];
    method = class_getInstanceMethod([NSScrollView class], @selector(initWithCoder:));
    originalScrollDecode = method->method_imp;
    method->method_imp = (IMP)decodeScroll;
    method = class_getInstanceMethod([NSUnarchiver class],
                                     @selector(decodeValuesOfObjCTypes:));
    originalDecodeValues = method->method_imp;
    method->method_imp = (IMP)decodeValues;
    method = class_getInstanceMethod([NSMenu class], @selector(initWithCoder:));
    originalMenuDecode = method->method_imp;
    method->method_imp = (IMP)decodeMenu;
    method = class_getInstanceMethod(NSClassFromString(@"NSMenuCell"),
                                     @selector(initWithCoder:));
    originalMenuCellDecode = method->method_imp;
    method->method_imp = (IMP)decodeMenuCell;
    [pool release];
}
@end
