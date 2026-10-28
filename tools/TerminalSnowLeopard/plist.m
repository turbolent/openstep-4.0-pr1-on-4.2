/* Binary and XML property lists, including the keyed font/color archives
 * stored in Snow Leopard terminal profiles. All input offsets are bounded. */
@interface SnowPlistReader : NSObject {
    NSData *snowData;
    const unsigned char *snowBytes;
    unsigned snowLength, snowOffsetSize, snowReferenceSize, snowObjectCount, snowOffsets;
    NSMutableDictionary *snowCache;
}
- initWithData:(NSData *)data;
- (id)readObject:(unsigned)index depth:(unsigned)depth;
- (id)rootObject;
@end
static unsigned long long snowBigInteger(const unsigned char *p, unsigned count) {
    unsigned long long value = 0;
    unsigned i;
    for (i = 0; i < count; i++)
        value = (value << 8) | p[i];
    return value;
}
static void snowBadPlist(void) {
    [NSException raise:NSInvalidArgumentException format:@"Invalid property list"];
}
static long long snowDecimalInteger(NSString *text) {
    const char *p = [text cString];
    unsigned long long value = 0;
    BOOL negative = NO;
    while (*p == ' ' || *p == '\n' || *p == '\t')
        p++;
    if (*p == '-' || *p == '+')
        negative = *p++ == '-';
    if (*p < '0' || *p > '9')
        snowBadPlist();
    while (*p >= '0' && *p <= '9') {
        unsigned digit = *p++ - '0';
        if (value > (0x7fffffffffffffffULL + (negative ? 1 : 0) - digit) / 10)
            snowBadPlist();
        value = value * 10 + digit;
    }
    while (*p == ' ' || *p == '\n' || *p == '\t')
        p++;
    if (*p)
        snowBadPlist();
    return negative ? (long long)(0 - value) : (long long)value;
}
@implementation SnowPlistReader
- initWithData:(NSData *)data {
    const unsigned char *trailer;
    self = [super init];
    snowData = [data retain];
    snowBytes = [data bytes];
    snowLength = [data length];
    if (snowLength < 40 || memcmp(snowBytes, "bplist00", 8))
        snowBadPlist();
    trailer = snowBytes + snowLength - 32;
    snowOffsetSize = trailer[6];
    snowReferenceSize = trailer[7];
    if (!snowOffsetSize || snowOffsetSize > 4 || !snowReferenceSize || snowReferenceSize > 4)
        snowBadPlist();
    if (snowBigInteger(trailer + 8, 8) > 1000000 ||
        snowBigInteger(trailer + 24, 8) > snowLength - 32)
        snowBadPlist();
    snowObjectCount = snowBigInteger(trailer + 8, 8);
    snowOffsets = snowBigInteger(trailer + 24, 8);
    if (snowObjectCount > (snowLength - 32 - snowOffsets) / snowOffsetSize)
        snowBadPlist();
    snowCache = [[NSMutableDictionary alloc] init];
    return self;
}
- (id)rootObject {
    return [self readObject:snowBigInteger(snowBytes + snowLength - 16, 8) depth:0];
}
- (id)readObject:(unsigned)index depth:(unsigned)depth {
    unsigned offset, marker, type, count, width, i;
    NSNumber *key;
    id value;
    if (index >= snowObjectCount || depth > 128)
        snowBadPlist();
    key = [NSNumber numberWithUnsignedInt:index];
    value = [snowCache objectForKey:key];
    if (value)
        return value;
    offset = snowBigInteger(snowBytes + snowOffsets + index * snowOffsetSize, snowOffsetSize);
    if (offset < 8 || offset >= snowOffsets)
        snowBadPlist();
    marker = snowBytes[offset++];
    type = marker >> 4;
    count = marker & 15;
    if ((type >= 4 && type <= 6) || type == 10 || type == 12 || type == 13) {
        if (count == 15) {
            if (offset >= snowOffsets || (snowBytes[offset] >> 4) != 1 ||
                (snowBytes[offset] & 15) > 3)
                snowBadPlist();
            width = 1 << (snowBytes[offset++] & 15);
            if (width > snowOffsets - offset ||
                snowBigInteger(snowBytes + offset, width) > snowLength)
                snowBadPlist();
            count = snowBigInteger(snowBytes + offset, width);
            offset += width;
        }
    }
    switch (type) {
    case 0:
        value = count == 8 || count == 9 ? [NSNumber numberWithBool:count == 9] : [NSNull null];
        break;
    case 1:
        if (count > 3)
            snowBadPlist();
        width = 1 << count;
        if (width > snowOffsets - offset)
            snowBadPlist();
        value = [NSNumber numberWithLongLong:snowBigInteger(snowBytes + offset, width)];
        break;
    case 2:
        if (count == 2 && snowOffsets - offset >= 4) {
            unsigned bits = snowBigInteger(snowBytes + offset, 4);
            float number;
            memcpy(&number, &bits, 4);
            value = [NSNumber numberWithFloat:number];
        } else if (count == 3 && snowOffsets - offset >= 8) {
            unsigned long long bits = snowBigInteger(snowBytes + offset, 8);
            double number;
            memcpy(&number, &bits, 8);
            value = [NSNumber numberWithDouble:number];
        } else
            snowBadPlist();
        break;
    case 3: {
        unsigned long long bits;
        double number;
        if (count != 3 || snowOffsets - offset < 8)
            snowBadPlist();
        bits = snowBigInteger(snowBytes + offset, 8);
        memcpy(&number, &bits, 8);
        value = [NSDate dateWithTimeIntervalSinceReferenceDate:number];
        break;
    }
    case 4:
        if (count > snowOffsets - offset)
            snowBadPlist();
        value = [NSData dataWithBytes:snowBytes + offset length:count];
        break;
    case 5:
        if (count > snowOffsets - offset)
            snowBadPlist();
        value = [[[NSString alloc] initWithData:[NSData dataWithBytes:snowBytes + offset
                                                               length:count]
                                       encoding:NSASCIIStringEncoding] autorelease];
        break;
    case 6: {
        unichar *characters;
        if (count > (snowOffsets - offset) / 2)
            snowBadPlist();
        characters = malloc((count + 1) * 2);
        for (i = 0; i < count; i++)
            characters[i] = snowBigInteger(snowBytes + offset + i * 2, 2);
        value = [NSString stringWithCharacters:characters length:count];
        free(characters);
        break;
    }
    case 8:
        width = count + 1;
        if (width > 8 || width > snowOffsets - offset)
            snowBadPlist();
        value = [NSDictionary
            dictionaryWithObject:[NSNumber numberWithUnsignedInt:snowBigInteger(snowBytes + offset,
                                                                                width)]
                          forKey:@"CF$UID"];
        break;
    case 10:
    case 12: {
        NSMutableArray *array = [NSMutableArray array];
        if (count > (snowOffsets - offset) / snowReferenceSize)
            snowBadPlist();
        for (i = 0; i < count; i++)
            [array addObject:[self readObject:snowBigInteger(snowBytes + offset +
                                                                 i * snowReferenceSize,
                                                             snowReferenceSize)
                                        depth:depth + 1]];
        value = array;
        break;
    }
    case 13: {
        NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
        if (count > (snowOffsets - offset) / (2 * snowReferenceSize))
            snowBadPlist();
        for (i = 0; i < count; i++) {
            id name = [self readObject:snowBigInteger(snowBytes + offset + i * snowReferenceSize,
                                                      snowReferenceSize)
                                 depth:depth + 1];
            id item = [self
                readObject:snowBigInteger(snowBytes + offset + (i + count) * snowReferenceSize,
                                          snowReferenceSize)
                     depth:depth + 1];
            [dictionary setObject:item forKey:name];
        }
        value = dictionary;
        break;
    }
    default:
        snowBadPlist();
        value = nil;
    }
    if (!value)
        snowBadPlist();
    [snowCache setObject:value forKey:key];
    return value;
}
- (void)dealloc {
    [snowData release];
    [snowCache release];
    [super dealloc];
}
@end

