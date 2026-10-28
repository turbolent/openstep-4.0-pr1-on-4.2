#include <assert.h>
static unsigned snowTestVisits;
static void snowTestVisit(void *block, id object, unsigned index, BOOL *stop) {
    assert([object intValue] == (int)index + 1);
    snowTestVisits++;
    if (index == 1)
        *stop = YES;
}
int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    unsigned short location[260], colors[8] = {0, 0, 0, 123, 65535, 65535, 65535, 456};
    void *rgb, *lab, *forward, *reverse, *frames[32];
    int count, status = 0;
    unsigned short delimiter;
    SnowStringTokenizer *tokenizer;
    unsigned long long range;
    SnowBlock block, *copy;
    struct SnowBlockDescriptor descriptor = {0, sizeof(SnowBlock), NULL, NULL};
    snowRuntimeLock = [[NSRecursiveLock alloc] init];
    tokenizer = CFStringTokenizerCreate(NULL, @"one can't 3.25", NSMakeRange(0, 14), 4, nil);
    assert(CFStringTokenizerGoToTokenAtIndex(tokenizer, 5) == 1);
    range = CFStringTokenizerGetCurrentTokenRange(tokenizer);
    assert((unsigned)range == 4 && (unsigned)(range >> 32) == 5);
    CFStringTokenizerSetString(tokenizer, @"one can't 3.25", NSMakeRange(10, 4));
    assert(CFStringTokenizerGoToTokenAtIndex(tokenizer, 12) == 1);
    range = CFStringTokenizerGetCurrentTokenRange(tokenizer);
    assert((unsigned)range == 10 && (unsigned)(range >> 32) == 4);
    assert(!CFStringTokenizerGoToTokenAtIndex(tokenizer, 14));
    assert(CFStringTokenizerGetCurrentTokenRange(tokenizer) == 0xffffffffU);
    [tokenizer release];
    assert(ulocdata_getDelimiter(ulocdata_open("en_US", &status), 0, &delimiter, 1, &status) == 1);
    assert(status == -124 && delimiter == 0x201c);
    memset(&block, 0, sizeof(block));
    block.isa = _NSConcreteStackBlock;
    block.descriptor = &descriptor;
    block.invoke = (void (*)(void))snowTestVisit;
    [[NSArray arrayWithObjects:@"1", @"2", @"3", nil] enumerateObjectsUsingBlock:&block];
    assert(snowTestVisits == 2);
    copy = _Block_copy(&block);
    assert(copy != &block && (copy->flags & SNBlockHeap));
    assert(_Block_copy(copy) == copy && (copy->flags & SNBlockCount) == 2);
    _Block_release(copy);
    _Block_release(copy);
    {
        SnowByref original, *capture, *other;
        memset(&original, 0, sizeof(original));
        original.forwarding = &original;
        original.size = sizeof(original);
        _Block_object_assign(&capture, &original, 8);
        assert(capture != &original && original.forwarding == capture);
        _Block_object_assign(&other, &original, 8);
        assert(other == capture && (capture->flags & SNBlockCount) == 3);
        _Block_object_dispose(other, 8);
        _Block_object_dispose(capture, 8);
        _Block_object_dispose(&original, 8);
    }
    location[0] = 5;
    strcpy((char *)location + 2, "/System/Library/ColorSync/Profiles/sRGB Profile.icc");
    assert(!CMOpenProfile(&rgb, location));
    strcpy((char *)location + 2, "/System/Library/ColorSync/Profiles/Generic Lab Profile.icc");
    assert(!CMOpenProfile(&lab, location));
    assert(!NCWNewColorWorld(&forward, rgb, lab) && !NCWNewColorWorld(&reverse, lab, rgb));
    assert(!CWMatchColors(forward, colors, 2));
    assert(colors[0] == 0 && colors[1] == 32768 && colors[2] == 32768 && colors[3] == 123);
    assert(colors[4] == 65535 && abs(colors[5] - 32768) < 2 && abs(colors[6] - 32768) < 2 &&
           colors[7] == 456);
    assert(!CWMatchColors(reverse, colors, 2));
    assert(colors[0] == 0 && colors[4] > 65530 && colors[5] > 65530 && colors[6] > 65530);
    colors[0] = 65535;
    colors[1] = colors[2] = 0;
    assert(!CWMatchColors(forward, colors, 1));
    assert(fabs(colors[0] * 100 / 65535.0 - 54.29) < 0.1 &&
           fabs(colors[1] / 256.0 - 128 - 80.81) < 0.1 &&
           fabs(colors[2] / 256.0 - 128 - 69.89) < 0.1);
    count = backtrace(frames, 32);
    assert(count > 0);
    {
        char **symbols = backtrace_symbols(frames, count);
        assert(symbols && !strncmp(symbols[0], "0x", 2));
        free(symbols);
    }
    [snowRuntimeLock release];
    [pool release];
    puts(
        "PASS native services: UTF-16 selection, block ownership, color conversion, locale delimiters and stack tracing");
    return 0;
}
