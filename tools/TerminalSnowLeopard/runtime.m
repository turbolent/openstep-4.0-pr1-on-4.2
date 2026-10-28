/* Objective-C ABI additions used by the Snow Leopard i386 compiler. */
#import <objc/objc-class.h>
#import <objc/objc-runtime.h>
#include <setjmp.h>

/* OPENSTEP callers align stacks to four bytes. Snow Leopard methods spill
 * SSE registers to sixteen-byte-aligned stack slots. Align every entry from
 * the native frameworks, preserving integer, x87, and small-struct returns. */
asm(".text\n.align 2\n.globl _SnowNativeToAlignedMethod\n_SnowNativeToAlignedMethod:\n"
    "pushl %ebp\nmovl %esp,%ebp\npushl %ebx\npushl %esi\npushl %edi\npushl %edx\n"
    "subl %ecx,%esp\nandl $-16,%esp\nmovl %esp,%edi\nleal 8(%ebp),%esi\ncld\nrep\nmovsb\n"
    "call *-16(%ebp)\nleal -12(%ebp),%esp\npopl %edi\npopl %esi\npopl %ebx\nleave\nret\n");
extern void SnowNativeToAlignedMethod(void);
asm(".text\n.align 2\n.globl _SnowNativeToAlignedStruct\n_SnowNativeToAlignedStruct:\n"
    "pushl %ebp\nmovl %esp,%ebp\npushl %ebx\npushl %esi\npushl %edi\npushl %edx\n"
    "subl %ecx,%esp\nsubl $4,%esp\nandl $-16,%esp\nmovl %ebx,(%esp)\n"
    "leal 4(%esp),%edi\nleal 8(%ebp),%esi\ncld\nrep\nmovsb\n"
    "call *-16(%ebp)\nleal -12(%ebp),%esp\npopl %edi\npopl %esi\npopl %ebx\nleave\nret\n");
extern void SnowNativeToAlignedStruct(void);
void SnowWrapMethod(Class cls, SEL selector) {
    Method method = class_getInstanceMethod(cls, selector);
    unsigned size, align, args;
    unsigned char *code;
    void (*bridge)(void) = SnowNativeToAlignedMethod;
    if (!method || (unsigned)method->method_imp < 0x2000 || (unsigned)method->method_imp >= 0x7a000)
        return;
    args = atoi(NSGetSizeAndAlignment(method->method_types, &size, &align));
    if (method->method_types[0] == '{' && size > 8)
        bridge = SnowNativeToAlignedStruct;
    if (args < 8 || args > 2048)
        [NSException raise:NSInternalInconsistencyException format:@"Invalid method argument size"];
    code = malloc(15);
    if (!code)
        [NSException raise:NSMallocException format:@"Cannot allocate method bridge"];
    code[0] = 0xba;
    memcpy(code + 1, &method->method_imp, 4);
    code[5] = 0xb9;
    memcpy(code + 6, &args, 4);
    code[10] = 0xe9;
    *(int *)(code + 11) = (char *)bridge - (char *)(code + 15);
    method->method_imp = (IMP)code;
}

@interface NSObject (SnowCollectionCopy)
- (id)snowCopy;
- (id)snowMutableCopy;
- (id)snowCopyWithZone:(NSZone *)zone;
- (id)snowMutableCopyWithZone:(NSZone *)zone;
@end

/* Native libc's crt0 aliases are supplied by the compatibility entry point. */
int _NXArgc;
char **_NXArgv;
char **_environ;

