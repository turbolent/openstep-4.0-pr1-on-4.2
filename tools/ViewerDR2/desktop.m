/* Expose Viewer's original panels and file-selection methods to Workspace DR2. */
#import <AppKit/AppKit.h>
#import <AppKit/obsoleteSpeaker.h>
#import <objc/objc-class.h>
#include "common/dr2-viewer-service.h"

extern NSString *_NXGetWorkspaceName(void);

enum {
    DesktopReplyTimeoutMilliseconds = 1000,
    ApplicationRecordFields = 4,
    NativeWorkspaceHandle = 1
};
static id applicationObserver;
static const NSTimeInterval ApplicationRefreshInterval = 1;

@interface NSObject (ViewerDesktopMethods)
- processManager;
- viewerServices;
- (void)showProcesses:(id)sender;
- (BOOL)openNode:(id)node;
+ fileNodeWithPath:(NSString *)path;
- (BOOL)selectFile:(NSString *)path inFileViewerRootedAt:(NSString *)root;
- (void)appsChanged:(id)sender;
@end

static Speaker *desktopSpeaker(void) {
    Speaker *speaker = [[[Speaker alloc] init] autorelease];
    [speaker setSendPort:NXPortFromName(_NXGetWorkspaceName(), @"")];
    [speaker setSendTimeout:DesktopReplyTimeoutMilliseconds];
    [speaker setReplyTimeout:DesktopReplyTimeoutMilliseconds];
    return speaker;
}

static NSArray *desktopApplications(void) {
    char *paths = NULL;
    NSArray *records;
    NSMutableArray *result = [NSMutableArray array];
    unsigned i;
    if ([desktopSpeaker() selectorRPC:@"getActiveAppPaths:" paramTypes:"C", &paths] || !paths)
        return nil;
    records = [[NSString stringWithCString:paths] componentsSeparatedByString:@"\t"];
    for (i = 0; i < [records count]; i++) {
        NSString *record = [records objectAtIndex:i];
        NSArray *fields = [record componentsSeparatedByString:@"\n"];
        if ([fields count] == ApplicationRecordFields) {
            NSString *name = [fields objectAtIndex:0];
            if ([[fields objectAtIndex:3] intValue] == NativeWorkspaceHandle)
                name = @"Workspace Manager";
            else if ([[fields objectAtIndex:1] isEqual:[[NSBundle mainBundle] bundlePath]])
                name = @"Viewer DR2";
            record = [[NSArray arrayWithObjects:name, [fields objectAtIndex:1],
                                                [fields objectAtIndex:2], [fields objectAtIndex:3],
                                                nil] componentsJoinedByString:@"\n"];
            [result addObject:record];
        }
    }
    return result;
}

@interface ViewerServices : NSObject
@end
@implementation ViewerServices (DR2DesktopApplications)
- (NSArray *)allUserApps {
    NSArray *apps = desktopApplications();
    return apps ? apps : [NSArray array];
}
- (void)activateApp:(int)handle {
    if ([desktopSpeaker() selectorRPC:@"activateAppWithHandle:" paramTypes:"i", handle])
        NSBeep();
}
- (void)deactivateApp:(int)handle {
    /* The original panel confirms Kill and protects the desktop manager. */
    if (handle <= NativeWorkspaceHandle || [desktopSpeaker() selectorRPC:@"killAppWithHandle:"
                                                              paramTypes:"i", handle])
        NSBeep();
}
- (void)registerForAppStatusChange:(id)observer {
    applicationObserver = observer;
}
- (void)unregisterForAppStatusChange:(id)observer {
    if (applicationObserver == observer)
        applicationObserver = nil;
}
@end

@interface DR2ViewerDesktop : NSObject <DR2ViewerService> {
    NSArray *lastApplications;
}
- (void)refreshApplications:(id)sender;
@end
@implementation DR2ViewerDesktop
- (void)dealloc {
    [lastApplications release];
    [super dealloc];
}
- (BOOL)showProcesses {
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp showProcesses:nil];
    return YES;
}
- (BOOL)openPath:(bycopy NSString *)path {
    BOOL result;
    if (![path isKindOfClass:[NSString class]] || ![path isAbsolutePath] ||
        ![[NSFileManager defaultManager] fileExistsAtPath:path])
        return NO;
    result = [NSApp openNode:[NSClassFromString(@"ViewerFileNode") fileNodeWithPath:path]];
    if (result)
        [NSApp activateIgnoringOtherApps:YES];
    return result;
}
- (BOOL)revealPath:(bycopy NSString *)path {
    BOOL result;
    if (![path isKindOfClass:[NSString class]] || ![path isAbsolutePath] ||
        ![[NSFileManager defaultManager] fileExistsAtPath:path])
        return NO;
    result = [[NSApp viewerServices] selectFile:path
                           inFileViewerRootedAt:[path stringByDeletingLastPathComponent]];
    if (result)
        [NSApp activateIgnoringOtherApps:YES];
    return result;
}
- (void)refreshApplications:(id)sender {
    NSArray *apps;
    Ivar field;
    NSWindow *window;
    if (!applicationObserver)
        return;
    field = class_getInstanceVariable([applicationObserver class], "window");
    window = field ? *(id *)((char *)applicationObserver + field->ivar_offset) : nil;
    if (![window isVisible])
        return;
    apps = desktopApplications();
    if (apps && ![apps isEqual:lastApplications]) {
        [apps retain];
        [lastApplications release];
        lastApplications = apps;
        [applicationObserver appsChanged:nil];
    }
}
@end

void DR2StartViewerDesktop(void) {
    static NSConnection *connection;
    DR2ViewerDesktop *service;
    if (connection)
        return;
    service = [[DR2ViewerDesktop alloc] init];
    connection = [[NSConnection connectionWithReceivePort:[NSPort port] sendPort:nil] retain];
    [connection setRootObject:service];
    if (![connection registerName:DR2ViewerServiceName()]) {
        NSLog(@"Viewer DR2 desktop service is already registered.");
        [connection invalidate];
        [connection release];
        connection = nil;
    }
    [NSTimer scheduledTimerWithTimeInterval:ApplicationRefreshInterval
                                     target:service
                                   selector:@selector(refreshApplications:)
                                   userInfo:nil
                                    repeats:YES];
    [service release];
}
