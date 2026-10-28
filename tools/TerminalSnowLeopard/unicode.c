/* ICU entry points used by Terminal, backed by the Unicode 5.1 tables.
 * unicode-data.inc is placed immediately before this file by the builder. */
#include <stdlib.h>
#include <string.h>
#include <limits.h>

#define SNOW_COUNT(a) (sizeof(a) / sizeof((a)[0]))
static unsigned snowUnicodeProperty(unsigned code) {
    unsigned low = 0, high = SNOW_COUNT(snowUnicodeProperties);
    while (low < high) {
        unsigned middle = low + (high - low) / 2;
        if (code < snowUnicodeProperties[middle].first)
            high = middle;
        else if (code > snowUnicodeProperties[middle].last)
            low = middle + 1;
        else
            return snowUnicodeProperties[middle].value;
    }
    return 0;
}
signed char u_charType(int code) {
    return snowUnicodeProperty(code) & 255;
}
signed char u_isMirrored(int code) {
    return (snowUnicodeProperty(code) >> 24) & 1;
}
int u_getIntPropertyValue(int code, int property) {
    unsigned value = snowUnicodeProperty(code);
    if (property == 0x1004)
        return (value >> 16) & 255;
    if (property == 0x1002)
        return (value >> 8) & 255;
    if (property == 0x1005)
        return value & 255;
    if (property == 3)
        return (value >> 24) & 1;
    return 0;
}
int u_charMirror(int code) {
    unsigned low = 0, high = SNOW_COUNT(snowUnicodeMirrors);
    while (low < high) {
        unsigned middle = low + (high - low) / 2;
        if ((unsigned)code < snowUnicodeMirrors[middle].code)
            high = middle;
        else if ((unsigned)code > snowUnicodeMirrors[middle].code)
            low = middle + 1;
        else
            return snowUnicodeMirrors[middle].mirror;
    }
    return code;
}
int utf8_nextCharSafeBody(const unsigned char *text, int *index, int length, int lead,
                          signed char strict) {
    int count, i = *index;
    unsigned code, minimum;
    if (lead >= 0xc2 && lead <= 0xdf) {
        count = 1;
        code = lead & 31;
        minimum = 0x80;
    } else if (lead >= 0xe0 && lead <= 0xef) {
        count = 2;
        code = lead & 15;
        minimum = 0x800;
    } else if (lead >= 0xf0 && lead <= 0xf4) {
        count = 3;
        code = lead & 7;
        minimum = 0x10000;
    } else
        return -1;
    while (count--) {
        if (i >= length || (text[i] & 0xc0) != 0x80) {
            *index = i;
            return -1;
        }
        code = (code << 6) | (text[i++] & 63);
    }
    *index = i;
    if (code < minimum || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff))
        return -1;
    if (strict > 0 && ((code & 0xfffe) == 0xfffe || (code >= 0xfdd0 && code <= 0xfdef)))
        return -1;
    return code;
}
int utf8_back1SafeBody(const unsigned char *text, int start, int index) {
    int original = index, count = 0;
    while (index > start && count < 3 && (text[index] & 0xc0) == 0x80) {
        index--;
        count++;
    }
    if (count && text[index] >= 0xc2 && text[index] <= 0xf4 &&
        utf8_countTrailBytes[text[index]] >= count)
        return index;
    return original;
}
unsigned short *u_strFromUTF8Lenient(unsigned short *out, int capacity, int *outLength,
                                     const char *source, int length, int *status) {
    int i = 0, used = 0, code;
    if (!status || *status > 0)
        return out;
    if (capacity < 0 || (!out && capacity) || !source || length < -1) {
        *status = 1;
        return out;
    }
    if (length < 0)
        length = strlen(source);
    while (i < length) {
        code = (unsigned char)source[i++];
        if (code >= 0x80)
            code = utf8_nextCharSafeBody((const unsigned char *)source, &i, length, code, -1);
        if (code < 0)
            code = 0xfffd;
        if (code >= 0x10000) {
            code -= 0x10000;
            if (used < capacity)
                out[used] = 0xd800 + (code >> 10);
            used++;
            if (used < capacity)
                out[used] = 0xdc00 + (code & 1023);
            used++;
        } else {
            if (used < capacity)
                out[used] = code;
            used++;
        }
    }
    if (outLength)
        *outLength = used;
    if (used > capacity)
        *status = 15;
    else if (used == capacity)
        *status = -124;
    else
        out[used] = 0;
    return out;
}

