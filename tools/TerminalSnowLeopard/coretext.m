/* Core Text's terminal-sized runs rendered by the native text system. */
/* Native font/layout work can change DPS's paint color. Quartz retains its
 * explicit fill color independently, including across saved graphics states. */
static NSColor *snowTextFillColor;
typedef struct SnowTextPaintState {
    NSColor *fill;
    struct SnowTextPaintState *previous;
} SnowTextPaintState;
static SnowTextPaintState *snowTextPaintStates;
@implementation NSColor (SnowDrawing)
- (void)setFill {
    [self retain];
    [snowTextFillColor release];
    snowTextFillColor = self;
    [self set];
}
- (void)setStroke {
    [self set];
}
@end
@interface NSGraphicsContext (SnowTextPaintState)
+ (void)saveGraphicsState;
+ (void)restoreGraphicsState;
@end
@implementation NSGraphicsContext (SnowTextPaintState)
+ (void)saveGraphicsState {
    SnowTextPaintState *state = malloc(sizeof(*state));
    if (!state)
        [NSException raise:NSMallocException format:@"Cannot save text paint state"];
    state->fill = [snowTextFillColor retain];
    state->previous = snowTextPaintStates;
    snowTextPaintStates = state;
    PSgsave();
}
+ (void)restoreGraphicsState {
    SnowTextPaintState *state = snowTextPaintStates;
    PSgrestore();
    if (state) {
        [snowTextFillColor release];
        snowTextFillColor = state->fill;
        snowTextPaintStates = state->previous;
        free(state);
    }
}
@end
@implementation NSLayoutManager (SnowFontMetrics)
- (float)defaultLineHeightForFont:(NSFont *)font {
    return tigerFontLineMetrics(font).height;
}
@end
NSString *kCTFontAttributeName = @"NSFont";
NSString *kCTForegroundColorAttributeName = @"NSColor";
typedef struct {
    float a, b, c, d, tx, ty;
} SnowTransform;
SnowTransform CGAffineTransformIdentity = {1, 0, 0, 1, 0, 0};
static NSPoint snowTextPosition;
static NSFont *snowGraphicsFont;
static float snowGraphicsFontSize;
static SnowTransform snowTextMatrix = {1, 0, 0, 1, 0, 0};
void SnowWriteScale(SnowTransform *out, float x, float y) {
    *out = CGAffineTransformIdentity;
    out->a = x;
    out->d = y;
}
asm(".text\n.align 2\n.globl _CGAffineTransformMakeScale\n_CGAffineTransformMakeScale:\n"
    "pushl %ebp\nmovl %esp,%ebp\npushl 16(%ebp)\npushl 12(%ebp)\npushl 8(%ebp)\ncall _SnowWriteScale\nmovl 8(%ebp),%eax\nleave\nret $4\n");
