/* Invocation-based undo and redo for the stock profile editors. */
@class NSUndoManager;
@interface SnowUndoProxy : NSProxy {
  @public
    NSUndoManager *manager;
    id receiver;
}
@end
@interface NSUndoManager : NSObject {
    NSMutableArray *snowUndo, *snowRedo, *snowGroup;
    unsigned snowGrouping, snowDisabled, snowLimit;
    unsigned snowUndoMode;
    BOOL snowGroupsByEvent;
    NSString *snowActionName;
}
- (void)recordInvocation:(NSInvocation *)invocation;
- (void)beginUndoGrouping;
- (void)endUndoGrouping;
- (void)removeAllActions;
@end
@implementation SnowUndoProxy
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    return [receiver methodSignatureForSelector:selector];
}
- (void)forwardInvocation:(NSInvocation *)invocation {
    [invocation setTarget:receiver];
    [manager recordInvocation:invocation];
}
@end
@implementation NSUndoManager
- init {
    self = [super init];
    snowUndo = [[NSMutableArray alloc] init];
    snowRedo = [[NSMutableArray alloc] init];
    snowGroupsByEvent = YES;
    return self;
}
- (id)prepareWithInvocationTarget:(id)target {
    SnowUndoProxy *proxy = [[SnowUndoProxy alloc] autorelease];
    proxy->manager = self;
    proxy->receiver = target;
    return proxy;
}
- (void)recordInvocation:(NSInvocation *)invocation {
    BOOL automatic;
    if (snowDisabled)
        return;
    [invocation retainArguments];
    automatic = snowGrouping == 0;
    if (automatic)
        [self beginUndoGrouping];
    [snowGroup addObject:invocation];
    if (!snowUndoMode)
        [snowRedo removeAllObjects];
    if (automatic)
        [self endUndoGrouping];
}
- (void)registerUndoWithTarget:(id)target selector:(SEL)selector object:(id)argument {
    NSInvocation *invocation =
        [NSInvocation invocationWithMethodSignature:[target methodSignatureForSelector:selector]];
    [invocation setTarget:target];
    [invocation setSelector:selector];
    [invocation setArgument:&argument atIndex:2];
    [self recordInvocation:invocation];
}
- (void)beginUndoGrouping {
    if (snowGrouping++ == 0)
        snowGroup = [[NSMutableArray alloc] init];
}
- (void)endUndoGrouping {
    NSMutableArray *stack;
    if (!snowGrouping)
        [NSException raise:NSInternalInconsistencyException format:@"No undo group is open"];
    if (--snowGrouping)
        return;
    stack = snowUndoMode == 1 ? snowRedo : snowUndo;
    if ([snowGroup count])
        [stack addObject:snowGroup];
    [snowGroup release];
    snowGroup = nil;
    if (snowLimit)
        while ([stack count] > snowLimit)
            [stack removeObjectAtIndex:0];
}
- (unsigned)groupingLevel {
    return snowGrouping;
}
- (void)applyStack:(NSMutableArray *)stack mode:(unsigned)mode {
    NSArray *group;
    int i;
    if (snowGrouping)
        [NSException raise:NSInternalInconsistencyException
                    format:@"Cannot undo inside an open group"];
    if (![stack count])
        return;
    group = [[stack lastObject] retain];
    [stack removeLastObject];
    snowUndoMode = mode;
    [self beginUndoGrouping];
    NS_DURING
        for (i = [group count] - 1; i >= 0; i--)
            [[group objectAtIndex:i] invoke];
    NS_HANDLER
        [self endUndoGrouping];
        snowUndoMode = 0;
        [group release];
        [localException raise];
    NS_ENDHANDLER
    [self endUndoGrouping];
    snowUndoMode = 0;
    [group release];
}
- (void)undo {
    [self applyStack:snowUndo mode:1];
}
- (void)undoNestedGroup {
    [self undo];
}
- (void)redo {
    [self applyStack:snowRedo mode:2];
}
- (BOOL)canUndo {
    return [snowUndo count] != 0;
}
- (BOOL)canRedo {
    return [snowRedo count] != 0;
}
- (BOOL)isUndoing {
    return snowUndoMode == 1;
}
- (BOOL)isRedoing {
    return snowUndoMode == 2;
}
- (void)setGroupsByEvent:(BOOL)value {
    snowGroupsByEvent = value;
}
- (BOOL)groupsByEvent {
    return snowGroupsByEvent;
}
- (void)setLevelsOfUndo:(unsigned)value {
    snowLimit = value;
}
- (unsigned)levelsOfUndo {
    return snowLimit;
}
- (void)disableUndoRegistration {
    snowDisabled++;
}
- (void)enableUndoRegistration {
    if (snowDisabled)
        snowDisabled--;
    else
        [NSException raise:NSInternalInconsistencyException
                    format:@"Undo registration is already enabled"];
}
- (BOOL)isUndoRegistrationEnabled {
    return snowDisabled == 0;
}
- (void)removeAllActions {
    [snowUndo removeAllObjects];
    [snowRedo removeAllObjects];
    [snowGroup removeAllObjects];
}
- (void)removeAllActionsWithTarget:(id)target {
    unsigned which;
    NSMutableArray *stacks[3];
    stacks[0] = snowUndo;
    stacks[1] = snowRedo;
    stacks[2] = snowGroup ? [NSMutableArray arrayWithObject:snowGroup] : nil;
    for (which = 0; which < 3; which++) {
        NSMutableArray *stack = stacks[which];
        int i, j;
        for (i = [stack count] - 1; i >= 0; i--) {
            NSMutableArray *group = [stack objectAtIndex:i];
            for (j = [group count] - 1; j >= 0; j--)
                if ([[group objectAtIndex:j] target] == target)
                    [group removeObjectAtIndex:j];
            if (![group count])
                [stack removeObjectAtIndex:i];
        }
    }
}
- (void)setActionName:(NSString *)name {
    [name retain];
    [snowActionName release];
    snowActionName = name;
}
- (NSString *)undoActionName {
    return snowActionName ? snowActionName : @"";
}
- (NSString *)redoActionName {
    return [self undoActionName];
}
- (NSString *)undoMenuItemTitle {
    return [snowActionName length] ? [@"Undo " stringByAppendingString:snowActionName] : @"Undo";
}
- (NSString *)redoMenuItemTitle {
    return [snowActionName length] ? [@"Redo " stringByAppendingString:snowActionName] : @"Redo";
}
- (void)dealloc {
    [snowUndo release];
    [snowRedo release];
    [snowGroup release];
    [snowActionName release];
    [super dealloc];
}
@end

@implementation NSResponder (SnowUndoActions)
- (id)undoManager {
    NSResponder *next = [self nextResponder];
    return [next respondsToSelector:@selector(undoManager)] ? [next undoManager] : nil;
}
- (void)undo:(id)sender {
    [[self undoManager] undo];
}
- (void)redo:(id)sender {
    [[self undoManager] redo];
}
@end
@implementation NSWindow (SnowUndoManager)
- (id)undoManager {
    id delegate = [self delegate], controller;
    if ([delegate respondsToSelector:@selector(windowWillReturnUndoManager:)])
        return [delegate performSelector:@selector(windowWillReturnUndoManager:) withObject:self];
    controller = [self windowController];
    return [controller respondsToSelector:@selector(undoManager)] ? [controller undoManager] : nil;
}
@end
