/* Core Foundation services used by Terminal, backed by Foundation objects. */
#import <AppKit/AppKit.h>
#include <string.h>
#include <stdlib.h>
enum {
    NSMacOSRomanStringEncoding = 30
};

const void *kCFAllocatorDefault = NULL;
NSString *kCFRunLoopCommonModes = @"TigerCommonModes";
NSString *NSURLPboardType = @"NSURLPboardType";
float kScrollWheelMultiplier = 10.0;

@implementation NSBundle (TigerInfo)
- (id)objectForInfoDictionaryKey:(NSString *)key {
    return [[self infoDictionary] objectForKey:key];
}
@end

id CFRetain(id object) {
    return [object retain];
}
void CFRelease(id object) {
    [object release];
}
int CFStringCompare(NSString *a, NSString *b, unsigned options) {
    return [a compare:b options:options & 3];
}
unsigned CFStringConvertEncodingToNSStringEncoding(unsigned encoding) {
    switch (encoding) {
    case 0x08000100:
        return NSUTF8StringEncoding;
    case 0x100:
        return NSUnicodeStringEncoding;
    case 0x600:
        return NSASCIIStringEncoding;
    case 0x201:
        return NSISOLatin1StringEncoding;
    case 0:
        return NSMacOSRomanStringEncoding;
    case 0x500:
        return NSWindowsCP1252StringEncoding;
    case 0xa01:
        return NSShiftJISStringEncoding;
    case 0x820:
        return NSJapaneseEUCStringEncoding;
    default:
        return encoding;
    }
}
unsigned CFStringConvertNSStringEncodingToEncoding(unsigned encoding) {
    switch (encoding) {
    case NSUTF8StringEncoding:
        return 0x08000100;
    case NSUnicodeStringEncoding:
        return 0x100;
    case NSASCIIStringEncoding:
        return 0x600;
    case NSISOLatin1StringEncoding:
        return 0x201;
    case NSMacOSRomanStringEncoding:
        return 0;
    case NSWindowsCP1252StringEncoding:
        return 0x500;
    case NSShiftJISStringEncoding:
        return 0xa01;
    case NSJapaneseEUCStringEncoding:
        return 0x820;
    default:
        return encoding;
    }
}

typedef struct {
    int version;
    void *info;
    const void *(*retain)(const void *);
    void (*release)(const void *);
    id (*description)(const void *);
    unsigned char (*equal)(const void *, const void *);
    unsigned (*hash)(const void *);
    void (*schedule)(void *, void *, void *);
    void (*cancel)(void *, void *, void *);
    void (*perform)(void *);
} TigerSourceContext;

@interface TigerRunLoopSource : NSObject {
  @public
    TigerSourceContext context;
    volatile BOOL signaled;
    BOOL valid;
    NSTimer *timer;
}
- (void)poll:(NSTimer *)timer;
@end
@implementation TigerRunLoopSource
- (void)poll:(NSTimer *)aTimer {
    if (valid && signaled) {
        signaled = NO;
        if (context.perform)
            context.perform(context.info);
    }
}
- (void)dealloc {
    [timer invalidate];
    [timer release];
    if (context.release)
        context.release(context.info);
    [super dealloc];
}
@end
id CFRunLoopSourceCreate(void *allocator, int order, TigerSourceContext *context) {
    TigerRunLoopSource *source = [[TigerRunLoopSource alloc] init];
    if (context->version) {
        [source release];
        return nil;
    }
    source->context = *context;
    source->valid = YES;
    if (context->retain)
        source->context.info = (void *)context->retain(context->info);
    return source;
}
void CFRunLoopAddSource(NSRunLoop *loop, TigerRunLoopSource *source, id mode) {
    if (source->timer)
        return;
    source->timer = [[NSTimer timerWithTimeInterval:0.02
                                             target:source
                                           selector:@selector(poll:)
                                           userInfo:nil
                                            repeats:YES] retain];
    [loop addTimer:source->timer forMode:NSDefaultRunLoopMode];
    [loop addTimer:source->timer forMode:NSEventTrackingRunLoopMode];
    [loop addTimer:source->timer forMode:NSModalPanelRunLoopMode];
    if (source->context.schedule)
        source->context.schedule(source->context.info, loop, mode);
}
void CFRunLoopSourceInvalidate(TigerRunLoopSource *source) {
    source->valid = NO;
    [source->timer invalidate];
    [source->timer release];
    source->timer = nil;
}
void CFRunLoopSourceSignal(TigerRunLoopSource *source) {
    source->signaled = YES;
}
void CFRunLoopWakeUp(NSRunLoop *loop) { /* The bounded native timer services the source. */ }
@implementation NSRunLoop (TigerCFRunLoop)
- (void *)getCFRunLoop {
    return self;
}
@end

