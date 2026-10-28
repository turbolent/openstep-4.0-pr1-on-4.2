/* Run a native worker and deliver a synchronous callback through the run loop. */
#include <assert.h>
@interface SnowDispatchTest : NSObject {
  @public
    NSThread *mainThread;
    BOOL called;
    id workerThread;
}
- (void)worker:(id)value;
- (void)callback:(id)value;
@end
@implementation SnowDispatchTest
- (void)worker:(id)value {
    assert([SNThread currentThread] == workerThread);
    [self performSelectorOnMainThread:@selector(callback:) withObject:value waitUntilDone:YES];
    [self performSelectorOnMainThread:@selector(threadCallback:)
                           withObject:[SNThread currentThread]
                        waitUntilDone:NO];
}
- (void)threadCallback:(id)value {
    assert(value == workerThread);
}
- (void)callback:(id)value {
    assert([NSThread currentThread] == mainThread);
    assert([value isEqual:@"delivered"]);
    called = YES;
}
@end
int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    SnowDispatchTest *test = [[SnowDispatchTest alloc] init];
    id thread;
    NSDate *deadline;
    SnowInitializeFoundation();
    SnowInitializeFormatting();
    SnowInitializeMainThreadDispatch();
    test->mainThread = [NSThread currentThread];
    thread = [[SNThread alloc] initWithTarget:test selector:@selector(worker:) object:@"delivered"];
    test->workerThread = thread;
    [thread start];
    deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (![thread isFinished] && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    assert([thread isFinished]);
    assert(test->called);
    [SnowMainThreadPump drain:nil];
    [thread release];
    [test release];
    [pool release];
    puts("Native worker and synchronous main-thread dispatch passed");
    return 0;
}