static NSRecursiveLock *snowRuntimeLock;
void SnowInitializeRuntime(void) {
    snowRuntimeLock = [[NSRecursiveLock alloc] init];
}
id objc_getProperty(id object, SEL selector, int offset, BOOL atomic) {
    id value;
    if (atomic)
        [snowRuntimeLock lock];
    value = *(id *)((char *)object + offset);
    if (atomic)
        value = [[value retain] autorelease];
    if (atomic)
        [snowRuntimeLock unlock];
    return value;
}
void objc_setProperty(id object, SEL selector, int offset, id value, BOOL atomic,
                      signed char copy) {
    id previous;
    if (copy == 1)
        value = [value snowCopy];
    else if (copy == 2)
        value = [value snowMutableCopy];
    else
        [value retain];
    if (atomic)
        [snowRuntimeLock lock];
    previous = *(id *)((char *)object + offset);
    *(id *)((char *)object + offset) = value;
    if (atomic)
        [snowRuntimeLock unlock];
    [previous release];
}
void objc_copyStruct(void *destination, const void *source, int size, BOOL atomic, BOOL strong) {
    if (atomic)
        [snowRuntimeLock lock];
    memmove(destination, source, size);
    if (atomic)
        [snowRuntimeLock unlock];
}
int objc_sync_enter(id object) {
    if (object)
        [snowRuntimeLock lock];
    return 0;
}
int objc_sync_exit(id object) {
    if (object)
        [snowRuntimeLock unlock];
    return 0;
}
void objc_enumerationMutation(id object) {
    [NSException raise:NSInternalInconsistencyException
                format:@"Collection mutated during enumeration: %@", object];
}

/* OPENSTEP's sigcontext is larger than Darwin's compiler-owned exception
 * buffer. Keep native handlers separately and tail-call its setjmp. */
typedef struct SnowExceptionFrame {
    void *foreign;
    NSHandler native;
    struct SnowExceptionFrame *next;
} SnowExceptionFrame;
@interface SnowExceptionStack : NSObject {
  @public
    SnowExceptionFrame *frames;
}
@end
@implementation SnowExceptionStack
- (void)dealloc {
    while (frames) {
        SnowExceptionFrame *next = frames->next;
        free(frames);
        frames = next;
    }
    [super dealloc];
}
@end
static SnowExceptionStack *snowExceptionStack(void) {
    NSMutableDictionary *dictionary = [[NSThread currentThread] threadDictionary];
    SnowExceptionStack *stack = [dictionary objectForKey:@"SnowExceptionStack"];
    if (!stack) {
        stack = [[[SnowExceptionStack alloc] init] autorelease];
        [dictionary setObject:stack forKey:@"SnowExceptionStack"];
    }
    return stack;
}
static SnowExceptionFrame *snowExceptionFrame(void *foreign) {
    SnowExceptionFrame *frame = snowExceptionStack()->frames;
    while (frame && frame->foreign != foreign)
        frame = frame->next;
    if (!frame)
        abort();
    return frame;
}
void objc_exception_try_enter(void *foreign) {
    SnowExceptionStack *stack = snowExceptionStack();
    SnowExceptionFrame *frame = calloc(1, sizeof(*frame));
    frame->foreign = foreign;
    frame->next = stack->frames;
    stack->frames = frame;
    _NSAddHandler(&frame->native);
}
void *SnowExceptionJumpBuffer(void *foreign) {
    return &snowExceptionFrame(foreign)->native._state;
}
void objc_exception_try_exit(void *foreign) {
    SnowExceptionStack *stack = snowExceptionStack();
    SnowExceptionFrame **link = &stack->frames, *frame;
    while (*link && (*link)->foreign != foreign)
        link = &(*link)->next;
    if (!*link)
        abort();
    frame = *link;
    _NSRemoveHandler(&frame->native);
    *link = frame->next;
    free(frame);
}
id objc_exception_extract(void *foreign) {
    SnowExceptionStack *stack = snowExceptionStack();
    SnowExceptionFrame **link = &stack->frames, *frame;
    id exception;
    while (*link && (*link)->foreign != foreign)
        link = &(*link)->next;
    if (!*link)
        abort();
    frame = *link;
    exception = _NSExceptionObjectFromHandler(&frame->native);
    *link = frame->next;
    free(frame);
    return exception;
}
int objc_exception_match(Class cls, id exception) {
    return [exception isKindOfClass:cls];
}
void objc_exception_throw(id exception) {
    [exception raise];
    abort();
}
unsigned SnowSuperArgumentSize(struct objc_super *super, SEL selector) {
    Method method = class_getInstanceMethod(super->class, selector);
    unsigned size, alignment;
    if (!method)
        [NSException raise:NSInvalidArgumentException
                    format:@"Unknown superclass selector %s", sel_getName(selector)];
    return atoi(NSGetSizeAndAlignment(method->method_types, &size, &alignment));
}
asm(".text\n.align 2\n.globl _Snow_setjmp\n_Snow_setjmp:\n"
    "pushl 4(%esp)\ncall _SnowExceptionJumpBuffer\naddl $4,%esp\nmovl %eax,4(%esp)\njmp __setjmp\n"
    ".globl _objc_msgSend_fpret\n_objc_msgSend_fpret:\njmp _objc_msgSend\n"
    ".globl _objc_msgSendSuper_stret\n_objc_msgSendSuper_stret:\n"
    "pushl %ebp\nmovl %esp,%ebp\npushl %ebx\npushl %esi\npushl %edi\n"
    "pushl 16(%ebp)\npushl 12(%ebp)\ncall _SnowSuperArgumentSize\naddl $8,%esp\n"
    "movl %eax,%ecx\naddl $15,%eax\nandl $-16,%eax\nsubl %eax,%esp\n"
    "movl %esp,%edi\nleal 12(%ebp),%esi\ncld\nrep\nmovsb\n"
    "movl 8(%ebp),%ebx\ncall _objc_msgSendSuper\nmovl 8(%ebp),%eax\n"
    "leal -12(%ebp),%esp\npopl %edi\npopl %esi\npopl %ebx\nleave\nret $4\n");

