#import <AppKit/AppKit.h>
#import <objc/objc-class.h>
#include "runtime-path.h"
extern NSString *_NXGetWorkspaceName(void);

@interface _NSWorkspaceDragManager : NSObject
- (port_t)_dragServerPort;
@end

static NSFont *(*originalScreenFont)(id, SEL);
static NSFont *runtimeScreenFont(NSFont *font, SEL selector) {
    /* The native server cannot discover DR2's private Charcoal bitmap face. */
    if ([[font fontName] isEqual:@"Charcoal"])
        return font;
    return originalScreenFont(font, selector);
}

@interface DR2InterfaceDefaults : NSObject
+ (void)loadInterfaceFonts:(NSNotification *)notification;
@end
@implementation DR2InterfaceDefaults
+ (void)load {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    Class fontClass = objc_getClass("NSFont");
    Method method = fontClass ? class_getInstanceMethod(fontClass, @selector(screenFont)) : NULL;
    if (method) {
        originalScreenFont = (NSFont * (*)(id, SEL)) method->method_imp;
        method->method_imp = (IMP)runtimeScreenFont;
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(loadInterfaceFonts:)
                   name:@"NSApplicationWillFinishLaunchingNotification"
                 object:nil];
    }
    [[NSUserDefaults standardUserDefaults]
        registerDefaults:[NSDictionary dictionaryWithObject:@"macintosh"
                                                     forKey:@"NSInterfaceStyle"]];
    [pool release];
}
+ (void)loadInterfaceFonts:(NSNotification *)notification {
    /* Define the stock outline in this application's PostScript context. */
    if (DPSGetCurrentContext()) {
        DPSrun(DPSGetCurrentContext(), DR2_RUNTIME_PATH "/Library/Fonts/Charcoal.font/Charcoal");
        PSWait();
    }
}
@end

@implementation NSTask (DR2PrivateTools)
+ (NSTask *)launchedTaskWithLaunchPath:(NSString *)path arguments:(NSArray *)arguments {
    NSTask *task = [[[self alloc] init] autorelease];
    if ([path isEqual:@"/usr/bin/fcache"])
        path = [NSString stringWithCString:DR2_RUNTIME_PATH "/fcache"];
    [task setLaunchPath:path];
    [task setArguments:arguments];
    [task launch];
    return task;
}
@end
@implementation _NSWorkspaceDragManager (NativeDragService)
- (port_t)_dragServerPort {
    return NXPortFromName(_NXGetWorkspaceName(), @"");
}
@end

@interface NSObject (DR2PrivateFontServer)
- (id)findServerWithName:(NSString *)name;
@end
static id privateFontServer;
@implementation NSFontManager (DR2FontService)
+ (void)privateFontServerDied:(NSNotification *)notification {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSConnectionDidDieNotification
                                                  object:[notification object]];
    [privateFontServer release];
    privateFontServer = nil;
}
+ (id)proxyForFontInfoServer {
    if (!privateFontServer) {
        id root = [NSConnection
            rootProxyForConnectionWithRegisteredName:[NSString stringWithCString:DR2_PBS_NAME]
                                                host:nil];
        privateFontServer = [[root findServerWithName:@"FontInfoServer"] retain];
        if (privateFontServer)
            [[NSNotificationCenter defaultCenter]
                addObserver:self
                   selector:@selector(privateFontServerDied:)
                       name:NSConnectionDidDieNotification
                     object:[privateFontServer connectionForProxy]];
    }
    return privateFontServer;
}
@end
