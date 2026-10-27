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
    fprintf(stderr, "Viewer PR1 activate: handle=%d status=%d result=%d\n", handle, status, result);
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
    if ([path isEqual:@"--check-disks"]) {
        [workspace checkForRemovableMedia];
        [pool release];
        return 0;
    }
    if ([path isEqual:@"--recycle"] && argc >= 3) {
        int i, tag;
        result = YES;
        for (i = 2; i < argc; i++) {
            NSString *source = [NSString stringWithCString:argv[i]];
            if (![source isAbsolutePath] || ![workspace performFileOperation:NSWorkspaceRecycleOperation
                source:[source stringByDeletingLastPathComponent] destination:@""
                files:[NSArray arrayWithObject:[source lastPathComponent]] tag:&tag]) {
                fprintf(stderr, "Viewer PR1: could not recycle %s\n", argv[i]);
                result = NO;
                break;
            }
        }
        [pool release];
        return result ? 0 : 1;
    }
    if ([path isEqual:@"--duplicate"] && argc >= 3) {
        NSFileManager *manager = [NSFileManager defaultManager];
        int i;
        result = YES;
        for (i = 2; i < argc; i++) {
            NSString *source = [NSString stringWithCString:argv[i]];
            NSString *directory = [source stringByDeletingLastPathComponent];
            NSString *base = [@"Copy Of " stringByAppendingString:[source lastPathComponent]];
            NSString *destination = [directory stringByAppendingPathComponent:base];
            unsigned int number = 2;
            /* Test entries without following links, including dangling symlinks. */
            while ([manager fileAttributesAtPath:destination traverseLink:NO]) {
                NSString *extension = [base pathExtension];
                NSString *name = [NSString stringWithFormat:@"%@ %u",
                    [base stringByDeletingPathExtension], number++];
                if ([extension length]) name = [name stringByAppendingPathExtension:extension];
                destination = [directory stringByAppendingPathComponent:name];
            }
            if (![source isAbsolutePath] || ![manager copyPath:source toPath:destination handler:nil]) {
                fprintf(stderr, "Viewer PR1: could not duplicate %s to %s\n",
                    [source cString], [destination cString]);
                result = NO;
                break;
            }
            fprintf(stderr, "Viewer PR1 duplicated %s to %s\n", [source cString], [destination cString]);
        }
        [workspace noteFileSystemChanged];
        [pool release];
        return result ? 0 : 1;
    }
    if (argc > 4)
        result = [workspace openFile:path withApplication:[NSString stringWithCString:argv[4]]];
    else if ([[path pathExtension] isEqual:@"app"] && !(argc > 3 && atoi(argv[3])))
        result = [workspace launchApplication:path];
    else
        result = [workspace openFile:path];
    if (result && [[path pathExtension] isEqual:@"app"])
        result = activateApplication(path);
    if (result && argc > 2 && atoi(argv[2])) [workspace hideOtherApplications];
    if (!result) fprintf(stderr, "Viewer PR1: could not open %s\n", argv[1]);
    [pool release];
    return result ? 0 : 1;
}