void CGContextMoveToPoint(void *context, float x, float y) {
    PSmoveto(x, y);
}
void CGContextAddLineToPoint(void *context, float x, float y) {
    PSlineto(x, y);
}
BOOL CGContextGetAllowsAntialiasing(void *context) {
    return NO;
}
void CGContextSetAllowsAntialiasing(void *context, BOOL value) {}
void CGContextSetBlendMode(void *context, int mode) {}
void CGContextSetFont(void *context, NSFont *font) {
    snowGraphicsFont = font;
}
void CGContextSetFontSize(void *context, float size) {
    snowGraphicsFontSize = size;
}
void CGContextSetTextDrawingMode(void *context, int mode) {}
void CGContextSetTextMatrix(void *context, SnowTransform matrix) {
    snowTextMatrix = matrix;
}
void CGContextSetTextPosition(void *context, float x, float y) {
    snowTextPosition = NSMakePoint(x, y);
}
NSPoint CGContextGetTextPosition(void *context) {
    return snowTextPosition;
}
void CGFontRelease(id font) {
    [font release];
}
id CTFontCopyGraphicsFont(NSFont *font, void *attributes) {
    return [font retain];
}
float CTFontGetSize(NSFont *font) {
    return [font pointSize];
}
float CTFontGetDescent(NSFont *font) {
    return -[font descender];
}
float CTFontGetLeading(NSFont *font) {
    return 2;
}
float CTFontGetUnderlinePosition(NSFont *font) {
    return [font underlinePosition];
}
float CTFontGetUnderlineThickness(NSFont *font) {
    return [font underlineThickness];
}
unsigned CTFontGetSymbolicTraits(NSFont *font) {
    unsigned native = [[NSFontManager sharedFontManager] traitsOfFont:font];
    return ((native & NSItalicFontMask) ? 1 : 0) | ((native & NSBoldFontMask) ? 2 : 0) |
           ([font isFixedPitch] ? 0x400 : 0);
}
BOOL CTFontShouldAntiAlias(NSFont *font) {
    return NO;
}
BOOL CTFontGetGlyphsForCharacters(NSFont *font, const unichar *characters, unsigned short *glyphs,
                                  int count) {
    memcpy(glyphs, characters, count * 2);
    return YES;
}
double CTFontGetAdvancesForGlyphs(NSFont *font, int orientation, const unsigned short *glyphs,
                                  NSSize *advances, int count) {
    int i;
    double total = 0;
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName];
    for (i = 0; i < count; i++) {
        float width = [[NSString stringWithCharacters:glyphs + i
                                               length:1] sizeWithAttributes:attributes]
                          .width;
#ifdef SNOW_TESTING
        {
            static unsigned traces;
            if (traces++ < 3)
                fprintf(stderr, "SNOW metric font=%s size=%g glyph=%u advance=%g stringWidth=%g\n",
                        [[font fontName] cString], [font pointSize], glyphs[i], width,
                        [font widthOfString:@"W"]);
        }
#endif
        if (advances)
            advances[i] = NSMakeSize(width, 0);
        total += width;
    }
    return total;
}
void CGContextShowGlyphsWithAdvances(void *context, const unsigned short *glyphs,
                                     const NSSize *advances, unsigned count) {
    unsigned i;
    float red, green, blue;
    NSFont *font = snowGraphicsFont ? snowGraphicsFont : (NSFont *)CGContextGetFont(context);
    NSColor *color = snowTextFillColor;
    if (snowGraphicsFontSize && snowGraphicsFontSize != [font pointSize])
        font = [NSFont fontWithName:[font fontName] size:snowGraphicsFontSize];
    if (!color) {
        PScurrentrgbcolor(&red, &green, &blue);
        color = [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:1];
    }
    for (i = 0; i < count; i++) {
        if (glyphs[i] && glyphs[i] != ' ')
            TigerDrawStringAtBaseline([NSString stringWithCharacters:glyphs + i length:1], font,
                                      color, snowTextPosition.x, snowTextPosition.y);
        snowTextPosition.x += advances[i].width;
        snowTextPosition.y += advances[i].height;
    }
}
@interface SnowTextRun : NSObject {
  @public
    NSString *text;
    NSDictionary *attributes;
    NSRange range;
}
@end
@implementation SnowTextRun
- (void)dealloc {
    [text release];
    [attributes release];
    [super dealloc];
}
@end
@interface SnowTextLine : NSObject {
  @public
    NSMutableArray *runs;
    unsigned count;
}
@end
@implementation SnowTextLine
- (void)dealloc {
    [runs release];
    [super dealloc];
}
@end
id CTLineCreateWithAttributedString(NSAttributedString *string) {
    SnowTextLine *line = [[SnowTextLine alloc] init];
    unsigned location = 0, length = [string length];
    line->runs = [[NSMutableArray alloc] init];
    line->count = length;
    while (location < length) {
        SnowTextRun *run = [[[SnowTextRun alloc] init] autorelease];
        NSRange range;
        run->attributes = [[string attributesAtIndex:location effectiveRange:&range] snowCopy];
        range = NSIntersectionRange(range, NSMakeRange(location, length - location));
        if (!range.length) {
            [line release];
            snowBadPlist();
        }
        run->range = range;
        run->text = [[[string string] substringWithRange:range] snowCopy];
        [line->runs addObject:run];
        location = NSMaxRange(range);
    }
    return line;
}
int CTLineGetGlyphCount(SnowTextLine *line) {
    return line->count;
}
id CTLineGetGlyphRuns(SnowTextLine *line) {
    return line->runs;
}
int CTRunGetGlyphCount(SnowTextRun *run) {
    return [run->text length];
}
id CTRunGetAttributes(SnowTextRun *run) {
    return run->attributes;
}
NSRange CTRunGetStringRange(SnowTextRun *run) {
    return run->range;
}
void CTRunGetGlyphs(SnowTextRun *run, NSRange range, unsigned short *glyphs) {
    if (!range.length)
        range.length = [run->text length] - range.location;
    [run->text getCharacters:glyphs range:range];
}
void CTRunGetStringIndices(SnowTextRun *run, NSRange range, int *indices) {
    unsigned i;
    if (!range.length)
        range.length = [run->text length] - range.location;
    for (i = 0; i < range.length; i++)
        indices[i] = run->range.location + range.location + i;
}
void CTRunGetAdvances(SnowTextRun *run, NSRange range, NSSize *advances) {
    unsigned short *glyphs;
    NSFont *font = [run->attributes objectForKey:NSFontAttributeName];
    if (!range.length)
        range.length = [run->text length] - range.location;
    glyphs = malloc(range.length * 2);
    CTRunGetGlyphs(run, range, glyphs);
    CTFontGetAdvancesForGlyphs(font ? font : [NSFont userFixedPitchFontOfSize:12], 0, glyphs,
                               advances, range.length);
    free(glyphs);
}
