/* ICU's search entry points, using PCRE's C89-compatible UTF-16 engine. */
#include "pcre16/pcre.h"
typedef struct {
    pcre16 *pattern;
    unsigned short *text;
    int length, groups, *offsets, next, matched;
} SnowRegex;
typedef struct {
    int line, offset;
    unsigned short before[16], after[16];
} SnowParseError;

SnowRegex *uregex_open(const unsigned short *pattern, int length, unsigned flags,
                       SnowParseError *error, int *status) {
    SnowRegex *result;
    unsigned short *terminated;
    int i, used = 0, offset = 0, options = PCRE_UTF16 | PCRE_UCP;
    const char *message;
    if (!status || *status > 0)
        return NULL;
    if (!pattern || length < -1) {
        *status = 1;
        return NULL;
    }
    if (flags & ~(1 | 2 | 4 | 8 | 16 | 32 | 512)) {
        *status = 16;
        return NULL;
    }
    if (length < 0)
        for (length = 0; pattern[length]; length++)
            ;
    if (length > (INT_MAX / 2 - 1) / 6) {
        *status = 7;
        return NULL;
    }
    terminated = malloc((length * 6 + 1) * sizeof(*terminated));
    if (!terminated) {
        *status = 7;
        return NULL;
    }
    for (i = 0; i < length; i++) {
        unsigned c = pattern[i];
        if (!c) {
            terminated[used++] = '\\';
            terminated[used++] = 'x';
            terminated[used++] = '{';
            terminated[used++] = '0';
            terminated[used++] = '}';
        } else {
            if ((flags & 16) && c < 128 && strchr("\\.^$|?*+()[]{}# ", c))
                terminated[used++] = '\\';
            terminated[used++] = c;
        }
    }
    terminated[used] = 0;
    options |= (flags & 1) ? PCRE_NEWLINE_LF : PCRE_NEWLINE_ANY;
    if (flags & 2)
        options |= PCRE_CASELESS;
    if ((flags & 4) && !(flags & 16))
        options |= PCRE_EXTENDED;
    if (flags & 8)
        options |= PCRE_MULTILINE;
    if (flags & 32)
        options |= PCRE_DOTALL;
    result = calloc(1, sizeof(*result));
    if (!result) {
        free(terminated);
        *status = 7;
        return NULL;
    }
    result->pattern = pcre16_compile(terminated, options, &message, &offset, NULL);
    free(terminated);
    if (!result->pattern) {
        if (error) {
            memset(error, 0, sizeof(*error));
            error->line = 0;
            error->offset = offset;
        }
        free(result);
        *status = 0x10301;
        return NULL;
    }
    pcre16_fullinfo(result->pattern, NULL, PCRE_INFO_CAPTURECOUNT, &result->groups);
    result->groups++;
    result->offsets = malloc(result->groups * 3 * sizeof(int));
    if (!result->offsets) {
        pcre16_free(result->pattern);
        free(result);
        *status = 7;
        return NULL;
    }
    return result;
}
void uregex_close(SnowRegex *expression) {
    if (expression) {
        pcre16_free(expression->pattern);
        free(expression->text);
        free(expression->offsets);
        free(expression);
    }
}
void uregex_setText(SnowRegex *expression, const unsigned short *text, int length, int *status) {
    unsigned short *copy;
    if (!status || *status > 0)
        return;
    if (!expression || !text || length < -1) {
        *status = 1;
        return;
    }
    if (length < 0)
        for (length = 0; text[length]; length++)
            ;
    if (length > INT_MAX / 2 - 1) {
        *status = 7;
        return;
    }
    copy = malloc((length + 1) * sizeof(*copy));
    if (!copy) {
        *status = 7;
        return;
    }
    memcpy(copy, text, length * sizeof(*copy));
    copy[length] = 0;
    free(expression->text);
    expression->text = copy;
    expression->length = length;
    expression->next = 0;
    expression->matched = 0;
}
signed char uregex_find(SnowRegex *expression, int start, int *status) {
    int result;
    if (!status || *status > 0)
        return 0;
    if (!expression || !expression->text) {
        *status = 0x10302;
        return 0;
    }
    if (start < -1 || start > expression->length) {
        *status = 8;
        return 0;
    }
    if (start == -1)
        start = expression->next;
    expression->matched = 0;
    if (start > expression->length)
        return 0;
    result = pcre16_exec(expression->pattern, NULL, expression->text, expression->length, start, 0,
                         expression->offsets, expression->groups * 3);
    if (result < 0) {
        expression->next = expression->length + 1;
        if (result != PCRE_ERROR_NOMATCH)
            *status = result == PCRE_ERROR_NOMEMORY
                          ? 7
                          : (result == PCRE_ERROR_MATCHLIMIT || result == PCRE_ERROR_RECURSIONLIMIT
                                 ? 0x10312
                                 : 1);
        return 0;
    }
    expression->matched = 1;
    expression->next = expression->offsets[1];
    if (expression->offsets[0] == expression->next) {
        int next = expression->next++;
        if (next + 1 < expression->length && expression->text[next] >= 0xd800 &&
            expression->text[next] <= 0xdbff && expression->text[next + 1] >= 0xdc00 &&
            expression->text[next + 1] <= 0xdfff)
            expression->next++;
    }
    return 1;
}
static int snowRegexOffset(SnowRegex *expression, int group, int end, int *status) {
    if (!status || *status > 0)
        return -1;
    if (!expression || !expression->matched) {
        *status = 0x10302;
        return -1;
    }
    if (group < 0 || group >= expression->groups) {
        *status = 8;
        return -1;
    }
    return expression->offsets[group * 2 + end];
}
int uregex_start(SnowRegex *expression, int group, int *status) {
    return snowRegexOffset(expression, group, 0, status);
}
int uregex_end(SnowRegex *expression, int group, int *status) {
    return snowRegexOffset(expression, group, 1, status);
}
