/* Native application services used by Terminal. */
#import <AppKit/AppKit.h>
#import <objc/objc-class.h>
#include <stdarg.h>
#include <unistd.h>

void NSBeginAlertSheet(NSString *title, NSString *primary, NSString *alternate, NSString *other,
                       NSWindow *window, id delegate, SEL didEnd, SEL didDismiss, void *info,
                       NSString *format, ...) {
    va_list arguments;
    NSString *message;
    int result;
    va_start(arguments, format);
    message = [[[NSString alloc] initWithFormat:format arguments:arguments] autorelease];
    va_end(arguments);
    result = NSRunAlertPanel(title, @"%@", primary, alternate, other, message);
    if (didEnd && [delegate respondsToSelector:didEnd])
        ((void (*)(id, SEL, id, int, void *))[delegate methodForSelector:didEnd])(
            delegate, didEnd, window, result, info);
    if (didDismiss && [delegate respondsToSelector:didDismiss])
        ((void (*)(id, SEL, id, int, void *))[delegate methodForSelector:didDismiss])(
            delegate, didDismiss, window, result, info);
}
void NSShowSystemInfoPanel(void) {
    NSRunAlertPanel(
        @"Terminal",
        @"Terminal 1.5 (133)\nTiger Intel application with an OPENSTEP compatibility bridge.",
        @"OK", nil, nil);
}
typedef struct {
    unsigned high, low;
} TigerProcessSerialNumber;
int CPSGetCurrentProcess(TigerProcessSerialNumber *process) {
    if (!process)
        return -50;
    process->high = 0;
    process->low = getpid();
    return 0;
}
int CPSStealKeyFocus(const TigerProcessSerialNumber *process, unsigned options) {
    if (!process || process->low != (unsigned)getpid())
        return -50;
    [NSApp activateIgnoringOtherApps:YES];
    return 0;
}
int CPSReleaseKeyFocus(const TigerProcessSerialNumber *process) {
    if (!process || process->low != (unsigned)getpid())
        return -50;
    [[NSApp keyWindow] resignKeyWindow];
    return 0;
}

/* OPENSTEP has no Quartz secure-input service. The original ignores that
 * service's error code, so also intercept its UI/state update to avoid a
 * checked menu item that would falsely promise protected input. */
int CGSSetSecureEventInput(int connection, int enabled) {
    return enabled ? -4 : 0;
}
static void tigerClearSecureInput(id app, SEL selector) {
    const char *names[] = {"secureKeyboardEntry", "secureKeyboardEntryOn"};
    unsigned i;
    Ivar item = class_getInstanceVariable([app class], "secureKeyboardMenuItem");
    for (i = 0; i < 2; i++) {
        Ivar field = class_getInstanceVariable([app class], names[i]);
        if (field)
            *(unsigned char *)((char *)app + field->ivar_offset) = 0;
    }
    if (item)
        [*(id *)((char *)app + item->ivar_offset) setState:0];
}
static void tigerSecureInputUnavailable(id app, SEL selector, id sender) {
    tigerClearSecureInput(app, selector);
    NSRunAlertPanel(
        @"Secure Keyboard Entry",
        @"OPENSTEP does not provide Tiger's secure keyboard input service. Secure Keyboard Entry is unavailable in this port.",
        @"OK", nil, nil);
}
void TigerInitializeServices(void) {
    Class app = NSClassFromString(@"TerminalApp");
    Method method = class_getInstanceMethod(app, sel_getUid("_updateSecureKeyboardEntry"));
    if (method)
        method->method_imp = (IMP)tigerClearSecureInput;
    method = class_getInstanceMethod(app, sel_getUid("secureKeyboardEntry:"));
    if (method)
        method->method_imp = (IMP)tigerSecureInputUnavailable;
}

/* Terminal uses NSSound only for its alert bell. OPENSTEP supplies that sound
 * through NSBeep; retain Tiger's asynchronous completion/delegate contract. */
@interface NSSound : NSObject {
    id tigerSoundDelegate;
    BOOL tigerPlaying;
}
@end
@implementation NSSound
- initWithData:(NSData *)data {
    return [super init];
}
- (void)setDelegate:(id)delegate {
    tigerSoundDelegate = delegate;
}
- (id)delegate {
    return tigerSoundDelegate;
}
- (BOOL)isPlaying {
    return tigerPlaying;
}
- (void)tigerFinished:(id)argument {
    SEL selector = sel_getUid("sound:didFinishPlaying:");
    if (!tigerPlaying)
        return;
    tigerPlaying = NO;
    if ([tigerSoundDelegate respondsToSelector:selector])
        ((void (*)(id, SEL, id, BOOL))[tigerSoundDelegate methodForSelector:selector])(
            tigerSoundDelegate, selector, self, YES);
}
- (BOOL)play {
    if (tigerPlaying)
        return NO;
    tigerPlaying = YES;
    NSBeep();
    [self performSelector:@selector(tigerFinished:) withObject:nil afterDelay:0.1];
    return YES;
}
- (BOOL)stop {
    tigerPlaying = NO;
    return YES;
}
@end
int SystemSoundGetProperty(unsigned property, unsigned qualifier, unsigned *size, id *value) {
    if (property != 1 || !size || !value || *size < sizeof(id))
        return -50;
    /* A null URL asks Terminal to use its default bell data. NSSound above
     * routes the bell request to OPENSTEP's configured alert sound. */
    *value = nil;
    *size = sizeof(id);
    return 0;
}
