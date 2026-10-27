/* Adapt DR2 Stickies startup to OPENSTEP 4.2. */
#import <AppKit/AppKit.h>
#import <objc/objc-class.h>

extern void DR2FixSubmenus(void);
static IMP originalReady;

static void ready(id receiver, SEL selector, id notification) {
    NSFileManager *files = [NSFileManager defaultManager];
    NSString *library = [NSHomeDirectory() stringByAppendingPathComponent:@"Library"];
    NSMenu *menu;
    id infoItem;
    if (![files fileExistsAtPath:library] && ![files createDirectoryAtPath:library attributes:nil])
        [NSException raise:NSInvalidArgumentException
                    format:@"Cannot create the notes directory: %@", library];
    DR2FixSubmenus();
    ((void (*)(id, SEL, id))originalReady)(receiver, selector, notification);
    menu = [NSApp mainMenu];
    [menu setTitle:@"Stickies DR2"];
    infoItem = [[menu itemArray] objectAtIndex:0];
    /* OPENSTEP has no image for the Apple menu in the DR2 nib. */
    if (![[infoItem title] length]) {
        [infoItem setImage:nil];
        [infoItem setImagePosition:NSNoImage];
        [infoItem setTitle:@"Info"];
        [menu sizeToFit];
    }
    [NSApp activateIgnoringOtherApps:YES];
}

void NSShowSystemInfoPanel(void) {
    NSRunAlertPanel(@"Stickies DR2", @"Rhapsody DR2 Stickies on OPENSTEP 4.2", @"OK", nil, nil);
}

@interface StickiesRuntime : NSObject
@end
@implementation StickiesRuntime
+ (void)load {
    Method method = class_getInstanceMethod(NSClassFromString(@"NoteController"),
                                            @selector(applicationDidFinishLaunching:));
    originalReady = method->method_imp;
    method->method_imp = (IMP)ready;
}
@end
