/* Non-GC Blocks ABI ownership and synchronous Foundation enumeration.
 * Stock callbacks require sixteen-byte stack alignment. */
struct SnowBlockDescriptor {
    unsigned reserved, size;
    void (*copy)(void *, const void *);
    void (*dispose)(void *);
};
typedef struct {
    void *isa;
    unsigned flags, reserved;
    void (*invoke)(void);
    struct SnowBlockDescriptor *descriptor;
} SnowBlock;
typedef struct SnowByref {
    void *isa;
    struct SnowByref *forwarding;
    unsigned flags, size;
    void (*keep)(void *, const void *);
    void (*destroy)(void *);
} SnowByref;
enum {
    SNBlockHeap = 1 << 24,
    SNBlockHelpers = 1 << 25,
    SNBlockGlobal = 1 << 28,
    SNBlockCount = 0xffff
};
void *_NSConcreteStackBlock[32], *_NSConcreteMallocBlock[32];
extern unsigned SnowCallAligned(void (*function)(void), const void *arguments, unsigned bytes);
asm(".text\n.align 2\n.globl _SnowCallAligned\n_SnowCallAligned:\n"
    "pushl %ebp\nmovl %esp,%ebp\npushl %esi\npushl %edi\n"
    "movl 16(%ebp),%ecx\nsubl %ecx,%esp\nandl $-16,%esp\n"
    "movl 12(%ebp),%esi\nmovl %esp,%edi\ncld\nrep\nmovsb\ncall *8(%ebp)\n"
    "leal -8(%ebp),%esp\npopl %edi\npopl %esi\nleave\nret\n");
static unsigned snowBlockIncrement(unsigned *flags) {
    unsigned value;
    [snowRuntimeLock lock];
    if ((*flags & SNBlockCount) != SNBlockCount)
        ++*flags;
    value = *flags & SNBlockCount;
    [snowRuntimeLock unlock];
    return value;
}
static unsigned snowBlockDecrement(unsigned *flags) {
    unsigned value;
    [snowRuntimeLock lock];
    if ((*flags & SNBlockCount) != SNBlockCount && (*flags & SNBlockCount))
        --*flags;
    value = *flags & SNBlockCount;
    [snowRuntimeLock unlock];
    return value;
}
void *_Block_copy(const void *value) {
    const SnowBlock *source = value;
    SnowBlock *copy;
    void *args[2];
    if (!source)
        return NULL;
    if (source->flags & SNBlockGlobal)
        return (void *)value;
    if (source->flags & SNBlockHeap) {
        snowBlockIncrement((unsigned *)&source->flags);
        return (void *)value;
    }
    if (!source->descriptor || source->descriptor->size < sizeof(SnowBlock))
        return NULL;
    copy = malloc(source->descriptor->size);
    if (!copy)
        return NULL;
    memcpy(copy, source, source->descriptor->size);
    copy->isa = _NSConcreteMallocBlock;
    copy->flags = (copy->flags & ~SNBlockCount) | SNBlockHeap | 1;
    if (copy->flags & SNBlockHelpers) {
        args[0] = copy;
        args[1] = (void *)source;
        SnowCallAligned((void (*)(void))copy->descriptor->copy, args, 8);
    }
    return copy;
}
void _Block_release(const void *value) {
    SnowBlock *block = (SnowBlock *)value;
    if (!block || !(block->flags & SNBlockHeap) || snowBlockDecrement(&block->flags))
        return;
    if (block->flags & SNBlockHelpers)
        SnowCallAligned((void (*)(void))block->descriptor->dispose, &block, 4);
    free(block);
}
void _Block_object_assign(void *destination, const void *object, int flags) {
    void *result = (void *)object;
    if (flags & 128) { /* __block object ownership belongs to its enclosing scope. */
    } else if ((flags & 15) == 8) {
        SnowByref *source = (SnowByref *)object, *copy;
        if (source) {
            [snowRuntimeLock lock];
            source = source->forwarding;
            if (source->flags & SNBlockHeap) {
                snowBlockIncrement(&source->flags);
                result = source;
            } else {
                copy = malloc(source->size);
                if (!copy) {
                    [snowRuntimeLock unlock];
                    [NSException raise:NSMallocException format:@"Cannot copy block capture"];
                }
                memcpy(copy, source, source->size);
                copy->forwarding = copy;
                copy->flags = (copy->flags & ~SNBlockCount) | SNBlockHeap | 2;
                source->forwarding = copy;
                if (copy->flags & SNBlockHelpers) {
                    void *args[2];
                    args[0] = copy;
                    args[1] = source;
                    SnowCallAligned((void (*)(void))copy->keep, args, 8);
                }
                result = copy;
            }
            [snowRuntimeLock unlock];
        }
    } else if ((flags & 7) == 7)
        result = _Block_copy(object);
    else if ((flags & 7) == 3 && !(flags & 16))
        [(id)object retain];
    *(void **)destination = result;
}
void _Block_object_dispose(const void *object, int flags) {
    if (flags & 128)
        return;
    if ((flags & 15) == 8) {
        SnowByref *byref = (SnowByref *)object;
        if (!byref)
            return;
        byref = byref->forwarding;
        if (!(byref->flags & SNBlockHeap) || snowBlockDecrement(&byref->flags))
            return;
        if (byref->flags & SNBlockHelpers)
            SnowCallAligned((void (*)(void))byref->destroy, &byref, 4);
        free(byref);
    } else if ((flags & 7) == 7)
        _Block_release(object);
    else if ((flags & 7) == 3 && !(flags & 16))
        [(id)object release];
}
@implementation NSArray (SnowBlockEnumeration)
- (void)enumerateObjectsUsingBlock:(SnowBlock *)block {
    unsigned i, count = [self count];
    BOOL stop = NO;
    if (!block)
        [NSException raise:NSInvalidArgumentException format:@"Missing enumeration block"];
    for (i = 0; i < count && !stop; i++) {
        void *args[4];
        args[0] = block;
        args[1] = [self objectAtIndex:i];
        args[2] = (void *)i;
        args[3] = &stop;
        SnowCallAligned(block->invoke, args, sizeof(args));
        if ([self count] != count)
            [NSException raise:NSInternalInconsistencyException
                        format:@"Array changed during enumeration"];
    }
}
@end