typedef struct {
    unsigned *points, count, capacity;
    int *status;
} SnowUnicodeBuffer;
static void snowUnicodeAppend(SnowUnicodeBuffer *buffer, unsigned code) {
    unsigned position, ccc = (snowUnicodeProperty(code) >> 8) & 255;
    if (*buffer->status > 0)
        return;
    if (buffer->count == buffer->capacity) {
        unsigned size = buffer->capacity ? buffer->capacity * 2 : 64;
        unsigned *points;
        if (size < buffer->capacity || size > INT_MAX / sizeof(unsigned)) {
            *buffer->status = 7;
            return;
        }
        points = realloc(buffer->points, size * sizeof(unsigned));
        if (!points) {
            *buffer->status = 7;
            return;
        }
        buffer->points = points;
        buffer->capacity = size;
    }
    position = buffer->count++;
    if (ccc)
        while (position && ((snowUnicodeProperty(buffer->points[position - 1]) >> 8) & 255) > ccc) {
            buffer->points[position] = buffer->points[position - 1];
            position--;
        }
    buffer->points[position] = code;
}
static void snowUnicodeDecompose(SnowUnicodeBuffer *buffer, unsigned code, int compatibility,
                                 unsigned depth) {
    unsigned low = 0, high = SNOW_COUNT(snowUnicodeDecompositions);
    if (depth > 32) {
        *buffer->status = 5;
        return;
    }
    if (code >= 0xac00 && code <= 0xd7a3) {
        unsigned syllable = code - 0xac00;
        snowUnicodeAppend(buffer, 0x1100 + syllable / 588);
        snowUnicodeAppend(buffer, 0x1161 + (syllable % 588) / 28);
        if (syllable % 28)
            snowUnicodeAppend(buffer, 0x11a7 + syllable % 28);
        return;
    }
    while (low < high) {
        unsigned middle = low + (high - low) / 2;
        const struct SnowUnicodeDecomposition *entry = &snowUnicodeDecompositions[middle];
        if (code < entry->code)
            high = middle;
        else if (code > entry->code)
            low = middle + 1;
        else {
            unsigned i;
            if (entry->compatibility && !compatibility)
                break;
            for (i = 0; i < entry->count; i++)
                snowUnicodeDecompose(buffer, snowUnicodeDecomposedPoints[entry->offset + i],
                                     compatibility, depth + 1);
            return;
        }
    }
    snowUnicodeAppend(buffer, code);
}
static unsigned snowUnicodeCompose(unsigned first, unsigned second) {
    unsigned low = 0, high = SNOW_COUNT(snowUnicodeCompositions);
    if (first >= 0x1100 && first < 0x1113 && second >= 0x1161 && second < 0x1176)
        return 0xac00 + (first - 0x1100) * 588 + (second - 0x1161) * 28;
    if (first >= 0xac00 && first <= 0xd7a3 && (first - 0xac00) % 28 == 0 && second > 0x11a7 &&
        second < 0x11c3)
        return first + second - 0x11a7;
    while (low < high) {
        unsigned middle = low + (high - low) / 2;
        if (first < snowUnicodeCompositions[middle].first ||
            (first == snowUnicodeCompositions[middle].first &&
             second < snowUnicodeCompositions[middle].second))
            high = middle;
        else if (first > snowUnicodeCompositions[middle].first ||
                 (first == snowUnicodeCompositions[middle].first &&
                  second > snowUnicodeCompositions[middle].second))
            low = middle + 1;
        else
            return snowUnicodeCompositions[middle].composed;
    }
    return 0;
}
int unorm_normalize(const unsigned short *source, int length, int mode, int options,
                    unsigned short *out, int capacity, int *status) {
    SnowUnicodeBuffer buffer;
    unsigned i, used = 0;
    if (!status || *status > 0)
        return 0;
    if (!source || length < -1 || capacity < 0 || (!out && capacity)) {
        *status = 1;
        return 0;
    }
    if (mode < 1 || mode > 5 || options) {
        *status = 16;
        return 0;
    }
    if (length < 0) {
        length = 0;
        while (source[length])
            length++;
    }
    if (mode == 1) {
        if (out && capacity)
            memmove(out, source, (length < capacity ? length : capacity) * sizeof(*out));
        if (length > capacity)
            *status = 15;
        else if (length == capacity)
            *status = -124;
        else
            out[length] = 0;
        return length;
    }
    memset(&buffer, 0, sizeof(buffer));
    buffer.status = status;
    for (i = 0; i < (unsigned)length; i++) {
        unsigned code = source[i];
        if (code >= 0xd800 && code <= 0xdbff && i + 1 < (unsigned)length &&
            source[i + 1] >= 0xdc00 && source[i + 1] <= 0xdfff) {
            code = 0x10000 + ((code - 0xd800) << 10) + (source[++i] - 0xdc00);
        }
        snowUnicodeDecompose(&buffer, code, mode == 3 || mode == 5, 0);
    }
    if (mode >= 4 && buffer.count) {
        unsigned starter = 0, lastClass = (snowUnicodeProperty(buffer.points[0]) >> 8) & 255,
                 count = 1;
        for (i = 1; i < buffer.count; i++) {
            unsigned code = buffer.points[i], ccc = (snowUnicodeProperty(code) >> 8) & 255;
            unsigned composed = (lastClass < ccc || lastClass == 0)
                                    ? snowUnicodeCompose(buffer.points[starter], code)
                                    : 0;
            if (composed)
                buffer.points[starter] = composed;
            else {
                if (!ccc)
                    starter = count;
                buffer.points[count++] = code;
                lastClass = ccc;
            }
        }
        buffer.count = count;
    }
    for (i = 0; i < buffer.count; i++) {
        unsigned code = buffer.points[i];
        if (code >= 0x10000) {
            code -= 0x10000;
            if (used < (unsigned)capacity)
                out[used] = 0xd800 + (code >> 10);
            used++;
            if (used < (unsigned)capacity)
                out[used] = 0xdc00 + (code & 1023);
            used++;
        } else {
            if (used < (unsigned)capacity)
                out[used] = code;
            used++;
        }
    }
    free(buffer.points);
    if (*status <= 0) {
        if (used > (unsigned)capacity)
            *status = 15;
        else if (used == (unsigned)capacity)
            *status = -124;
        else
            out[used] = 0;
    }
    return used;
}
signed char unorm_isNormalized(const unsigned short *source, int length, int mode, int *status) {
    unsigned short *result;
    int needed, inner = 0;
    signed char equal;
    if (!status || *status > 0)
        return 0;
    needed = unorm_normalize(source, length, mode, 0, NULL, 0, &inner);
    if (inner > 0 && inner != 15) {
        *status = inner;
        return 0;
    }
    result = malloc((needed + 1) * sizeof(unsigned short));
    if (!result) {
        *status = 7;
        return 0;
    }
    inner = 0;
    unorm_normalize(source, length, mode, 0, result, needed + 1, &inner);
    if (length < 0) {
        length = 0;
        while (source[length])
            length++;
    }
    equal =
        inner <= 0 && needed == length && !memcmp(source, result, length * sizeof(unsigned short));
    free(result);
    if (inner > 0)
        *status = inner;
    return equal;
}
