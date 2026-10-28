#include <assert.h>
static unsigned short *snowTestRegexString(const char *text) {
    static unsigned short values[4][512];
    static unsigned slot;
    unsigned i;
    unsigned short *result = values[(slot++) % 4];
    for (i = 0; text[i]; i++)
        result[i] = (unsigned char)text[i];
    result[i] = 0;
    return result;
}
int main(void) {
    int status = 0;
    SnowRegex *regex;
    unsigned short unicode[] = {0x03b1, 0x03b2, ' ', 0xd83d, 0xde00, 0};
    regex = uregex_open(snowTestRegexString("(hello)\\s+(world)?"), -1, 2, NULL, &status);
    assert(regex && !status);
    uregex_setText(regex, snowTestRegexString("HELLO world; hello "), -1, &status);
    assert(uregex_find(regex, 0, &status) && uregex_start(regex, 1, &status) == 0 &&
           uregex_end(regex, 2, &status) == 11);
    assert(uregex_find(regex, -1, &status) && uregex_start(regex, 2, &status) == -1);
    assert(!uregex_find(regex, -1, &status) && !status);
    uregex_close(regex);
    regex = uregex_open(snowTestRegexString("\\p{L}+|."), -1, 0, NULL, &status);
    assert(regex && !status);
    uregex_setText(regex, unicode, 5, &status);
    assert(uregex_find(regex, 0, &status) && uregex_end(regex, 0, &status) == 2);
    assert(uregex_find(regex, 3, &status) && uregex_end(regex, 0, &status) == 5);
    uregex_close(regex);
    regex = uregex_open(snowTestRegexString("(?=.)"), -1, 0, NULL, &status);
    assert(regex && !status);
    uregex_setText(regex, unicode, 5, &status);
    assert(uregex_find(regex, 3, &status) && !uregex_find(regex, -1, &status));
    uregex_close(regex);
    regex = uregex_open(snowTestRegexString("a+b.[x]"), -1, 16, NULL, &status);
    assert(regex && !status);
    uregex_setText(regex, snowTestRegexString("a+b.[x]"), -1, &status);
    assert(uregex_find(regex, 0, &status) && uregex_end(regex, 0, &status) == 7);
    uregex_close(regex);
    assert(!uregex_open(snowTestRegexString("["), -1, 0, NULL, &status) && status > 0);
    puts(
        "UTF-16 search, groups, case folding, Unicode properties, literals, empty matches, and invalid patterns passed");
    return 0;
}
