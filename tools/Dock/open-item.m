#import <AppKit/AppKit.h>
#import <AppKit/obsoleteSpeaker.h>
#include <libc.h>

extern NSString *_NXGetWorkspaceName(void);

static BOOL activateApplication(NSString *path)
{
    Speaker *speaker = [[Speaker alloc] init];
    port_t port = NXPortFromName(_NXGetWorkspaceName(), @"");
    NSString *name = [[path lastPathComponent] stringByDeletingPathExtension];
    int handle = 0, status = 0, result;
    if (!port) { [speaker release]; return NO; }
    [speaker setSendPort:port];
    [speaker setSendTimeout:3000];
    [speaker setReplyTimeout:3000];
    result = [speaker selectorRPC:@"getAppHandle:status:forPath:name:mustBeIdle:"
        paramTypes:"IIcci", &handle, &status, [path cString], [name cString], 0];
    if (!result && handle)
        result = [speaker selectorRPC:@"activateAppWithHandle:" paramTypes:"i", handle];
    else result = -1;
    fprintf(stderr, "Dock PR1 activate: handle=%d status=%d result=%d\n", handle, status, result);
    [speaker release];
    return result == 0;
}

/* Keep PR1's private classes out of the native Workspace client. */
int main(int argc, char **argv)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    NSString *path;
    BOOL result;
    if (argc < 2) return 2;
    path = [NSString stringWithCString:argv[1]];
    if ([[path pathExtension] isEqual:@"app"] && !(argc > 3 && atoi(argv[3])))
        result = [workspace launchApplication:path];
    else
        result = [workspace openFile:path];
    if (result && [[path pathExtension] isEqual:@"app"])
        result = activateApplication(path);
    if (result && argc > 2 && atoi(argv[2])) [workspace hideOtherApplications];
    if (!result) fprintf(stderr, "Dock PR1: could not open %s\n", argv[1]);
    [pool release];
    return result ? 0 : 1;
}
