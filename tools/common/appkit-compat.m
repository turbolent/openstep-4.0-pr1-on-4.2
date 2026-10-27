#import <AppKit/AppKit.h>
#include <stdarg.h>

/* OPENSTEP 4.2 implements cell tooltips but omits them from NSMatrix.h. */
@interface NSMatrix (OpenStep42ToolTips)
- (void)setToolTip:(NSString *)text forCell:(NSCell *)cell;
@end

/* Register PR1 help with AppKit instead of its obsolete bubble helpers. */
@interface NSView (PR1ToolTipCompatibility)
- (void)registerHelpText:(NSString *)text;
- (void)unregisterHelpText;
@end
@implementation NSView (PR1ToolTipCompatibility)
- (void)registerHelpText:(NSString *)text { [self setToolTip:text]; }
- (void)unregisterHelpText { [self setToolTip:nil]; }
@end

@interface NSMatrix (PR1ToolTipCompatibility)
- (void)registerHelpText:(NSString *)text forCell:(NSCell *)cell;
@end
@implementation NSMatrix (PR1ToolTipCompatibility)
- (void)registerHelpText:(NSString *)text forCell:(NSCell *)cell {
    [self setToolTip:text forCell:cell];
}
@end

@interface NSString (PR1StringCompatibility)
- (NSString *)substringFromRange:(NSRange)range;
@end
@implementation NSString (PR1StringCompatibility)
- (NSString *)substringFromRange:(NSRange)range { return [self substringWithRange:range]; }
@end

/* PR1 NSText uses NSString objects here (not the old C-string Text API). */
@interface NSText (PR1TextCompatibility)
- (void)setText:(NSString *)text;
- (NSString *)text;
- (void)replaceSel:(NSString *)text;
- (void)setSelectionStart:(int)start end:(int)end;
- (void)scrollSelToVisible;
@end
@implementation NSText (PR1TextCompatibility)
- (void)setText:(NSString *)text { [self setString:text ? text : @""]; }
- (NSString *)text { return [self string]; }
- (void)replaceSel:(NSString *)text {
    [self replaceCharactersInRange:[self selectedRange] withString:text ? text : @""];
}
- (void)setSelectionStart:(int)start end:(int)end {
    unsigned int length = [[self string] length];
    unsigned int first = start < 0 ? 0 : (unsigned int)start;
    unsigned int last = end < 0 ? length : (unsigned int)end;
    if (first > length) first = length;
    if (last > length) last = length;
    if (last < first) last = first;
    [self setSelectedRange:NSMakeRange(first, last - first)];
}
- (void)scrollSelToVisible { [self scrollRangeToVisible:[self selectedRange]]; }
@end

@interface NSButton (PR1Compatibility)
- (void)setType:(int)type;
@end
@implementation NSButton (PR1Compatibility)
- (void)setType:(int)type { [self setButtonType:(NSButtonType)type]; }
@end

@interface NSCursor (PR1Compatibility)
- initWithImage:(NSImage *)image;
@end
@implementation NSCursor (PR1Compatibility)
- initWithImage:(NSImage *)image {
    return [self initWithImage:image hotSpot:NSMakePoint(0, 0)];
}
@end

@interface NSTextView (PR1Compatibility)
- (void)setSelectionColor:(NSColor *)color;
- (NSColor *)selectionColor;
@end
@implementation NSTextView (PR1Compatibility)
- (void)setSelectionColor:(NSColor *)color {
    NSMutableDictionary *attributes = [[self selectedTextAttributes] mutableCopy];
    if (!attributes) attributes = [[NSMutableDictionary alloc] init];
    if (color) [attributes setObject:color forKey:NSBackgroundColorAttributeName];
    else [attributes removeObjectForKey:NSBackgroundColorAttributeName];
    [self setSelectedTextAttributes:attributes];
    [attributes release];
}
- (NSColor *)selectionColor {
    return [[self selectedTextAttributes] objectForKey:NSBackgroundColorAttributeName];
}
@end

int NSRunLocalizedAlertPanel(NSString *table, NSString *title, NSString *format,
    NSString *defaultButton, NSString *alternateButton, NSString *otherButton, ...)
{
    va_list args;
    NSString *message;
    int result;
    NSBundle *bundle = [NSBundle mainBundle];
    if (title) title = [bundle localizedStringForKey:title value:title table:table];
    if (format) format = [bundle localizedStringForKey:format value:format table:table];
    if (defaultButton) defaultButton = [bundle localizedStringForKey:defaultButton value:defaultButton table:table];
    if (alternateButton) alternateButton = [bundle localizedStringForKey:alternateButton value:alternateButton table:table];
    if (otherButton) otherButton = [bundle localizedStringForKey:otherButton value:otherButton table:table];
    va_start(args, otherButton);
    message = [[[NSString alloc] initWithFormat:format arguments:args] autorelease];
    va_end(args);
    result = NSRunAlertPanel(title, @"%@", defaultButton, alternateButton, otherButton, message);
    return result;
}
