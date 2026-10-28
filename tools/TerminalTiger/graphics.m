/* The subset of Quartz used by Tiger Terminal, backed by Display PostScript. */
#import <AppKit/AppKit.h>
#import <AppKit/NSDPSContext.h>
#import <AppKit/NSStringDrawing.h>
#import <objc/objc-class.h>
#include <math.h>
#include <string.h>
#include <stdlib.h>

static NSFont *tigerCurrentFont;
static IMP tigerNativeFontSet;
static IMP tigerNativeTerminalDraw;
static unsigned tigerDirtyMapOffset, tigerDirtyMapSize;
static NSSize tigerFontLineMetrics(NSFont *font);
static void tigerTerminalDraw(id view, SEL selector, NSRect rect) {
    /* OPENSTEP may erase the view during ancestor display even when Tiger's
     * row map is clean. Repaint the visible rows whenever AppKit calls us. */
    memset((char *)view + tigerDirtyMapOffset, 1, tigerDirtyMapSize);
    ((void (*)(id, SEL, NSRect))tigerNativeTerminalDraw)(view, selector, rect);
}
@implementation NSWindow (TigerShadow)
/* OPENSTEP's frame is redrawn by WindowServer; it has no cached Quartz shadow. */
- (void)invalidateShadow {
    [self flushWindowIfNeeded];
}
- (void)_setContentHasShadow:
    (BOOL)flag { /* WindowServer draws the native frame without a separate content shadow. */
}
@end
@implementation NSScreen (TigerVisibleFrame)
- (NSRect)visibleFrame {
    NSRect frame = [self frame];
    if (self == [NSScreen mainScreen]) {
        float menuWidth = 110;
        /* Reserve the vertical native menu and bottom application icons. */
        if (frame.size.width > menuWidth + 100) {
            frame.origin.x += menuWidth;
            frame.size.width -= menuWidth;
        }
        if (frame.size.height > 164) {
            frame.origin.y += 64;
            frame.size.height -= 64;
        }
    }
    return frame;
}
@end
void SetPt(short *point, short horizontal, short vertical) {
    point[0] = vertical;
    point[1] = horizontal;
}
void SetRect(short *rect, short left, short top, short right, short bottom) {
    rect[0] = top;
    rect[1] = left;
    rect[2] = bottom;
    rect[3] = right;
}
@implementation NSFont (TigerMetrics)
+ (float)systemFontSize {
    return [[self systemFontOfSize:0] pointSize];
}
+ (float)smallSystemFontSize {
    return [[self systemFontOfSize:10] pointSize];
}
+ (float)labelFontSize {
    return [self systemFontSize];
}
- (float)defaultLineHeightForFont {
    return tigerFontLineMetrics(self).height;
}
- (float)leading {
    return 2;
}
@end
static void tigerFontSet(id font, SEL selector) {
    tigerCurrentFont = font;
    ((void (*)(id, SEL))tigerNativeFontSet)(font, selector);
}
void TigerInitializeGraphics(void) {
    Method method = class_getInstanceMethod([NSFont class], @selector(set));
    Class terminal = NSClassFromString(@"TermSubview");
    Ivar dirty = class_getInstanceVariable(terminal, "dirtyMap");
    unsigned alignment;
    tigerNativeFontSet = method->method_imp;
    method->method_imp = (IMP)tigerFontSet;
    if (!dirty)
        [NSException raise:NSInternalInconsistencyException
                    format:@"Terminal row map is unavailable"];
    tigerDirtyMapOffset = dirty->ivar_offset;
    NSGetSizeAndAlignment(dirty->ivar_type, &tigerDirtyMapSize, &alignment);
    method = class_getInstanceMethod(terminal, @selector(drawRect:));
    tigerNativeTerminalDraw = method->method_imp;
    method->method_imp = (IMP)tigerTerminalDraw;
}

/* OPENSTEP's bitmap fonts can extend beyond their AFM ascender/descender.
 * Use the native typesetter's baseline and line box for terminal rows. */
