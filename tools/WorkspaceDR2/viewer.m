/* Launch the companion Viewer and send requests without blocking the menu. */
#import <AppKit/AppKit.h>
#include "common/dr2-viewer-service.h"

enum {
    ShowViewerProcesses,
    OpenViewerPath,
    RevealViewerPath
};
static const NSTimeInterval ViewerLaunchTimeout = 15;
static const NSTimeInterval ViewerPollInterval = 0.2;
static const NSTimeInterval ViewerReplyTimeout = 2;

@interface NSObject (WorkspaceViewerFallback)
- (void)showLocalProcesses:(id)sender;
@end

static NSString *companionViewer(void) {
    NSString *path = [[NSUserDefaults standardUserDefaults] stringForKey:@"ViewerDR2Path"];
    NSDictionary *info;
    if (![path length])
        path = [[[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent]
            stringByAppendingPathComponent:@"ViewerDR2.app"];
    if (![path isAbsolutePath])
        return nil;
    info = [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:
                                                                @"Resources/Info-nextstep.plist"]];
    if ([[info objectForKey:@"DR2DesktopServiceVersion"] intValue] != DR2ViewerServiceVersion)
        return nil;
    return path;
}

@interface WorkspaceViewerClient : NSObject {
    NSMutableArray *requests;
    NSTimer *timer;
    NSDate *deadline;
}
- (BOOL)request:(int)kind path:(NSString *)path;
- (void)poll:(NSTimer *)sender;
@end
@implementation WorkspaceViewerClient
- init {
    self = [super init];
    requests = [[NSMutableArray alloc] init];
    return self;
}
- (BOOL)request:(int)kind path:(NSString *)path {
    NSString *viewer = companionViewer();
    BOOL launched = YES;
    if (!viewer)
        return NO;
    [requests
        addObject:[NSArray arrayWithObjects:[NSNumber numberWithInt:kind], path ? path : @"", nil]];
    if (!timer) {
        NS_DURING
            NSConnection *connection =
                [NSConnection connectionWithRegisteredName:DR2ViewerServiceName() host:@""];
            if (!connection) {
                NSTask *task = [[[NSTask alloc] init] autorelease];
                NSMutableDictionary *environment =
                    [[[NSProcessInfo processInfo] environment] mutableCopy];
                [environment removeObjectForKey:@"DYLD_INSERT_LIBRARIES"];
                [environment removeObjectForKey:@"DYLD_LIBRARY_PATH"];
                [environment removeObjectForKey:@"DYLD_FRAMEWORK_PATH"];
                [task setEnvironment:environment];
                [environment release];
                [task setLaunchPath:@"/usr/bin/open"];
                [task setArguments:[NSArray arrayWithObject:viewer]];
                [task launch];
            }
        NS_HANDLER
            NSLog(@"Could not connect to Viewer DR2: %@", localException);
            launched = NO;
        NS_ENDHANDLER
        if (!launched) {
            [requests removeLastObject];
            return NO;
        }
        deadline = [[NSDate dateWithTimeIntervalSinceNow:ViewerLaunchTimeout] retain];
        timer = [[NSTimer scheduledTimerWithTimeInterval:ViewerPollInterval
                                                  target:self
                                                selector:@selector(poll:)
                                                userInfo:nil
                                                 repeats:YES] retain];
    }
    return YES;
}
- (void)finish {
    [timer invalidate];
    [timer release];
    timer = nil;
    [deadline release];
    deadline = nil;
}
- (void)failedRequest:(NSArray *)request {
    if ([[request objectAtIndex:0] intValue] == ShowViewerProcesses)
        [[NSApp delegate] showLocalProcesses:nil];
    else
        NSRunAlertPanel(@"Workspace DR2", @"Viewer DR2 could not open %@.", @"OK", nil, nil,
                        [request objectAtIndex:1]);
}
- (void)poll:(NSTimer *)sender {
    NSConnection *connection;
    NSArray *pending;
    unsigned i;
    id<DR2ViewerService> viewer = nil;
    BOOL expired = [deadline timeIntervalSinceNow] <= 0;
    NS_DURING
        connection = [NSConnection connectionWithRegisteredName:DR2ViewerServiceName() host:@""];
        [connection setRequestTimeout:ViewerReplyTimeout];
        [connection setReplyTimeout:ViewerReplyTimeout];
        viewer = (id<DR2ViewerService>)[connection rootProxy];
    NS_HANDLER
        viewer = nil;
        expired = YES;
    NS_ENDHANDLER
    if (!viewer && !expired)
        return;
    pending = [requests copy];
    [requests removeAllObjects];
    [self finish];
    for (i = 0; i < [pending count]; i++) {
        NSArray *request = [pending objectAtIndex:i];
        NSString *path = [request objectAtIndex:1];
        int kind = [[request objectAtIndex:0] intValue];
        BOOL result = NO;
        if (viewer) {
            NS_DURING
                if (kind == ShowViewerProcesses)
                    result = [viewer showProcesses];
                else if (kind == OpenViewerPath)
                    result = [viewer openPath:path];
                else
                    result = [viewer revealPath:path];
            NS_HANDLER
                NSLog(@"Viewer DR2 request failed: %@", localException);
            NS_ENDHANDLER
        }
        if (!result)
            [self failedRequest:request];
    }
    [pending release];
}
@end

static BOOL requestViewer(int kind, NSString *path) {
    static WorkspaceViewerClient *client;
    if (!client)
        client = [[WorkspaceViewerClient alloc] init];
    return [client request:kind path:path];
}
BOOL WorkspaceDR2ShowProcesses(void) {
    return requestViewer(ShowViewerProcesses, nil);
}
BOOL WorkspaceDR2HasViewer(void) {
    return companionViewer() != nil;
}
BOOL WorkspaceDR2OpenPath(NSString *path) {
    return requestViewer(OpenViewerPath, path);
}
BOOL WorkspaceDR2RevealPath(NSString *path) {
    return requestViewer(RevealViewerPath, path);
}
