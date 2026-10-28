/* Exercise the actual bridge assembly at every native stack alignment. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
asm(".text\n.align 2\n.globl _SnowTestInvoke\n_SnowTestInvoke:\n"
    "pushl %ebp\nmovl %esp,%ebp\npushl %ebx\npushl %esi\npushl %edi\n"
    "subl $80,%esp\nandl $-16,%esp\nsubl 12(%ebp),%esp\n"
    "movl $11,(%esp)\nmovl $22,4(%esp)\nmovl $33,8(%esp)\nmovl $44,12(%esp)\nmovl $55,16(%esp)\n"
    "movl 16(%ebp),%ebx\nmovl $0x13579,%esi\nmovl $0x24680,%edi\ncall *8(%ebp)\n"
    "cmpl $1,20(%ebp)\nje 1f\ncmpl $2,20(%ebp)\nje 2f\n"
    "movl %eax,(%ebx)\nmovl %edx,4(%ebx)\njmp 1f\n2: fstpl (%ebx)\n"
    "1: movl $1,%eax\ncmpl 16(%ebp),%ebx\njne 3f\ncmpl $0x13579,%esi\njne 3f\ncmpl $0x24680,%edi\njne 3f\nxorl %eax,%eax\n"
    "3: leal -12(%ebp),%esp\npopl %edi\npopl %esi\npopl %ebx\nleave\nret\n"
    ".globl _SnowTestInteger\n_SnowTestInteger:\n"
    "leal 4(%esp),%ecx\nandl $15,%ecx\njnz 9f\n"
    "movl 4(%esp),%eax\naddl 8(%esp),%eax\naddl 12(%esp),%eax\naddl 16(%esp),%eax\naddl 20(%esp),%eax\nmovl $0x12345678,%edx\nret\n"
    ".globl _SnowTestFloat\n_SnowTestFloat:\n"
    "leal 4(%esp),%ecx\nandl $15,%ecx\njnz 9f\nfldl _SnowTestDouble\nret\n"
    ".globl _SnowTestStruct\n_SnowTestStruct:\n"
    "leal 4(%esp),%ecx\nandl $15,%ecx\njnz 9f\nmovl 4(%esp),%eax\n"
    "movl 8(%esp),%ecx\nmovl %ecx,(%eax)\nmovl 12(%esp),%ecx\nmovl %ecx,4(%eax)\n"
    "movl 16(%esp),%ecx\nmovl %ecx,8(%eax)\nmovl 20(%esp),%ecx\nmovl %ecx,12(%eax)\nret $4\n"
    "9: .byte 0x0f,0x0b\n");
double SnowTestDouble = 3.25;
extern void SnowTestInteger(void), SnowTestFloat(void), SnowTestStruct(void);
extern int SnowTestInvoke(void *function, unsigned phase, void *result, unsigned kind);
static void *bridge(void (*target)(void), void (*entry)(void)) {
    unsigned char *code = malloc(15);
    unsigned arguments = 20;
    assert(code);
    code[0] = 0xba;
    memcpy(code + 1, &target, 4);
    code[5] = 0xb9;
    memcpy(code + 6, &arguments, 4);
    code[10] = 0xe9;
    *(int *)(code + 11) = (char *)entry - (char *)(code + 15);
    return code;
}
int main(void) {
    unsigned phase, result[4];
    double floating;
    void *integer = bridge(SnowTestInteger, SnowNativeToAlignedMethod);
    void *real = bridge(SnowTestFloat, SnowNativeToAlignedMethod);
    void *structure = bridge(SnowTestStruct, SnowNativeToAlignedStruct);
    for (phase = 0; phase < 16; phase += 4) {
        assert(SnowTestInvoke(integer, phase, result, 0) == 0);
        assert(result[0] == 165 && result[1] == 0x12345678);
        assert(SnowTestInvoke(real, phase, &floating, 2) == 0);
        assert(floating == 3.25);
        assert(SnowTestInvoke(structure, phase, result, 1) == 0);
        assert(result[0] == 11 && result[1] == 22 && result[2] == 33 && result[3] == 44);
    }
    free(integer);
    free(real);
    free(structure);
    puts("All four stack alignments, saved registers, scalar, floating and struct returns passed");
    return 0;
}