static NSSize tigerFontLineMetrics(NSFont *font) {
    static NSMutableDictionary *cache;
    NSValue *cached;
    NSTextStorage *storage;
    NSLayoutManager *layout;
    NSTextContainer *container;
    NSPoint point;
    NSRect used;
    NSSize metrics;
    if (!cache)
        cache = [[NSMutableDictionary alloc] init];
    cached = [cache objectForKey:font];
    if (cached)
        return [cached sizeValue];
    storage = [[NSTextStorage alloc]
        initWithString:@"M"
            attributes:[NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName]];
    layout = [[NSLayoutManager alloc] init];
    container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(10000, 10000)];
    [container setLineFragmentPadding:0];
    [storage addLayoutManager:layout];
    [layout addTextContainer:container];
    [layout glyphRangeForTextContainer:container];
    point = [layout locationForGlyphAtIndex:0];
    used = [layout usedRectForTextContainer:container];
    metrics = NSMakeSize(point.y, used.size.height);
    [cache setObject:[NSValue valueWithSize:metrics] forKey:font];
    [container release];
    [layout release];
    [storage release];
    return metrics;
}
void TigerDrawStringAtBaseline(NSString *text, NSFont *font, NSColor *color, float x, float y) {
    static NSTextStorage *storage;
    static NSLayoutManager *layout;
    static NSTextContainer *container;
    NSRange glyphs;
    NSPoint point;
    NSDictionary *attributes =
        [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, color,
                                                   NSForegroundColorAttributeName, nil];
    if (!storage) {
        storage = [[NSTextStorage alloc] init];
        layout = [[NSLayoutManager alloc] init];
        /* ATSUI uses scalable metrics. Native bitmap screen-font substitution
         * can have taller glyphs than those metrics and clip terminal rows. */
        [layout setUsesScreenFonts:NO];
        container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(100000, 100000)];
        [container setLineFragmentPadding:0];
        [storage addLayoutManager:layout];
        [layout addTextContainer:container];
    }
    [storage replaceCharactersInRange:NSMakeRange(0, [storage length]) withString:text];
    [storage setAttributes:attributes range:NSMakeRange(0, [storage length])];
    glyphs = [layout glyphRangeForTextContainer:container];
    if (!glyphs.length)
        return;
    point = [layout locationForGlyphAtIndex:glyphs.location];
    [layout drawGlyphsForGlyphRange:glyphs atPoint:NSMakePoint(x - point.x, y - point.y)];
}

@interface NSGraphicsContext : NSObject {
    NSDPSContext *dps;
}
+ (id)currentContext;
+ (id)graphicsContextWithWindow:(NSWindow *)window;
+ (void)setCurrentContext:(NSGraphicsContext *)context;
- (void *)graphicsPort;
@end
@implementation NSGraphicsContext
+ (id)currentContext {
    NSGraphicsContext *context = [[[self alloc] init] autorelease];
    context->dps = [[NSDPSContext currentContext] retain];
    return context;
}
+ (id)graphicsContextWithWindow:(NSWindow *)window {
    return [self currentContext];
}
+ (void)setCurrentContext:(NSGraphicsContext *)context {
    if (context)
        [NSDPSContext setCurrentContext:context->dps];
}
+ (void)saveGraphicsState {
    PSgsave();
}
+ (void)restoreGraphicsState {
    PSgrestore();
}
- (void *)graphicsPort {
    return self;
}
- (BOOL)isDrawingToScreen {
    return [dps isDrawingToScreen];
}
- (BOOL)isFlipped {
    return NO;
}
- (void)setShouldAntialias:(BOOL)value {
}
- (void)flushGraphics {
    [dps flush];
}
- (void)dealloc {
    [dps release];
    [super dealloc];
}
@end

