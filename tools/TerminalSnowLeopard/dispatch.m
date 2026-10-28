/* Deliver background shell I/O notifications on the AppKit thread. */
@interface SnowMainThreadCall : NSObject {
  @public
    id target, argument;
    SEL selector;
    NSConditionLock *completion;
    NSException *exception;
}
@end

/* NSThread gained initWithTarget:/start after OPENSTEP. A managed handle
 * starts a native detached thread and keeps its target alive until exit. */
@interface SNThread : NSObject {
    id snowTarget, snowArgument;
    SEL snowSelector;
    NSLock *snowStateLock;
    NSString *snowName;
    BOOL snowStarted, snowFinished, snowCancelled;
}
- initWithTarget:(id)target selector:(SEL)selector object:(id)argument;
- (void)start;
- (void)run:(id)unused;
- (BOOL)isCancelled;
+ (id)currentThread;
@end
@implementation SNThread
+ (id)currentThread {
    NSThread *native = [NSThread currentThread];
    id handle =
        [[[native threadDictionary] objectForKey:@"SnowThreadHandle"] nonretainedObjectValue];
    return handle ? handle : native;
}
+ (BOOL)isMultiThreaded {
    return [NSThread isMultiThreaded];
}
+ (void)detachNewThreadSelector:(SEL)selector toTarget:(id)target withObject:(id)argument {
    id thread = [[self alloc] initWithTarget:target selector:selector object:argument];
    [thread start];
    [thread release];
}
- initWithTarget:(id)target selector:(SEL)selector object:(id)argument {
    self = [super init];
    snowTarget = [target retain];
    snowArgument = [argument retain];
    snowSelector = selector;
    snowStateLock = [[NSLock alloc] init];
    return self;
}
- (void)start {
    [snowStateLock lock];
    if (snowStarted) {
        [snowStateLock unlock];
        [NSException raise:NSInternalInconsistencyException format:@"Thread already started"];
    }
    snowStarted = YES;
    [self retain];
    [snowStateLock unlock];
    [NSThread detachNewThreadSelector:@selector(run:) toTarget:self withObject:nil];
}
- (void)run:(id)unused {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSMutableDictionary *dictionary = [[NSThread currentThread] threadDictionary];
    [dictionary setObject:[NSValue valueWithNonretainedObject:self] forKey:@"SnowThreadHandle"];
    NS_DURING
        if (![self isCancelled])
            [snowTarget performSelector:snowSelector withObject:snowArgument];
    NS_HANDLER
        NSLog(@"Background thread failed: %@", localException);
    NS_ENDHANDLER
    [dictionary removeObjectForKey:@"SnowThreadHandle"];
    [snowStateLock lock];
    snowFinished = YES;
    [snowStateLock unlock];
    [snowTarget release];
    snowTarget = nil;
    [snowArgument release];
    snowArgument = nil;
    [pool release];
    [self release];
}
- (BOOL)isExecuting {
    BOOL value;
    [snowStateLock lock];
    value = snowStarted && !snowFinished;
    [snowStateLock unlock];
    return value;
}
- (BOOL)isFinished {
    BOOL value;
    [snowStateLock lock];
    value = snowFinished;
    [snowStateLock unlock];
    return value;
}
- (BOOL)isCancelled {
    BOOL value;
    [snowStateLock lock];
    value = snowCancelled;
    [snowStateLock unlock];
    return value;
}
- (void)cancel {
    [snowStateLock lock];
    snowCancelled = YES;
    [snowStateLock unlock];
}
- (void)setName:(NSString *)name {
    [snowStateLock lock];
    [name retain];
    [snowName release];
    snowName = name;
    [snowStateLock unlock];
}
- (NSString *)name {
    NSString *value;
    [snowStateLock lock];
    value = [[snowName retain] autorelease];
    [snowStateLock unlock];
    return value;
}
- (BOOL)isMainThread {
    return NO;
}
- (void)dealloc {
    [snowTarget release];
    [snowArgument release];
    [snowStateLock release];
    [snowName release];
    [super dealloc];
}
@end
@implementation SnowMainThreadCall
- (void)dealloc {
    [target release];
    [argument release];
    [completion release];
    [exception release];
    [super dealloc];
}
@end
static NSThread *snowMainThread;
static NSLock *snowDispatchLock;
static NSMutableArray *snowDispatchQueue;
@interface SnowMainThreadPump : NSObject
+ (void)drain:(id)sender;
@end
@implementation SnowMainThreadPump
+ (void)drain:(id)sender {
    NSArray *calls;
    unsigned i;
    [snowDispatchLock lock];
    calls = [[NSArray alloc] initWithArray:snowDispatchQueue];
    [snowDispatchQueue removeAllObjects];
    [snowDispatchLock unlock];
    for (i = 0; i < [calls count]; i++) {
        SnowMainThreadCall *call = [calls objectAtIndex:i];
        NS_DURING
            [call->target performSelector:call->selector withObject:call->argument];
        NS_HANDLER
            call->exception = [localException retain];
        NS_ENDHANDLER
        if (call->completion) {
            [call->completion lock];
            [call->completion unlockWithCondition:1];
        } else if (call->exception)
            NSLog(@"Main thread callback failed: %@", call->exception);
    }
    [calls release];
}
@end
static void SnowInitializeMainThreadDispatch(void) {
    NSTimer *timer;
    snowMainThread = [[NSThread currentThread] retain];
    snowDispatchLock = [[NSLock alloc] init];
    snowDispatchQueue = [[NSMutableArray alloc] init];
    timer = [NSTimer timerWithTimeInterval:0.01
                                    target:[SnowMainThreadPump class]
                                  selector:@selector(drain:)
                                  userInfo:nil
                                   repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSEventTrackingRunLoopMode];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSModalPanelRunLoopMode];
}
@implementation NSObject (SnowMainThreadDispatch)
- (void)performSelectorOnMainThread:(SEL)selector withObject:(id)argument waitUntilDone:(BOOL)wait {
    SnowMainThreadCall *call;
    if ([NSThread currentThread] == snowMainThread) {
        [self performSelector:selector withObject:argument];
        return;
    }
    call = [[SnowMainThreadCall alloc] init];
    call->target = [self retain];
    call->argument = [argument retain];
    call->selector = selector;
    if (wait)
        call->completion = [[NSConditionLock alloc] initWithCondition:0];
    [snowDispatchLock lock];
    [snowDispatchQueue addObject:call];
    [snowDispatchLock unlock];
    if (wait) {
        [call->completion lockWhenCondition:1];
        [call->completion unlock];
        if (call->exception) {
            NSException *exception = [[call->exception retain] autorelease];
            [call release];
            [exception raise];
        }
    }
    [call release];
}
@end
