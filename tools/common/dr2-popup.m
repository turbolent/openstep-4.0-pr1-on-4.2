/* Adapt DR2 AppSupport icon popups to OPENSTEP 4.2. */
#import <AppKit/AppKit.h>
#import <objc/objc-class.h>
#include <string.h>

@interface NSIconPopUpButton : NSPopUpButton
@end
@interface DR2IconItem : NSObject {
    NSString *title;
    NSImage *image;
}
- initWithTitle:(NSString *)value;
- (NSString *)title;
- (NSImage *)image;
- (void)setImage:(NSImage *)value;
@end
@implementation DR2IconItem
- initWithTitle:(NSString *)value {
    self = [super init];
    title = [value copy];
    return self;
}
- (NSString *)title {
    return title;
}
- (NSImage *)image {
    return image;
}
- (void)setImage:(NSImage *)value {
    [value retain];
    [image release];
    image = value;
}
- (void)dealloc {
    [image release];
    [title release];
    [super dealloc];
}
@end

static IMP originalButtonTitle;
static NSString *iconButtonTitle(id receiver, SEL selector) {
    id identity, control;
    /* 4.2 hides image-only titles even from its popup's item lookup. */
    if ([receiver respondsToSelector:@selector(representedObject)]) {
        identity = [receiver representedObject];
        if ([identity isKindOfClass:[DR2IconItem class]])
            return [identity title];
    }
    control = [receiver controlView];
    if ([control isKindOfClass:[NSIconPopUpButton class]] && [control selectedItem])
        return [[control selectedItem] title];
    return ((id(*)(id, SEL))originalButtonTitle)(receiver, selector);
}

static void syncPopupImage(NSPopUpButton *button) {
    id item = [button selectedItem];
    NSButtonCell *cell = [button cell];
    if (item) {
        DR2IconItem *identity = [item representedObject];
        NSImage *image = [identity image];
        if (!image)
            image = [item image];
        [cell setTitle:[item title]];
        [cell setImage:image];
        [cell setAlternateImage:image];
        [cell setImagePosition:NSImageOnly];
    }
}
static void restorePopupImages(NSArray *items) {
    unsigned i;
    for (i = 0; i < [items count]; i++) {
        id item = [items objectAtIndex:i];
        [item setImage:[[item representedObject] image]];
    }
}
@implementation NSIconPopUpButton (DR2IconItems)
- (void)setTitle:(NSString *)title {
    /* 4.2's implementation adds a menu item; DR2 only changes the caption. */
    [[self cell] setTitle:title];
    [self setNeedsDisplay:YES];
}
- (void)addItemWithTitle:(NSString *)title {
    /* 4.2 identifies popup items by title, even when only images are visible. */
    NSString *unique = [NSString stringWithFormat:@"DR2 item %d", [self numberOfItems]];
    DR2IconItem *identity = [[DR2IconItem alloc] initWithTitle:unique];
    [super addItemWithTitle:unique];
    [[self lastItem] setRepresentedObject:identity];
    [identity release];
    [(id)[self lastItem] setImagePosition:NSImageOnly];
}
- (void)drawRect:(NSRect)rect {
    syncPopupImage(self);
    [super drawRect:rect];
}
- (void)selectItemAtIndex:(int)index {
    [super selectItemAtIndex:index];
    syncPopupImage(self);
    [self setNeedsDisplay:YES];
}
- (BOOL)sendAction:(SEL)action to:(id)target {
    BOOL result;
    /* MailViewer chooses the action by image name, before the next redraw. */
    syncPopupImage(self);
    if (action && !strcmp(sel_getName(action), "popUp:")) {
        NSMutableArray *items = [[NSMutableArray alloc] init];
        unsigned i;
        /* The matrix's internal cell array deep-copies its cells on copy. */
        for (i = 0; i < [self numberOfItems]; i++) {
            id item = [self itemAtIndex:i];
            [[item representedObject] setImage:[item image]];
            [items addObject:item];
        }
        /* Native tracking borrows the selected item's image, then clears it. */
        NS_DURING
            result = [super sendAction:action to:target];
        NS_HANDLER
            restorePopupImages(items);
            [items release];
            [localException raise];
        NS_ENDHANDLER
        restorePopupImages(items);
        [items release];
        syncPopupImage(self);
        [self setNeedsDisplay:YES];
        return result;
    }
    return [super sendAction:action to:target];
}
@end

@interface DR2PopupRuntime : NSObject
@end
@implementation DR2PopupRuntime
+ (void)load {
    Method method = class_getInstanceMethod([NSButtonCell class], @selector(title));
    originalButtonTitle = method->method_imp;
    method->method_imp = (IMP)iconButtonTitle;
}
@end