/* DPS has one paint color. Save Quartz's separate fill/stroke gray values. */
typedef struct {
    float fill, stroke;
    BOOL hasFill, hasStroke;
} TigerPaint;
static TigerPaint tigerPaint, tigerPaintStack[64];
static unsigned tigerPaintDepth;
void CGContextSaveGState(void *context) {
    if (tigerPaintDepth < 64)
        tigerPaintStack[tigerPaintDepth++] = tigerPaint;
    PSgsave();
}
void CGContextRestoreGState(void *context) {
    PSgrestore();
    if (tigerPaintDepth)
        tigerPaint = tigerPaintStack[--tigerPaintDepth];
}
void CGContextTranslateCTM(void *context, float x, float y) {
    PStranslate(x, y);
}
void CGContextScaleCTM(void *context, float x, float y) {
    PSscale(x, y);
}
void CGContextSetGrayFillColor(void *context, float gray, float alpha) {
    tigerPaint.fill = gray;
    tigerPaint.hasFill = YES;
}
void CGContextSetGrayStrokeColor(void *context, float gray, float alpha) {
    tigerPaint.stroke = gray;
    tigerPaint.hasStroke = YES;
}
void CGContextSetLineWidth(void *context, float width) {
    PSsetlinewidth(width);
}
void CGContextSetShouldAntialias(void *context, unsigned char flag) {}
void CGContextBeginPath(void *context) {
    PSnewpath();
}
void CGContextAddRect(void *context, NSRect r) {
    PSmoveto(r.origin.x, r.origin.y);
    PSrlineto(r.size.width, 0);
    PSrlineto(0, r.size.height);
    PSrlineto(-r.size.width, 0);
    PSclosepath();
}
void CGContextAddLines(void *context, const NSPoint *p, unsigned n) {
    unsigned i;
    if (!n)
        return;
    PSmoveto(p[0].x, p[0].y);
    for (i = 1; i < n; i++)
        PSlineto(p[i].x, p[i].y);
}
void CGContextClip(void *context) {
    PSclip();
    PSnewpath();
}
void CGContextFillPath(void *context) {
    PSgsave();
    if (tigerPaint.hasFill)
        PSsetgray(tigerPaint.fill);
    PSfill();
    PSgrestore();
    PSnewpath();
}
void CGContextStrokePath(void *context) {
    PSgsave();
    if (tigerPaint.hasStroke)
        PSsetgray(tigerPaint.stroke);
    PSstroke();
    PSgrestore();
    PSnewpath();
}
void CGContextFillRect(void *context, NSRect r) {
    PSgsave();
    if (tigerPaint.hasFill)
        PSsetgray(tigerPaint.fill);
    NSRectFill(r);
    PSgrestore();
}
void CGContextStrokeRectWithWidth(void *context, NSRect r, float width) {
    PSgsave();
    PSsetlinewidth(width);
    CGContextBeginPath(context);
    CGContextAddRect(context, r);
    CGContextStrokePath(context);
    PSgrestore();
}
id CGContextGetFont(void *context) {
    return tigerCurrentFont ? tigerCurrentFont : [NSFont userFixedPitchFontOfSize:12];
}
void *CGFontGetPlatformFont(id font) {
    static id platformFont;
    platformFont = font;
    return &platformFont;
}
unsigned FMGetFontFromATSFontRef(unsigned font) {
    return font;
}
int CGFontGetGlyphsForUnicodes(id font, const unsigned short *text, unsigned short *glyphs,
                               unsigned count) {
    /* Glyph handles are Unicode values within this shim; DPS shapes the text. */
    memcpy(glyphs, text, count * 2);
    return 1;
}
void CGContextShowGlyphsAtPoint(void *context, float x, float y, const unsigned short *glyphs,
                                unsigned count) {
    NSString *text = [NSString stringWithCharacters:glyphs length:count];
    NSFont *font = CGContextGetFont(context);
    float red, green, blue;
    PScurrentrgbcolor(&red, &green, &blue);
    TigerDrawStringAtBaseline(
        text, font, [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:1], x, y);
}
void NSRectFillUsingOperation(NSRect rect, int op) {
    NSRectFill(rect);
}
void NSFrameRectWithWidthUsingOperation(NSRect rect, float width, int op) {
    /* AppKit frames stay inside the rectangle. A centered Quartz stroke can
     * be clipped by the terminal row and lose the inactive cursor's edge. */
    NSFrameRectWithWidth(rect, width);
}

@interface TigerImageProvider : NSObject {
  @public
    const unsigned char *bytes;
    unsigned length;
    void *info;
    void (*releaseBytes)(void *, const void *, unsigned);
}
@end
@implementation TigerImageProvider
- (void)dealloc {
    if (releaseBytes)
        releaseBytes(info, bytes, length);
    [super dealloc];
}
@end
id CGDataProviderCreateWithData(void *info, const void *bytes, unsigned length,
                                void (*releaseBytes)(void *, const void *, unsigned)) {
    TigerImageProvider *p = [[TigerImageProvider alloc] init];
    p->bytes = bytes;
    p->length = length;
    p->info = info;
    p->releaseBytes = releaseBytes;
    return p;
}
@interface TigerImageMask : NSObject {
  @public
    unsigned width, height, bits, stride;
    TigerImageProvider *provider;
    BOOL inverted;
}
@end
@implementation TigerImageMask
- (void)dealloc {
    [provider release];
    [super dealloc];
}
@end
id CGImageMaskCreate(unsigned width, unsigned height, unsigned bpc, unsigned bpp, unsigned stride,
                     id provider, const float *decode, unsigned char interpolate) {
    TigerImageMask *mask = [[TigerImageMask alloc] init];
    mask->width = width;
    mask->height = height;
    mask->bits = bpc;
    mask->stride = stride;
    mask->provider = [provider retain];
    mask->inverted = decode && decode[0] > decode[1];
    return mask;
}
void CGContextDrawImage(void *context, NSRect rect, TigerImageMask *mask) {
    unsigned x, y, rowBytes = (mask->width + 7) / 8;
    NSMutableString *hex = [NSMutableString string];
    if (mask->stride * mask->height > mask->provider->length)
        return;
    for (y = 0; y < mask->height; y++)
        for (x = 0; x < rowBytes; x++) {
            unsigned b = 0, j;
            for (j = 0; j < 8; j++) {
                unsigned px = x * 8 + j, sample = 0;
                if (px < mask->width) {
                    const unsigned char *row = mask->provider->bytes + y * mask->stride;
                    if (mask->bits == 1)
                        sample = (row[px / 8] >> (7 - (px % 8))) & 1;
                    else if (mask->bits == 8)
                        sample = row[px] >= 128;
                    if (mask->inverted)
                        sample = !sample;
                }
                b = (b << 1) | sample;
            }
            [hex appendFormat:@"%02x", b];
        }
    [[NSDPSContext currentContext]
        printFormat:
            @"gsave %g %g translate %g %g scale %d %d false [%d 0 0 -%d 0 %d] <%@> imagemask grestore\n",
            rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, mask->width,
            mask->height, mask->width, mask->height, mask->height, hex];
}
