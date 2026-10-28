/* Start private services and reuse running DR2 applications. */
#import <AppKit/AppKit.h>
#import <objc/objc-runtime.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <unistd.h>
#include "runtime-path.h"

enum {
    ServicePollLimit = 100,
    ServicePollMicroseconds = 100000,
    ServiceChildFailure = 127,
    LibraryDirectoryMode = 0755,
    PrivateDirectoryMode = 0700,
    PrivateFileMode = 0600
};

static BOOL serviceAvailable(void) {
    return [[NSPortNameServer defaultPortNameServer]
               portForName:[NSString stringWithCString:DR2_PBS_NAME]
                      host:nil] != nil;
}

static BOOL createDirectory(NSString *path, int mode) {
    struct stat attributes;
    const char *name = [path cString];
    if (!mkdir(name, mode))
        return YES;
    if (errno == EEXIST && !stat(name, &attributes) && (attributes.st_mode & S_IFMT) == S_IFDIR)
        return YES;
    NSLog(@"Cannot create %@: %s", path, strerror(errno));
    return NO;
}

static int startService(int lock, const char *logPath) {
    const char *executable = DR2_RUNTIME_PATH "/pbs-dr2";
    int child = fork();
    if (!child) {
        int input, output;
        const char failure[] = "Cannot execute the DR2 runtime service binary.\n";
        char *arguments[] = {(char *)executable, "-a", NULL};
        close(lock);
        input = open("/dev/null", O_RDONLY);
        if (input < 0 || dup2(input, STDIN_FILENO) < 0)
            _exit(ServiceChildFailure);
        if (input != STDIN_FILENO)
            close(input);
        output = open(logPath, O_WRONLY | O_CREAT | O_APPEND, PrivateFileMode);
        if (output < 0 || dup2(output, STDOUT_FILENO) < 0 || dup2(output, STDERR_FILENO) < 0)
            _exit(ServiceChildFailure);
        if (output > STDERR_FILENO)
            close(output);
        execv(executable, arguments);
        write(STDERR_FILENO, failure, sizeof(failure) - 1);
        _exit(ServiceChildFailure);
    }
    return child;
}

static BOOL ensureService(void) {
    NSString *library, *state, *name, *logPath, *lockPath;
    union wait status;
    int child;
    int lock, poll;
    BOOL ready = NO;
    if (serviceAvailable())
        return YES;
    library = [NSHomeDirectory() stringByAppendingPathComponent:@"Library"];
    state = [library stringByAppendingPathComponent:@"DR2Runtime"];
    if (!createDirectory(library, LibraryDirectoryMode) ||
        !createDirectory([library stringByAppendingPathComponent:@"Fonts"], LibraryDirectoryMode) ||
        !createDirectory(state, PrivateDirectoryMode))
        return NO;
    name = [NSString stringWithCString:DR2_PBS_NAME];
    lockPath = [state stringByAppendingPathComponent:[name stringByAppendingString:@".lock"]];
    logPath = [state stringByAppendingPathComponent:[name stringByAppendingString:@".log"]];
    lock = open([lockPath cString], O_RDWR | O_CREAT, PrivateFileMode);
    if (lock < 0) {
        NSLog(@"Cannot open %@: %s", lockPath, strerror(errno));
        return NO;
    }
    while (flock(lock, LOCK_EX) < 0) {
        if (errno != EINTR) {
            NSLog(@"Cannot lock %@: %s", lockPath, strerror(errno));
            close(lock);
            return NO;
        }
    }
    if (serviceAvailable()) {
        close(lock);
        return YES;
    }
    child = startService(lock, [logPath cString]);
    if (child < 0) {
        NSLog(@"Cannot start the DR2 runtime service: %s", strerror(errno));
        close(lock);
        return NO;
    }
    for (poll = 0; poll < ServicePollLimit; poll++) {
        struct timeval delay = {0, ServicePollMicroseconds};
        if (serviceAvailable()) {
            ready = YES;
            break;
        }
        if (wait4(child, &status, WNOHANG, NULL) == child &&
            (!WIFEXITED(status) || WEXITSTATUS(status)))
            break;
        select(0, NULL, NULL, NULL, &delay);
    }
    close(lock);
    if (!ready)
        NSLog(@"The DR2 runtime service did not start; see %@.", logPath);
    return ready;
}

@interface DR2RuntimeApplication : NSObject
- (void)reopenRuntimeApplication;
@end

static NSConnection *applicationConnection;

@implementation DR2RuntimeApplication
+ (void)load {
    NSAutoreleasePool *pool;
    NSString *name;
    id running;
    if (!objc_getClass("NSApplication"))
        return;
    pool = [[NSAutoreleasePool alloc] init];
    if (!ensureService()) {
        [pool release];
        exit(1);
    }
    name = [@"DR2Runtime.application."
        stringByAppendingString:[[NSProcessInfo processInfo] processName]];
    running = [NSConnection rootProxyForConnectionWithRegisteredName:name host:nil];
    if (running) {
        [running reopenRuntimeApplication];
        exit(0);
    }
    applicationConnection = [[NSConnection connectionWithReceivePort:[NSPort port]
                                                            sendPort:nil] retain];
    [applicationConnection setRootObject:[[[self alloc] init] autorelease]];
    if (![applicationConnection registerName:name]) {
        running = [NSConnection rootProxyForConnectionWithRegisteredName:name host:nil];
        if (running) {
            [running reopenRuntimeApplication];
            exit(0);
        }
        NSLog(@"Cannot register the runtime application: %@", name);
        exit(1);
    }
    [pool release];
}
- (void)reopenRuntimeApplication {
    NSApplication *application = [objc_getClass("NSApplication") sharedApplication];
    [application unhide:nil];
    [application activateIgnoringOtherApps:YES];
}
@end