typedef struct {
    unsigned state;
    id *itemsPtr;
    unsigned *mutationsPtr;
    unsigned extra[5];
} SnowEnumerationState;
@implementation NSArray (SnowEnumeration)
- (unsigned)countByEnumeratingWithState:(SnowEnumerationState *)state
                                objects:(id *)objects
                                  count:(unsigned)capacity {
    unsigned count = [self count], used = 0;
    state->itemsPtr = objects;
    state->mutationsPtr = &state->extra[0];
    while (used < capacity && state->state < count)
        objects[used++] = [self objectAtIndex:state->state++];
    return used;
}
@end
static unsigned snowEnumerate(id collection, SnowEnumerationState *state, id *objects,
                              unsigned capacity) {
    NSEnumerator *enumerator;
    id value;
    unsigned used = 0;
    if (!state->state) {
        enumerator = [collection isKindOfClass:[NSDictionary class]]
                         ? [collection keyEnumerator]
                         : [collection objectEnumerator];
        state->extra[1] = (unsigned)enumerator;
        state->state = 1;
    }
    enumerator = (id)state->extra[1];
    state->itemsPtr = objects;
    state->mutationsPtr = &state->extra[0];
    while (used < capacity && (value = [enumerator nextObject]))
        objects[used++] = value;
    return used;
}
@implementation NSDictionary (SnowEnumeration)
- (unsigned)countByEnumeratingWithState:(SnowEnumerationState *)state
                                objects:(id *)objects
                                  count:(unsigned)capacity {
    return snowEnumerate(self, state, objects, capacity);
}
@end
@implementation NSSet (SnowEnumeration)
- (unsigned)countByEnumeratingWithState:(SnowEnumerationState *)state
                                objects:(id *)objects
                                  count:(unsigned)capacity {
    return snowEnumerate(self, state, objects, capacity);
}
@end
@implementation NSEnumerator (SnowEnumeration)
- (unsigned)countByEnumeratingWithState:(SnowEnumerationState *)state
                                objects:(id *)objects
                                  count:(unsigned)capacity {
    unsigned used = 0;
    id value;
    state->itemsPtr = objects;
    state->mutationsPtr = &state->extra[0];
    state->state = 1;
    while (used < capacity && (value = [self nextObject]))
        objects[used++] = value;
    return used;
}
@end