static NSString *snowXMLUnescape(NSString *text) {
    NSMutableString *result = [NSMutableString string];
    unsigned i;
    for (i = 0; i < [text length]; i++) {
        unichar c = [text characterAtIndex:i];
        if (c == '&') {
            NSRange end = [text rangeOfString:@";"
                                      options:0
                                        range:NSMakeRange(i, [text length] - i)];
            NSString *entity;
            if (end.location == NSNotFound)
                snowBadPlist();
            entity = [text substringWithRange:NSMakeRange(i + 1, end.location - i - 1)];
            i = end.location;
            if ([entity isEqual:@"lt"])
                c = '<';
            else if ([entity isEqual:@"gt"])
                c = '>';
            else if ([entity isEqual:@"quot"])
                c = '"';
            else if ([entity isEqual:@"apos"])
                c = '\'';
            else if ([entity isEqual:@"amp"])
                c = '&';
            else if ([entity hasPrefix:@"#"]) {
                const char *digits = [entity cString] + 1;
                char *tail;
                unsigned long scalar;
                int base = 10;
                if (*digits == 'x') {
                    base = 16;
                    digits++;
                }
                scalar = strtoul(digits, &tail, base);
                if (!*digits || *tail || scalar > 0x10ffff ||
                    (scalar >= 0xd800 && scalar <= 0xdfff) ||
                    (scalar < 32 && scalar != 9 && scalar != 10 && scalar != 13))
                    snowBadPlist();
                if (scalar > 0xffff) {
                    unichar pair[2];
                    scalar -= 0x10000;
                    pair[0] = 0xd800 + (scalar >> 10);
                    pair[1] = 0xdc00 + (scalar & 1023);
                    [result appendString:[NSString stringWithCharacters:pair length:2]];
                    continue;
                }
                c = scalar;
            } else
                snowBadPlist();
        }
        [result appendString:[NSString stringWithCharacters:&c length:1]];
    }
    return result;
}
static void snowXMLText(NSMutableString *output, NSString *text) {
    unsigned i;
    for (i = 0; i < [text length]; i++) {
        unichar c = [text characterAtIndex:i];
        if (c == '&')
            [output appendString:@"&amp;"];
        else if (c == '<')
            [output appendString:@"&lt;"];
        else if (c == '>')
            [output appendString:@"&gt;"];
        else if (c < 32 && c != '\t' && c != '\n' && c != '\r')
            snowBadPlist();
        else
            [output appendString:[NSString stringWithCharacters:&c length:1]];
    }
}
static void snowPlistDecimal(char *buffer, unsigned long long value, BOOL negative) {
    char reversed[24];
    unsigned count = 0, i = 0;
    do {
        reversed[count++] = '0' + value % 10;
        value /= 10;
    } while (value);
    if (negative)
        buffer[i++] = '-';
    while (count)
        buffer[i++] = reversed[--count];
    buffer[i] = 0;
}
static void snowXMLWrite(NSMutableString *output, id value, unsigned depth) {
    unsigned i;
    if (depth > 128 || !value)
        snowBadPlist();
    if ([value isKindOfClass:[NSString class]]) {
        [output appendString:@"<string>"];
        snowXMLText(output, value);
        [output appendString:@"</string>"];
    } else if ([value isKindOfClass:[NSData class]]) {
        const unsigned char *bytes = [value bytes];
        unsigned length = [value length];
        const char *alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        [output appendString:@"<data>"];
        for (i = 0; i < length; i += 3) {
            char encoded[5];
            unsigned remaining = length - i;
            unsigned bits = (unsigned)bytes[i] << 16;
            if (remaining > 1)
                bits |= (unsigned)bytes[i + 1] << 8;
            if (remaining > 2)
                bits |= bytes[i + 2];
            encoded[0] = alphabet[(bits >> 18) & 63];
            encoded[1] = alphabet[(bits >> 12) & 63];
            encoded[2] = remaining > 1 ? alphabet[(bits >> 6) & 63] : '=';
            encoded[3] = remaining > 2 ? alphabet[bits & 63] : '=';
            encoded[4] = 0;
            [output appendString:[NSString stringWithCString:encoded]];
        }
        [output appendString:@"</data>"];
    } else if ([value isKindOfClass:[NSNumber class]]) {
        const char *type = [value objCType];
        char number[96];
        if (*type == 'c' || *type == 'B')
            [output appendString:[value boolValue] ? @"<true/>" : @"<false/>"];
        else if (*type == 'f' || *type == 'd') {
            sprintf(number, "%.17g", [value doubleValue]);
            [output appendFormat:@"<real>%s</real>", number];
        } else {
            if (*type == 'Q' || *type == 'I' || *type == 'L' || *type == 'S' || *type == 'C')
                snowPlistDecimal(number, [value unsignedLongLongValue], NO);
            else {
                long long integer = [value longLongValue];
                snowPlistDecimal(number,
                                 integer < 0 ? 0 - (unsigned long long)integer
                                             : (unsigned long long)integer,
                                 integer < 0);
            }
            [output appendFormat:@"<integer>%s</integer>", number];
        }
    } else if ([value isKindOfClass:[NSDate class]]) {
        NSCalendarDate *date = [NSCalendarDate
            dateWithTimeIntervalSinceReferenceDate:[value timeIntervalSinceReferenceDate]];
        [date setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
        [output appendFormat:@"<date>%@</date>",
                             [date descriptionWithCalendarFormat:@"%Y-%m-%dT%H:%M:%SZ"]];
    } else if ([value isKindOfClass:[NSArray class]]) {
        [output appendString:@"<array>"];
        for (i = 0; i < [value count]; i++)
            snowXMLWrite(output, [value objectAtIndex:i], depth + 1);
        [output appendString:@"</array>"];
    } else if ([value isKindOfClass:[NSDictionary class]]) {
        NSEnumerator *keys = [value keyEnumerator];
        id key;
        [output appendString:@"<dict>"];
        while ((key = [keys nextObject])) {
            if (![key isKindOfClass:[NSString class]])
                snowBadPlist();
            [output appendString:@"<key>"];
            snowXMLText(output, key);
            [output appendString:@"</key>"];
            snowXMLWrite(output, [value objectForKey:key], depth + 1);
        }
        [output appendString:@"</dict>"];
    } else
        snowBadPlist();
}
/* Binary property lists use fixed four-byte object references and offsets.
 * Keeping them fixed avoids integer truncation as a profile grows. */
static void snowPlistInteger(NSMutableData *data, unsigned long long value, unsigned width) {
    unsigned char bytes[8];
    unsigned i;
    for (i = 0; i < width; i++)
        bytes[width - 1 - i] = value >> (8 * i);
    [data appendBytes:bytes length:width];
}
static void snowPlistCount(NSMutableData *data, unsigned marker, unsigned count) {
    snowPlistInteger(data, marker + (count < 15 ? count : 15), 1);
    if (count >= 15) {
        snowPlistInteger(data, 0x12, 1);
        snowPlistInteger(data, count, 4);
    }
}
static unsigned snowBinaryObject(id value, NSMutableArray *objects, unsigned depth) {
    NSMutableData *data = [NSMutableData data];
    unsigned index = [objects count], i;
    if (depth > 128 || index >= 1000000 || !value)
        snowBadPlist();
    [objects addObject:data];
    if ([value isKindOfClass:[NSString class]]) {
        snowPlistCount(data, 0x60, [value length]);
        for (i = 0; i < [value length]; i++)
            snowPlistInteger(data, [value characterAtIndex:i], 2);
    } else if ([value isKindOfClass:[NSData class]]) {
        snowPlistCount(data, 0x40, [value length]);
        [data appendData:value];
    } else if ([value isKindOfClass:[NSNumber class]]) {
        const char *type = [value objCType];
        if (*type == 'c' || *type == 'B')
            snowPlistInteger(data, [value boolValue] ? 9 : 8, 1);
        else if (*type == 'f' || *type == 'd') {
            double number = [value doubleValue];
            unsigned long long bits;
            memcpy(&bits, &number, 8);
            snowPlistInteger(data, 0x23, 1);
            snowPlistInteger(data, bits, 8);
        } else {
            snowPlistInteger(data, 0x13, 1);
            snowPlistInteger(data, [value unsignedLongLongValue], 8);
        }
    } else if ([value isKindOfClass:[NSDate class]]) {
        double number = [value timeIntervalSinceReferenceDate];
        unsigned long long bits;
        memcpy(&bits, &number, 8);
        snowPlistInteger(data, 0x33, 1);
        snowPlistInteger(data, bits, 8);
    } else if ([value isKindOfClass:[NSArray class]]) {
        snowPlistCount(data, 0xa0, [value count]);
        for (i = 0; i < [value count]; i++)
            snowPlistInteger(data, snowBinaryObject([value objectAtIndex:i], objects, depth + 1),
                             4);
    } else if ([value isKindOfClass:[NSDictionary class]]) {
        NSArray *keys = [value allKeys];
        snowPlistCount(data, 0xd0, [keys count]);
        for (i = 0; i < [keys count]; i++) {
            id key = [keys objectAtIndex:i];
            if (![key isKindOfClass:[NSString class]])
                snowBadPlist();
            snowPlistInteger(data, snowBinaryObject(key, objects, depth + 1), 4);
        }
        for (i = 0; i < [keys count]; i++)
            snowPlistInteger(
                data,
                snowBinaryObject([value objectForKey:[keys objectAtIndex:i]], objects, depth + 1),
                4);
    } else
        snowBadPlist();
    return index;
}
static NSData *snowBinaryWrite(id value) {
    NSMutableArray *objects = [NSMutableArray array];
    NSMutableData *data = [NSMutableData dataWithBytes:"bplist00" length:8],
                  *offsets = [NSMutableData data];
    unsigned i, table;
    snowBinaryObject(value, objects, 0);
    for (i = 0; i < [objects count]; i++) {
        snowPlistInteger(offsets, [data length], 4);
        [data appendData:[objects objectAtIndex:i]];
    }
    table = [data length];
    [data appendData:offsets];
    snowPlistInteger(data, 0, 6);
    snowPlistInteger(data, 4, 1);
    snowPlistInteger(data, 4, 1);
    snowPlistInteger(data, [objects count], 8);
    snowPlistInteger(data, 0, 8);
    snowPlistInteger(data, table, 8);
    return data;
}
static id snowXMLValue(NSScanner *scanner, unsigned depth) {
    NSString *tag, *body;
    unsigned i;
    if (depth > 128)
        snowBadPlist();
    while (YES) {
        [scanner scanUpToString:@"<" intoString:NULL];
        if (![scanner scanString:@"<" intoString:NULL] ||
            ![scanner scanUpToString:@">" intoString:&tag] ||
            ![scanner scanString:@">" intoString:NULL])
            snowBadPlist();
        if (![tag hasPrefix:@"?"] && ![tag hasPrefix:@"!"])
            break;
    }
    if ([tag hasPrefix:@"plist"])
        return snowXMLValue(scanner, depth + 1);
    if ([tag isEqual:@"true/"] || [tag isEqual:@"true /"])
        return [NSNumber numberWithBool:YES];
    if ([tag isEqual:@"false/"] || [tag isEqual:@"false /"])
        return [NSNumber numberWithBool:NO];
    if ([tag isEqual:@"dict/"])
        return [NSDictionary dictionary];
    if ([tag isEqual:@"array/"])
        return [NSArray array];
    if ([tag isEqual:@"string/"])
        return @"";
    if ([tag isEqual:@"data/"])
        return [NSData data];
    if ([tag isEqual:@"dict"] || [tag isEqual:@"array"]) {
        BOOL dictionary = [tag isEqual:@"dict"];
        id result = dictionary ? (id)[NSMutableDictionary dictionary] : (id)[NSMutableArray array];
        NSString *close = dictionary ? @"</dict>" : @"</array>";
        while (![scanner scanString:close intoString:NULL]) {
            id item = snowXMLValue(scanner, depth + 1);
            if (dictionary)
                [result setObject:snowXMLValue(scanner, depth + 1) forKey:item];
            else
                [result addObject:item];
        }
        return result;
    }
    /* Scanner's default whitespace skipping would strip shell commands and
     * custom titles. Whitespace is significant inside string and data tags. */
    {
        NSCharacterSet *skip = [scanner charactersToBeSkipped];
        [scanner setCharactersToBeSkipped:nil];
        body = @"";
        [scanner scanUpToString:@"</" intoString:&body];
        [scanner setCharactersToBeSkipped:skip];
    }
    if (![scanner scanString:[NSString stringWithFormat:@"</%@>", tag] intoString:NULL])
        snowBadPlist();
    if ([tag isEqual:@"string"] || [tag isEqual:@"key"])
        return snowXMLUnescape(body);
    if ([tag isEqual:@"integer"])
        return [NSNumber numberWithLongLong:snowDecimalInteger(body)];
    if ([tag isEqual:@"real"])
        return [NSNumber numberWithDouble:[body doubleValue]];
    if ([tag isEqual:@"date"]) {
        NSCalendarDate *date = [NSCalendarDate dateWithString:body
                                               calendarFormat:@"%Y-%m-%dT%H:%M:%SZ"];
        if (!date)
            snowBadPlist();
        return [NSCalendarDate dateWithYear:[date yearOfCommonEra]
                                      month:[date monthOfYear]
                                        day:[date dayOfMonth]
                                       hour:[date hourOfDay]
                                     minute:[date minuteOfHour]
                                     second:[date secondOfMinute]
                                   timeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    }
    if ([tag isEqual:@"data"]) {
        NSMutableData *data = [NSMutableData data];
        unsigned bits = 0, count = 0;
        for (i = 0; i < [body length]; i++) {
            int c = [body characterAtIndex:i], v = -1;
            if (c >= 'A' && c <= 'Z')
                v = c - 'A';
            else if (c >= 'a' && c <= 'z')
                v = c - 'a' + 26;
            else if (c >= '0' && c <= '9')
                v = c - '0' + 52;
            else if (c == '+')
                v = 62;
            else if (c == '/')
                v = 63;
            if (v < 0)
                continue;
            bits = (bits << 6) | v;
            count += 6;
            if (count >= 8) {
                unsigned char byte;
                count -= 8;
                byte = bits >> count;
                [data appendBytes:&byte length:1];
            }
        }
        return data;
    }
    snowBadPlist();
    return nil;
}
@interface NSPropertyListSerialization : NSObject
+ (id)propertyListFromData:(NSData *)data
          mutabilityOption:(unsigned)option
                    format:(unsigned *)format
          errorDescription:(NSString **)error;
@end
@implementation NSPropertyListSerialization
+ (id)propertyListFromData:(NSData *)data
          mutabilityOption:(unsigned)option
                    format:(unsigned *)format
          errorDescription:(NSString **)error {
    id result = nil;
    NS_DURING
        if ([data length] >= 8 && !memcmp([data bytes], "bplist00", 8)) {
            result = [[[[SnowPlistReader alloc] initWithData:data] autorelease] rootObject];
            if (format)
                *format = 200;
        } else {
            NSString *string = [[[NSString alloc] initWithData:data
                                                      encoding:NSUTF8StringEncoding] autorelease];
            if ([string rangeOfString:@"<plist"].location != NSNotFound) {
                result = snowXMLValue([NSScanner scannerWithString:string], 0);
                if (format)
                    *format = 100;
            } else {
                result = [string propertyList];
                if (format)
                    *format = 1;
            }
        }
    NS_HANDLER
        if (error)
            *error = [[localException reason] snowCopy];
        result = nil;
    NS_ENDHANDLER
    return result;
}
+ (NSData *)dataFromPropertyList:(id)value
                          format:(unsigned)format
                errorDescription:(NSString **)error {
    NSData *result = nil;
    if (error)
        *error = nil;
    NS_DURING
        if (format == 200)
            result = snowBinaryWrite(value);
        else if (format == 100) {
            NSMutableString *output = [NSMutableString
                stringWithString:
                    @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">"];
            snowXMLWrite(output, value, 0);
            [output appendString:@"</plist>\n"];
            result = [output dataUsingEncoding:NSUTF8StringEncoding];
        } else if (format == 1 && snowIsNativePlist(value))
            result = [[value description] dataUsingEncoding:NSUTF8StringEncoding];
        else
            snowBadPlist();
    NS_HANDLER
        if (error)
            *error = [[localException reason] snowCopy];
    NS_ENDHANDLER
    return result;
}
@end

@implementation NSDictionary (SnowPropertyListFiles)
+ (id)dictionaryWithContentsOfFile:(NSString *)path {
    id value =
        [NSPropertyListSerialization propertyListFromData:[NSData dataWithContentsOfFile:path]
                                         mutabilityOption:1
                                                   format:NULL
                                         errorDescription:NULL];
    if (![value isKindOfClass:[NSDictionary class]])
        return nil;
    return [[[self alloc] initWithDictionary:value] autorelease];
}
@end
@implementation NSArray (SnowPropertyListFiles)
+ (id)arrayWithContentsOfFile:(NSString *)path {
    id value =
        [NSPropertyListSerialization propertyListFromData:[NSData dataWithContentsOfFile:path]
                                         mutabilityOption:1
                                                   format:NULL
                                         errorDescription:NULL];
    if (![value isKindOfClass:[NSArray class]])
        return nil;
    return [[[self alloc] initWithArray:value] autorelease];
}
@end

static id snowUnarchiveValue(id value, NSArray *objects, unsigned depth) {
    id classValue, definition;
    NSString *className;
    if (depth > 128)
        snowBadPlist();
    if (![value isKindOfClass:[NSDictionary class]])
        return value;
    if ([value objectForKey:@"CF$UID"]) {
        unsigned index = [[value objectForKey:@"CF$UID"] unsignedIntValue];
        if (index == 0)
            return nil;
        if (index >= [objects count])
            snowBadPlist();
        return snowUnarchiveValue([objects objectAtIndex:index], objects, depth + 1);
    }
    classValue = [value objectForKey:@"$class"];
    if (!classValue)
        return value;
    definition = snowUnarchiveValue(classValue, objects, depth + 1);
    className = [definition objectForKey:@"$classname"];
    if ([className isEqual:@"NSFont"]) {
        NSString *name = snowUnarchiveValue([value objectForKey:@"NSName"], objects, depth + 1);
        float size = [[value objectForKey:@"NSSize"] floatValue];
        /* Native fontWithName: silently substitutes Helvetica for unknown
         * families. Choose a fixed-pitch replacement for Menlo and Monaco. */
        NSFont *font;
        if (![[[NSFontManager sharedFontManager] availableFonts] containsObject:name])
            name = @"Courier";
        font = [NSFont fontWithName:name size:size];
        return font ? font : [NSFont userFixedPitchFontOfSize:size];
    }
    if ([className isEqual:@"NSColor"]) {
        NSData *data = [value objectForKey:@"NSRGB"];
        float a = 1, b = 0, c = 0, d = 1;
        unsigned space = [[value objectForKey:@"NSColorSpace"] unsignedIntValue];
        if (space == 6)
            return snowUnarchiveValue([value objectForKey:@"NSColor"], objects, depth + 1);
        if (data) {
            NSString *text = [[[NSString alloc] initWithData:data
                                                    encoding:NSASCIIStringEncoding] autorelease];
            sscanf([text cString], "%f %f %f %f", &a, &b, &c, &d);
            return [NSColor colorWithCalibratedRed:a green:b blue:c alpha:d];
        }
        data = [value objectForKey:@"NSWhite"];
        if (data) {
            NSString *text = [[[NSString alloc] initWithData:data
                                                    encoding:NSASCIIStringEncoding] autorelease];
            sscanf([text cString], "%f %f", &a, &d);
            return [NSColor colorWithCalibratedWhite:a alpha:d];
        }
        return [NSColor blackColor];
    }
    if ([className isEqual:@"NSString"] || [className isEqual:@"NSMutableString"])
        return snowUnarchiveValue([value objectForKey:@"NS.string"], objects, depth + 1);
    if ([className isEqual:@"NSArray"] || [className isEqual:@"NSMutableArray"]) {
        NSArray *items = [value objectForKey:@"NS.objects"];
        NSMutableArray *result = [NSMutableArray array];
        unsigned i;
        for (i = 0; i < [items count]; i++)
            [result addObject:snowUnarchiveValue([items objectAtIndex:i], objects, depth + 1)];
        return result;
    }
    if ([className isEqual:@"NSDictionary"] || [className isEqual:@"NSMutableDictionary"]) {
        NSArray *keys = [value objectForKey:@"NS.keys"],
                *items = [value objectForKey:@"NS.objects"];
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        unsigned i;
        for (i = 0; i < [keys count]; i++)
            [result setObject:snowUnarchiveValue([items objectAtIndex:i], objects, depth + 1)
                       forKey:snowUnarchiveValue([keys objectAtIndex:i], objects, depth + 1)];
        return result;
    }
    [NSException raise:NSInvalidArgumentException
                format:@"Unsupported archived class %@", className];
    return nil;
}
@interface NSKeyedUnarchiver : NSObject
+ (id)unarchiveObjectWithData:(NSData *)data;
@end
@implementation NSKeyedUnarchiver
+ (id)unarchiveObjectWithData:(NSData *)data {
    NSDictionary *archive;
    if ([data length] > 12 && !memcmp((char *)[data bytes] + 2, "streamtyped", 11))
        return [NSUnarchiver unarchiveObjectWithData:data];
    archive = [NSPropertyListSerialization propertyListFromData:data
                                               mutabilityOption:0
                                                         format:NULL
                                               errorDescription:NULL];
    return snowUnarchiveValue([[archive objectForKey:@"$top"] objectForKey:@"root"],
                              [archive objectForKey:@"$objects"], 0);
}
@end
@interface NSKeyedArchiver : NSObject
+ (NSData *)archivedDataWithRootObject:(id)object;
@end
@implementation NSKeyedArchiver
+ (NSData *)archivedDataWithRootObject:(id)object {
    return [NSArchiver archivedDataWithRootObject:object];
}
@end
