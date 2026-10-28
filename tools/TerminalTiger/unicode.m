/* Unicode boundaries used by Terminal's cell counter and layout preparation. */
#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    unsigned unicodeEncoding, otherEncoding;
    int version;
} TigerUnicodeMapping;
typedef struct {
    unsigned encoding;
} TigerTextConverter;

int CreateTextToUnicodeInfo(const TigerUnicodeMapping *mapping, TigerTextConverter **out) {
    const unsigned *available;
    unsigned encoding;
    if (!mapping || !out)
        return -50;
    *out = NULL;
    if (mapping->unicodeEncoding != 0x100)
        return -8738;
    encoding = CFStringConvertEncodingToNSStringEncoding(mapping->otherEncoding);
    available = [NSString availableStringEncodings];
    while (*available && *available != encoding)
        available++;
    if (!*available)
        return -8738;
    *out = calloc(1, sizeof(TigerTextConverter));
    if (!*out)
        return -108;
    (*out)->encoding = encoding;
    return 0;
}
int DisposeTextToUnicodeInfo(TigerTextConverter **converter) {
    if (!converter)
        return -50;
    free(*converter);
    *converter = NULL;
    return 0;
}
int ConvertFromTextToUnicode(TigerTextConverter *converter, unsigned inputLength,
                             const unsigned char *input, unsigned flags, unsigned offsetCount,
                             const unsigned *offsets, unsigned *mappedCount, unsigned *mapped,
                             unsigned capacity, unsigned *read, unsigned *written,
                             unichar *output) {
    unsigned pos = 0, used = 0, offsetIndex = 0;
    int status = 0;
    if (read)
        *read = 0;
    if (written)
        *written = 0;
    if (mappedCount)
        *mappedCount = 0;
    if (!converter || (!input && inputLength) || (!output && capacity) || !read || !written ||
        (offsetCount && (!offsets || !mapped || !mappedCount)))
        return -50;
    while (pos < inputLength) {
        unsigned count = 1, units = 1, value = input[pos], j;
        unichar pair[2];
        int error = 0;
        if (converter->encoding == NSUTF8StringEncoding) {
            if (value >= 0xc2 && value <= 0xdf) {
                count = 2;
                value &= 31;
            } else if (value >= 0xe0 && value <= 0xef) {
                count = 3;
                value &= 15;
            } else if (value >= 0xf0 && value <= 0xf4) {
                count = 4;
                value &= 7;
            } else if (value >= 0x80)
                error = -8739;
            if (!error && count > inputLength - pos)
                error = -8753;
            if (!error)
                for (j = 1; j < count; j++) {
                    if ((input[pos + j] & 0xc0) != 0x80) {
                        error = -8739;
                        break;
                    }
                    value = (value << 6) | (input[pos + j] & 63);
                }
            if (!error && ((count == 2 && value < 0x80) || (count == 3 && value < 0x800) ||
                           (count == 4 && value < 0x10000) || value > 0x10ffff ||
                           (value >= 0xd800 && value <= 0xdfff)))
                error = -8739;
            if (value > 0xffff) {
                value -= 0x10000;
                pair[0] = 0xd800 + (value >> 10);
                pair[1] = 0xdc00 + (value & 1023);
                units = 2;
            } else
                pair[0] = value;
        } else {
            NSString *text = nil;
            for (count = 1; count <= 8 && count <= inputLength - pos; count++) {
                text = [[[NSString alloc] initWithData:[NSData dataWithBytes:input + pos
                                                                      length:count]
                                              encoding:converter->encoding] autorelease];
                if (text && [text length])
                    break;
            }
            if (!text || [text length] > 2)
                error = -8739;
            else {
                units = [text length];
                [text getCharacters:pair];
            }
        }
        if (error) {
            if (!(flags & 1) || (error == -8753 && (flags & 64))) {
                status = error;
                break;
            }
            pair[0] = 0xfffd;
            units = 1;
            count = 1;
            status = -8783;
        }
        if (units * 2 > capacity - used) {
            status = used ? -8785 : -8750;
            break;
        }
        while (offsetIndex < offsetCount && offsets[offsetIndex] <= pos) {
            mapped[offsetIndex] = used;
            offsetIndex++;
        }
        for (j = 0; j < units; j++)
            output[used / 2 + j] = (flags & 4096) && pair[j] == '\n' ? '\r' : pair[j];
        used += units * 2;
        pos += count;
    }
    while (offsetIndex < offsetCount && offsets[offsetIndex] <= pos) {
        mapped[offsetIndex] = used;
        offsetIndex++;
    }
    if (mappedCount)
        *mappedCount = offsetIndex;
    *read = pos;
    *written = used;
    return status;
}

int UCFindTextBreak(void *locator, unsigned type, unsigned options, const unichar *text,
                    unsigned length, unsigned start, unsigned *out) {
    unsigned position = start;
    BOOL backwards = (options & 2) != 0;
    if (!out || start > length || (!text && length))
        return -50;
    *out = start;
    if (type != 1 && type != 4)
        return -50;
    if (backwards) {
        if (!position)
            return 0;
        position--;
        if (position && text[position] >= 0xdc00 && text[position] <= 0xdfff &&
            text[position - 1] >= 0xd800 && text[position - 1] <= 0xdbff)
            position--;
    } else {
        if (position == length)
            return 0;
        position++;
        if (position < length && text[position - 1] >= 0xd800 && text[position - 1] <= 0xdbff &&
            text[position] >= 0xdc00 && text[position] <= 0xdfff)
            position++;
    }
    if (type == 4) {
        NSString *string = [NSString stringWithCharacters:text length:length];
        NSRange range =
            [string rangeOfComposedCharacterSequenceAtIndex:backwards ? position : start];
        position = backwards ? range.location : NSMaxRange(range);
    }
    *out = position;
    return 0;
}
