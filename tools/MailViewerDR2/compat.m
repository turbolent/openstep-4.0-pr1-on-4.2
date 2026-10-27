/* Adapt DR2 MailViewer startup to OPENSTEP 4.2. */
#import <AppKit/AppKit.h>
#import <objc/objc-class.h>

extern void DR2FixSubmenus(void);
static IMP originalMailReady;

static void mailReady(id receiver, SEL selector, id notification) {
    DR2FixSubmenus();
    ((void (*)(id, SEL, id))originalMailReady)(receiver, selector, notification);
    [[NSApp mainMenu] setTitle:@"MailViewer DR2"];
    [NSApp activateIgnoringOtherApps:YES];
}
@interface DR2MailRuntime : NSObject
@end
@implementation DR2MailRuntime
+ (void)load {
    Method method;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    method = class_getInstanceMethod(NSClassFromString(@"MailApp"),
                                     @selector(applicationDidFinishLaunching:));
    originalMailReady = method->method_imp;
    method->method_imp = (IMP)mailReady;
    [pool release];
}
@end

NSString *NSLinkAttributeName = @"NSLink";
void NSShowSystemInfoPanel(void) {
    NSRunAlertPanel(@"MailViewer DR2", @"Rhapsody DR2 MailViewer on OPENSTEP 4.2",
                    @"OK", nil, nil);
}
