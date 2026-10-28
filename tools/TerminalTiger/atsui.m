/* ATSUI layouts expressed through OPENSTEP's Unicode strings and font metrics. */
#import <AppKit/AppKit.h>
#import <AppKit/NSStringDrawing.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

typedef int TigerFixed;
typedef struct {
    TigerFixed x, y, dx, dy;
} TigerCaret;
typedef struct {
    TigerFixed x, y;
} TigerFixedPoint;
typedef struct {
    TigerFixedPoint upperLeft, upperRight, lowerRight, lowerLeft;
} TigerTrapezoid;

TigerFixed X2Fix(double value) {
    return (TigerFixed)floor(value * 65536.0 + 0.5);
}
double Fix2X(TigerFixed value) {
    return value / 65536.0;
}

@interface TigerATSUStyle : NSObject {
  @public
    NSFont *font;
    NSColor *color;
    float size, width, ascent, descent;
    BOOL bold, italic, underline;
}
@end
@implementation TigerATSUStyle
- init {
    self = [super init];
    font = [[NSFont userFixedPitchFontOfSize:12] retain];
    size = 12;
    return self;
}
- (void)dealloc {
    [font release];
    [color release];
    [super dealloc];
}
@end
@interface TigerATSURun : NSObject {
  @public
    TigerATSUStyle *style;
    unsigned start, length;
}
@end
@implementation TigerATSURun
- (void)dealloc {
    [style release];
    [super dealloc];
}
@end
@interface TigerATSULayout : NSObject {
  @public
    const unichar *text;
    unsigned total, start, length;
    float width;
    NSMutableArray *runs;
}
@end
@implementation TigerATSULayout
- init {
    self = [super init];
    runs = [[NSMutableArray alloc] init];
    return self;
}
- (void)dealloc {
    [runs release];
    [super dealloc];
}
@end