/* Tiger passes the CoreFoundation common-mode marker to delayed NSObject
 * performs. OPENSTEP has no common-mode set, so expand it to its UI modes. */
static IMP tigerNativeDelayedPerform;
static void tigerDelayedPerform(id object, SEL method, SEL action, id argument, double delay,
                                NSArray *modes) {
    NSMutableArray *expanded;
    unsigned i;
    if ([modes containsObject:kCFRunLoopCommonModes]) {
        expanded = [NSMutableArray arrayWithArray:modes];
        [expanded removeObject:kCFRunLoopCommonModes];
        for (i = 0; i < 3; i++) {
            id mode = i == 0 ? NSDefaultRunLoopMode
                             : (i == 1 ? NSEventTrackingRunLoopMode : NSModalPanelRunLoopMode);
            if (![expanded containsObject:mode])
                [expanded addObject:mode];
        }
        modes = expanded;
    }
    ((void (*)(id, SEL, SEL, id, double, id))tigerNativeDelayedPerform)(object, method, action,
                                                                        argument, delay, modes);
}
void TigerInitializeRunLoop(void) {
    Method method = class_getInstanceMethod([NSObject class], @selector
                                            (performSelector:withObject:afterDelay:inModes:));
    tigerNativeDelayedPerform = method->method_imp;
    method->method_imp = (IMP)tigerDelayedPerform;
}

@interface NSURL : NSObject {
    NSString *tigerURL;
}
+ URLWithString:(NSString *)string;
+ fileURLWithPath:(NSString *)path;
- initWithString:(NSString *)string;
- (NSString *)absoluteString;
- (NSString *)path;
- (NSString *)scheme;
@end
@implementation NSURL
+ URLWithString:(NSString *)string {
    return [[[self alloc] initWithString:string] autorelease];
}
+ fileURLWithPath:(NSString *)path {
    return [self
        URLWithString:[@"file://" stringByAppendingString:[path stringByExpandingTildeInPath]]];
}
- initWithString:(NSString *)string {
    self = [super init];
    tigerURL = [string copy];
    return self;
}
- (NSString *)absoluteString {
    return tigerURL;
}
- (NSString *)scheme {
    NSRange colon = [tigerURL rangeOfString:@":"];
    return colon.location == NSNotFound ? nil : [tigerURL substringToIndex:colon.location];
}
- (NSString *)path {
    NSRange scheme = [tigerURL rangeOfString:@"://"];
    NSString *path = tigerURL;
    if (scheme.location != NSNotFound) {
        NSRange slash = [tigerURL
            rangeOfString:@"/"
                  options:0
                    range:NSMakeRange(NSMaxRange(scheme), [tigerURL length] - NSMaxRange(scheme))];
        if (slash.location == NSNotFound)
            path = @"";
        else
            path = [tigerURL substringFromIndex:slash.location];
    }
    return path;
}
- (BOOL)isFileURL {
    return [[self scheme] isEqual:@"file"];
}
- (id)copyWithZone:(NSZone *)zone {
    return [self retain];
}
- (void)dealloc {
    [tigerURL release];
    [super dealloc];
}
@end
id CFURLCreateWithBytes(void *allocator, const unsigned char *bytes, int length, unsigned encoding,
                        id base) {
    NSString *string = [[[NSString alloc]
        initWithData:[NSData dataWithBytes:bytes length:length]
            encoding:CFStringConvertEncodingToNSStringEncoding(encoding)] autorelease];
    return [[NSURL alloc] initWithString:string];
}
id CFURLCopyPath(NSURL *url) {
    return [[url path] copy];
}
