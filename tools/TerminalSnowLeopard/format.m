/* OPENSTEP's formatter predates Cocoa's UTF-16 %C and %S conversions. */
#include <stdarg.h>
#include <ctype.h>
static IMP snowNativeFormat, snowNativeLocaleFormat;
static NSString *snowFormatArguments(NSString *format, va_list arguments,
                                     NSMutableData **converted) {
    NSMutableString *result;
    NSMutableData *bytes;
    unsigned length = [format length], i = 0, start, end, width;
    char *input = (char *)arguments;
    BOOL wide;
    /* Leave positional formats to the native formatter. The supplied image
     * uses ordinary sequential conversions for Unicode characters. */
    if ([format rangeOfString:@"$"].location != NSNotFound ||
        ([format rangeOfString:@"C"].location == NSNotFound &&
         [format rangeOfString:@"S"].location == NSNotFound))
        return format;
    result = [NSMutableString string];
    bytes = [NSMutableData data];
    while (i < length) {
        unichar kind;
        start = i;
        while (i < length && [format characterAtIndex:i] != '%')
            i++;
        [result appendString:[format substringWithRange:NSMakeRange(start, i - start)]];
        if (i == length)
            break;
        start = i++;
        if (i < length && [format characterAtIndex:i] == '%') {
            [result appendString:@"%%"];
            i++;
            continue;
        }
        while (i < length && strchr("-+ #0'", [format characterAtIndex:i]))
            i++;
        while (i < length &&
               (isdigit([format characterAtIndex:i]) || [format characterAtIndex:i] == '*' ||
                [format characterAtIndex:i] == '.')) {
            if ([format characterAtIndex:i] == '*') {
                [bytes appendBytes:input length:4];
                input += 4;
            }
            i++;
        }
        wide = NO;
        width = 4;
        if (i < length && strchr("hlqLztj", [format characterAtIndex:i])) {
            kind = [format characterAtIndex:i++];
            if (kind == 'q' || kind == 'j')
                width = 8;
            if (kind == 'L') {
                width = 12;
                wide = YES;
            }
            if (i < length && [format characterAtIndex:i] == kind && (kind == 'h' || kind == 'l')) {
                i++;
                if (kind == 'l')
                    width = 8;
            }
        }
        if (i == length)
            return format;
        end = i;
        kind = [format characterAtIndex:i++];
        if (kind == 'C' || kind == 'S') {
            NSString *value;
            if (kind == 'C') {
                unichar character = (unichar) * (unsigned *)input;
                value = [NSString stringWithCharacters:&character length:1];
            } else {
                const unichar *characters = *(const unichar **)input;
                unsigned count = 0;
                if (characters) {
                    while (characters[count])
                        count++;
                    value = [NSString stringWithCharacters:characters length:count];
                } else
                    value = @"(null)";
            }
            [result appendString:[format substringWithRange:NSMakeRange(start, end - start)]];
            [result appendString:@"@"];
            [bytes appendBytes:&value length:4];
            input += 4;
        } else {
            if (strchr("eEfFgGaA", kind))
                width = wide ? 12 : 8;
            else if (strchr("@cspn", kind))
                width = 4;
            else if (!strchr("diouxXDUO", kind))
                return format;
            [result appendString:[format substringWithRange:NSMakeRange(start, i - start)]];
            [bytes appendBytes:input length:width];
            input += width;
        }
    }
    *converted = bytes;
    return result;
}
static id snowInitFormat(id object, SEL action, NSString *format, va_list arguments) {
    NSMutableData *converted = nil;
    format = snowFormatArguments(format, arguments, &converted);
    return ((id (*)(id, SEL, id, va_list))snowNativeFormat)(
        object, action, format, converted ? (va_list)[converted bytes] : arguments);
}
static id snowInitLocaleFormat(id object, SEL action, NSString *format, id locale,
                               va_list arguments) {
    NSMutableData *converted = nil;
    format = snowFormatArguments(format, arguments, &converted);
    return ((id (*)(id, SEL, id, id, va_list))snowNativeLocaleFormat)(
        object, action, format, locale, converted ? (va_list)[converted bytes] : arguments);
}
static void snowAppendFormat(id object, SEL action, NSString *format, ...) {
    va_list arguments;
    NSString *text;
    va_start(arguments, format);
    text = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    [object appendString:text];
    [text release];
}
void SnowInitializeFormatting(void) {
    id placeholder = [NSString alloc];
    Class cls = [placeholder class];
    Method method;
    method = class_getInstanceMethod(cls, @selector(initWithFormat:arguments:));
    snowNativeFormat = method->method_imp;
    method->method_imp = (IMP)snowInitFormat;
    method = class_getInstanceMethod(cls, @selector(initWithFormat:locale:arguments:));
    snowNativeLocaleFormat = method->method_imp;
    method->method_imp = (IMP)snowInitLocaleFormat;
    method = class_getInstanceMethod([[NSMutableString string] class], @selector(appendFormat:));
    method->method_imp = (IMP)snowAppendFormat;
    [placeholder release];
}