static TigerATSUStyle *tigerStyleAt(TigerATSULayout *layout, unsigned offset) {
    int i;
    static TigerATSUStyle *fallback;
    for (i = [layout->runs count] - 1; i >= 0; i--) {
        TigerATSURun *run = [layout->runs objectAtIndex:i];
        if (offset >= run->start && (run->length == ~0U || offset - run->start < run->length))
            return run->style;
    }
    if (!fallback)
        fallback = [[TigerATSUStyle alloc] init];
    return fallback;
}
static unsigned tigerLength(TigerATSULayout *layout, unsigned start, unsigned length) {
    if (start >= layout->total)
        return 0;
    return length > layout->total - start ? layout->total - start : length;
}
static float tigerAdvance(TigerATSULayout *layout, unsigned offset) {
    TigerATSUStyle *style = tigerStyleAt(layout, offset);
    unichar ch = layout->text[offset];
    if ([[NSCharacterSet nonBaseCharacterSet] characterIsMember:ch])
        return 0;
    if (ch >= 0xdc00 && ch <= 0xdfff && offset && layout->text[offset - 1] >= 0xd800 &&
        layout->text[offset - 1] <= 0xdbff)
        return 0;
    if (style->width > 0)
        return style->width;
    return [style->font widthOfString:[NSString stringWithCharacters:&ch length:1]];
}
static float tigerTextWidth(TigerATSULayout *layout, unsigned start, unsigned count) {
    float width = 0;
    unsigned end = start + tigerLength(layout, start, count);
    while (start < end)
        width += tigerAdvance(layout, start++);
    return width;
}
int ATSUCreateStyle(TigerATSUStyle **out) {
    *out = [[TigerATSUStyle alloc] init];
    return 0;
}
int ATSUDisposeStyle(id style) {
    [style release];
    return 0;
}
int ATSUCreateTextLayout(TigerATSULayout **out) {
    *out = [[TigerATSULayout alloc] init];
    return 0;
}
int ATSUDisposeTextLayout(id layout) {
    [layout release];
    return 0;
}
int ATSUSetAttributes(TigerATSUStyle *style, unsigned count, const unsigned *tags,
                      const unsigned *sizes, const void **values) {
    unsigned i;
    NSFont *font;
    for (i = 0; i < count; i++)
        switch (tags[i]) {
        case 256:
            style->bold = *(unsigned char *)values[i];
            break;
        case 257:
            style->italic = *(unsigned char *)values[i];
            break;
        case 258:
            style->underline = *(unsigned char *)values[i];
            break;
        case 261:
            font = *(id *)values[i];
            [font retain];
            [style->font release];
            style->font = font;
            break;
        case 262:
            style->size = Fix2X(*(TigerFixed *)values[i]);
            break;
        case 263: {
            const unsigned short *rgb = values[i];
            [style->color release];
            style->color = [[NSColor colorWithCalibratedRed:rgb[0] / 65535.0
                                                      green:rgb[1] / 65535.0
                                                       blue:rgb[2] / 65535.0
                                                      alpha:1] retain];
            break;
        }
        case 288: {
            const float *rgba = values[i];
            [style->color release];
            style->color = [[NSColor colorWithCalibratedRed:rgba[0]
                                                      green:rgba[1]
                                                       blue:rgba[2]
                                                      alpha:rgba[3]] retain];
            break;
        }
        case 266:
            style->width = Fix2X(*(TigerFixed *)values[i]);
            break;
        case 284:
            style->ascent = Fix2X(*(TigerFixed *)values[i]);
            break;
        case 285:
            style->descent = Fix2X(*(TigerFixed *)values[i]);
            break;
        }
    font = [NSFont fontWithName:[style->font fontName] size:style->size];
    if (!font)
        font = [NSFont userFixedPitchFontOfSize:style->size];
    [font retain];
    [style->font release];
    style->font = font;
    return 0;
}
int ATSUSetFontFeatures(id style, unsigned count, const unsigned short *types,
                        const unsigned short *selectors) {
    return 0;
}
int ATSUSetLayoutControls(TigerATSULayout *layout, unsigned count, const unsigned *tags,
                          const unsigned *sizes, const void **values) {
    unsigned i;
    for (i = 0; i < count; i++)
        if (tags[i] == 1)
            layout->width = Fix2X(*(TigerFixed *)values[i]);
    return 0;
}
int ATSUSetTransientFontMatching(id layout, unsigned char flag) {
    return 0;
}
int ATSUSetTextPointerLocation(TigerATSULayout *layout, const unichar *text, unsigned start,
                               unsigned length, unsigned total) {
    layout->text = text;
    layout->total = total;
    layout->start = start == ~0U ? 0 : start;
    layout->length = tigerLength(layout, layout->start, length);
    return 0;
}
int ATSUSetRunStyle(TigerATSULayout *layout, TigerATSUStyle *style, unsigned start,
                    unsigned length) {
    TigerATSURun *run;
    int i;
    unsigned end = length == ~0U ? ~0U : start + length;
    for (i = [layout->runs count] - 1; i >= 0; i--) {
        TigerATSURun *old = [layout->runs objectAtIndex:i];
        unsigned oldEnd = old->length == ~0U ? ~0U : old->start + old->length;
        if (oldEnd <= start || old->start >= end)
            continue;
        if (old->start < start && oldEnd > end) {
            TigerATSURun *tail = [[TigerATSURun alloc] init];
            tail->style = [old->style retain];
            tail->start = end;
            tail->length = oldEnd == ~0U ? ~0U : oldEnd - end;
            [layout->runs addObject:tail];
            [tail release];
            old->length = start - old->start;
        } else if (old->start < start)
            old->length = start - old->start;
        else if (oldEnd > end) {
            old->start = end;
            old->length = oldEnd == ~0U ? ~0U : oldEnd - end;
        } else
            [layout->runs removeObjectAtIndex:i];
    }
    run = [[TigerATSURun alloc] init];
    run->style = [style retain];
    run->start = start;
    run->length = length;
    [layout->runs addObject:run];
    [run release];
    return 0;
}
int ATSUTextInserted(TigerATSULayout *layout, unsigned start, unsigned length) {
    layout->total += length;
    return 0;
}
int ATSUTextDeleted(TigerATSULayout *layout, unsigned start, unsigned length) {
    layout->total -= length > layout->total ? layout->total : length;
    return 0;
}
int ATSUTextMoved(TigerATSULayout *layout, const unichar *text) {
    layout->text = text;
    return 0;
}
int ATSUBreakLine(TigerATSULayout *layout, unsigned start, TigerFixed fixedWidth,
                  unsigned char soft, unsigned *out) {
    float width = 0, limit = fixedWidth == 0x7fffffff ? layout->width : Fix2X(fixedWidth);
    unsigned i = start;
    while (i < layout->total) {
        float next = tigerAdvance(layout, i);
        if (width + next > limit && i > start)
            break;
        width += next;
        i++;
    }
    if (out)
        *out = i;
    return 0;
}
int ATSUGetGlyphBounds(TigerATSULayout *layout, TigerFixed x, TigerFixed y, unsigned start,
                       unsigned length, unsigned short kind, unsigned max, TigerTrapezoid *out,
                       unsigned *actual) {
    TigerATSUStyle *style = tigerStyleAt(layout, start);
    float w = tigerTextWidth(layout, start, length);
    /* Bounds stay relative to the line origin, even for a partial selection. */
    float left = Fix2X(x) + tigerTextWidth(layout, 0, start),
          top = Fix2X(y) + [style->font ascender],
          bottom = Fix2X(y) + [style->font descender];
    if (actual)
        *actual = 1;
    if (out && max) {
        out->upperLeft.x = out->lowerLeft.x = X2Fix(left);
        out->upperRight.x = out->lowerRight.x = X2Fix(left + w);
        out->upperLeft.y = out->upperRight.y = X2Fix(top);
        out->lowerLeft.y = out->lowerRight.y = X2Fix(bottom);
    }
    return 0;
}
int ATSUOffsetToPosition(TigerATSULayout *layout, unsigned offset, unsigned char leading,
                         TigerCaret *main, TigerCaret *second, unsigned char *split) {
    TigerATSUStyle *style = tigerStyleAt(layout, offset);
    TigerCaret caret;
    caret.x = X2Fix(tigerTextWidth(layout, 0, offset));
    caret.y = X2Fix([style->font descender]);
    caret.dx = caret.x;
    caret.dy = X2Fix([style->font ascender]);
    if (main)
        *main = caret;
    if (second)
        *second = caret;
    if (split)
        *split = 0;
    return 0;
}
int ATSUPositionToOffset(TigerATSULayout *layout, TigerFixed x, TigerFixed y, unsigned *primary,
                         unsigned char *leading, unsigned *secondary) {
    float width = 0, position = Fix2X(x);
    unsigned i = 0;
    while (i < layout->total) {
        float next = tigerAdvance(layout, i);
        if (width + next / 2 > position)
            break;
        width += next;
        i++;
    }
    if (primary)
        *primary = i;
    if (secondary)
        *secondary = i;
    if (leading)
        *leading = 1;
    return 0;
}
int ATSUNextCursorPosition(TigerATSULayout *layout, unsigned offset, unsigned short movement,
                           unsigned *out) {
    if (offset < layout->total)
        offset++;
    while (offset < layout->total && [[NSCharacterSet nonBaseCharacterSet]
                                         characterIsMember:layout->text[offset]])
        offset++;
    *out = offset;
    return 0;
}
int ATSUDrawText(TigerATSULayout *layout, unsigned start, unsigned length, TigerFixed x,
                 TigerFixed y) {
    float px = Fix2X(x), py = Fix2X(y);
    unsigned end = start + tigerLength(layout, start, length), i = start;
    while (i < end) {
        TigerATSUStyle *style = tigerStyleAt(layout, i);
        unsigned count = 1, j;
        float advance = 0, baseline;
        NSString *text;
        NSFont *font = style->font;
        NSFontTraitMask traits = 0;
        NSColor *color = style->color ? style->color : [NSColor blackColor];
        if (layout->text[i] >= 0xd800 && layout->text[i] <= 0xdbff && i + 1 < end &&
            layout->text[i + 1] >= 0xdc00 && layout->text[i + 1] <= 0xdfff)
            count++;
        while (i + count < end && [[NSCharacterSet nonBaseCharacterSet]
                                      characterIsMember:layout->text[i + count]])
            count++;
        text = [NSString stringWithCharacters:layout->text + i length:count];
        /* Terminal positions its baseline using AFM ascenders. Align that
         * position to the same native line metrics used for its row height. */
        baseline = py + ceil([font ascender]) - tigerFontLineMetrics(font).width;
        if (style->bold)
            traits |= NSBoldFontMask;
        if (style->italic)
            traits |= NSItalicFontMask;
        if (traits)
            font = [[NSFontManager sharedFontManager] convertFont:font toHaveTrait:traits];
        TigerDrawStringAtBaseline(text, font, color, px, baseline);
        if (style->bold &&
            !([[NSFontManager sharedFontManager] traitsOfFont:font] & NSBoldFontMask))
            TigerDrawStringAtBaseline(text, font, color, px + 0.5, baseline);
        for (j = 0; j < count; j++)
            advance += tigerAdvance(layout, i + j);
        if (style->underline) {
            PSgsave();
            [color set];
            PSrectfill(px, baseline + [font underlinePosition], advance, 1);
            PSgrestore();
        }
        px += advance;
        i += count;
    }
    return 0;
}
