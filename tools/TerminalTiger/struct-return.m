/* i386 structure-return ABI boundary: Tiger stack pointer <-> OPENSTEP EBX. */
#import <AppKit/AppKit.h>
#import <objc/objc-class.h>
#include <stdlib.h>
#include <string.h>

unsigned TigerMethodArgumentSize(id object, SEL selector) {
    Method method;
    const char *types;
    unsigned size, align, count;
    if (!object)
        return 8;
    method = class_getInstanceMethod(*(Class *)(void *)object, selector);
    if (!method)
        [NSException raise:NSInvalidArgumentException
                    format:@"Unknown struct-return selector %s", sel_getName(selector)];
    types = NSGetSizeAndAlignment(method->method_types, &size, &align);
    count = atoi(types);
    if (count < 8 || count > 1024)
        [NSException raise:NSInvalidArgumentException
                    format:@"Invalid method argument size: %u", count];
    return count;
}

asm(".text\n.align 2\n.globl _objc_msgSend_stret\n"
    "_objc_msgSend_stret:\n"
    "pushl %ebp\nmovl %esp,%ebp\npushl %ebx\npushl %esi\npushl %edi\n"
    "pushl 16(%ebp)\npushl 12(%ebp)\ncall _TigerMethodArgumentSize\naddl $8,%esp\n"
    "movl %eax,%ecx\naddl $15,%eax\nandl $-16,%eax\nsubl %eax,%esp\n"
    "movl %esp,%edi\nleal 12(%ebp),%esi\ncld\nrep\nmovsb\n"
    "movl 8(%ebp),%ebx\ncall _objc_msgSend\nmovl 8(%ebp),%eax\n"
    "leal -12(%ebp),%esp\npopl %edi\npopl %esi\npopl %ebx\nleave\nret $4\n"
    ".align 2\n.globl _TigerNativeToStackStruct\n"
    "_TigerNativeToStackStruct:\n"
    "pushl %ebp\nmovl %esp,%ebp\npushl %ebx\npushl %esi\npushl %edi\npushl %edx\n"
    "movl %ecx,%eax\naddl $19,%eax\nandl $-16,%eax\nsubl %eax,%esp\n"
    "movl %ebx,(%esp)\nleal 8(%ebp),%esi\nleal 4(%esp),%edi\ncld\nrep\nmovsb\n"
    "call *-16(%ebp)\nleal -12(%ebp),%esp\npopl %edi\npopl %esi\npopl %ebx\nleave\nret\n");

extern void TigerNativeToStackStruct(void);
/* Only large structs use a hidden result. Eight-byte NSRange/NSSize use EDX:EAX. */
void TigerWrapStructMethod(Class cls, SEL selector) {
    Method method = class_getInstanceMethod(cls, selector);
    unsigned size, align, args;
    unsigned char *code;
    if (!method || method->method_types[0] != '{')
        return;
    args = atoi(NSGetSizeAndAlignment(method->method_types, &size, &align));
    if (size <= 8)
        return;
    code = malloc(15);
    code[0] = 0xba;
    memcpy(code + 1, &method->method_imp, 4);
    code[5] = 0xb9;
    memcpy(code + 6, &args, 4);
    code[10] = 0xe9;
    *(int *)(code + 11) = (char *)TigerNativeToStackStruct - (char *)(code + 15);
    method->method_imp = (IMP)code;
}
void TigerInitializeStructReturns(void) {
    TigerWrapStructMethod(NSClassFromString(@"TermSubview"),
                          sel_getUid("firstRectForCharacterRange:"));
    TigerWrapStructMethod(NSClassFromString(@"TermFakeScrollView"), sel_getUid("_taxRectHelper"));
    TigerWrapStructMethod(NSClassFromString(@"TermFakeScrollView"),
                          sel_getUid("_taxRectHelperForView:"));
}

void TigerWriteUnionRect(NSRect *out, NSRect a, NSRect b) {
    *out = NSUnionRect(a, b);
}
void TigerWriteOffsetRect(NSRect *out, NSRect rect, float x, float y) {
    *out = NSOffsetRect(rect, x, y);
}
asm(".text\n.align 2\n.globl _TigerNSUnionRect\n_TigerNSUnionRect:\n"
    "pushl %ebp\nmovl %esp,%ebp\nsubl $36,%esp\npushl %esi\npushl %edi\n"
    "leal 8(%ebp),%esi\nleal -36(%ebp),%edi\nmovl $9,%ecx\ncld\nrep\nmovsl\n"
    "popl %edi\npopl %esi\ncall _TigerWriteUnionRect\nmovl 8(%ebp),%eax\nleave\nret $4\n"
    ".align 2\n.globl _TigerNSOffsetRect\n_TigerNSOffsetRect:\n"
    "pushl %ebp\nmovl %esp,%ebp\nsubl $28,%esp\npushl %esi\npushl %edi\n"
    "leal 8(%ebp),%esi\nleal -28(%ebp),%edi\nmovl $7,%ecx\ncld\nrep\nmovsl\n"
    "popl %edi\npopl %esi\ncall _TigerWriteOffsetRect\nmovl 8(%ebp),%eax\nleave\nret $4\n");
