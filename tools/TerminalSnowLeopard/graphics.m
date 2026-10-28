/* Cocoa graphics objects implemented with Display PostScript. */
#import <AppKit/psopsOpenStep.h>

/* Cocoa's compositing operation also applies to translucent selection colors. */
void SnowNSRectFillUsingOperation(NSRect rect, int operation) {
    if (rect.size.width > 0 && rect.size.height > 0)
        PScompositerect(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, operation);
}

static void snowCompositeColor(NSColor *color, NSRect rect) {
    float alpha = [color alphaComponent];
    if (alpha <= 0)
        return;
    [color set];
    PSsetalpha(alpha);
    PScompositerect(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height,
                    NSCompositeSourceOver);
}
@implementation NSGraphicsContext (SnowInterpolation)
/* DPS selects its own image sampling; it has no Quartz quality setting. */
- (void)setImageInterpolation:(unsigned)quality {
}
- (unsigned)imageInterpolation {
    return 0;
}
@end
@implementation NSImage (SnowImageDrawing)
- (void)drawAtPoint:(NSPoint)point
           fromRect:(NSRect)source
          operation:(NSCompositingOperation)operation
           fraction:(float)fraction {
    NSBitmapImageRep *pixels;
    NSSize size = [self size];
    if (fraction <= 0)
        return;
    if (NSEqualRects(source, NSZeroRect))
        source.size = size;
    /* Native compositeToPoint ignores CTM scaling. Cocoa drawAtPoint does
     * not: Terminal downsamples its profile previews through this method. */
    pixels = [NSBitmapImageRep imageRepWithData:[self TIFFRepresentation]];

    if (!pixels)
        return;
    PSgsave();
    NSRectClip(NSMakeRect(point.x, point.y, source.size.width, source.size.height));
    [pixels drawInRect:NSMakeRect(point.x - source.origin.x, point.y - source.origin.y, size.width,
                                  size.height)];
    PSgrestore();
}
- (void)drawInRect:(NSRect)destination
          fromRect:(NSRect)source
         operation:(NSCompositingOperation)operation
          fraction:(float)fraction {
    if (NSEqualRects(source, NSZeroRect))
        source.size = [self size];
    if (source.size.width <= 0 || source.size.height <= 0 || destination.size.width <= 0 ||
        destination.size.height <= 0)
        return;
    PSgsave();
    NSRectClip(destination);
    PStranslate(destination.origin.x, destination.origin.y);
    PSscale(destination.size.width / source.size.width,
            destination.size.height / source.size.height);
    [self drawAtPoint:NSZeroPoint fromRect:source operation:operation fraction:fraction];
    PSgrestore();
}
@end
@interface NSAffineTransform : NSObject <NSCopying> {
  @public
    SnowTransform matrix;
}
+ (id)transform;
- (SnowTransform)transformStruct;
- (void)setTransformStruct:(SnowTransform)value;
@end
static SnowTransform snowMultiplyTransform(SnowTransform a, SnowTransform b) {
    SnowTransform out;
    out.a = a.a * b.a + a.c * b.b;
    out.b = a.b * b.a + a.d * b.b;
    out.c = a.a * b.c + a.c * b.d;
    out.d = a.b * b.c + a.d * b.d;
    out.tx = a.a * b.tx + a.c * b.ty + a.tx;
    out.ty = a.b * b.tx + a.d * b.ty + a.ty;
    return out;
}
@implementation NSAffineTransform
- init {
    self = [super init];
    matrix = CGAffineTransformIdentity;
    return self;
}
+ (id)transform {
    return [[[self alloc] init] autorelease];
}
- initWithTransform:(NSAffineTransform *)other {
    self = [self init];
    matrix = other->matrix;
    return self;
}
- (id)copyWithZone:(NSZone *)zone {
    return [[[self class] allocWithZone:zone] initWithTransform:self];
}
- (SnowTransform)transformStruct {
    return matrix;
}
- (void)setTransformStruct:(SnowTransform)value {
    matrix = value;
}
/* Appending applies the receiver first, then the supplied transform:
 * https://developer.apple.com/documentation/foundation/nsaffinetransform/append(_:) */
- (void)appendTransform:(NSAffineTransform *)other {
    matrix = snowMultiplyTransform(other->matrix, matrix);
}
- (void)prependTransform:(NSAffineTransform *)other {
    matrix = snowMultiplyTransform(matrix, other->matrix);
}
- (void)translateXBy:(float)x yBy:(float)y {
    SnowTransform t = CGAffineTransformIdentity;
    t.tx = x;
    t.ty = y;
    matrix = snowMultiplyTransform(matrix, t);
}
- (void)scaleXBy:(float)x yBy:(float)y {
    SnowTransform t = CGAffineTransformIdentity;
    t.a = x;
    t.d = y;
    matrix = snowMultiplyTransform(matrix, t);
}
- (void)scaleBy:(float)scale {
    [self scaleXBy:scale yBy:scale];
}
- (void)rotateByRadians:(float)angle {
    SnowTransform t = CGAffineTransformIdentity;
    t.a = t.d = cos(angle);
    t.b = sin(angle);
    t.c = -t.b;
    matrix = snowMultiplyTransform(matrix, t);
}
- (void)rotateByDegrees:(float)angle {
    [self rotateByRadians:angle * 3.14159265358979323846 / 180];
}
- (void)invert {
    double determinant = matrix.a * matrix.d - matrix.b * matrix.c;
    SnowTransform t;
    if (determinant == 0)
        [NSException raise:NSInvalidArgumentException format:@"Cannot invert a singular transform"];
    t.a = matrix.d / determinant;
    t.b = -matrix.b / determinant;
    t.c = -matrix.c / determinant;
    t.d = matrix.a / determinant;
    t.tx = -(t.a * matrix.tx + t.c * matrix.ty);
    t.ty = -(t.b * matrix.tx + t.d * matrix.ty);
    matrix = t;
}
- (NSPoint)transformPoint:(NSPoint)point {
    return NSMakePoint(matrix.a * point.x + matrix.c * point.y + matrix.tx,
                       matrix.b * point.x + matrix.d * point.y + matrix.ty);
}
- (NSSize)transformSize:(NSSize)size {
    return NSMakeSize(matrix.a * size.width + matrix.c * size.height,
                      matrix.b * size.width + matrix.d * size.height);
}
- (void)concat {
    PSconcat((float *)&matrix);
}
- (void)set {
    PSsendfloatarray((float *)&matrix, 6);
    PSsetmatrix();
}
@end

@interface NSColorSpace : NSObject {
  @public
    NSString *spaceName;
}
+ (id)genericRGBColorSpace;
@end
@implementation NSColorSpace
+ (id)spaceWithName:(NSString *)name {
    static NSMutableDictionary *spaces;
    id value;
    if (!spaces)
        spaces = [[NSMutableDictionary alloc] init];
    value = [spaces objectForKey:name];
    if (!value) {
        value = [[[self alloc] init] autorelease];
        ((NSColorSpace *)value)->spaceName = [name retain];
        [spaces setObject:value forKey:name];
    }
    return value;
}
+ (id)genericRGBColorSpace {
    return [self spaceWithName:NSCalibratedRGBColorSpace];
}
+ (id)deviceRGBColorSpace {
    return [self spaceWithName:NSDeviceRGBColorSpace];
}
+ (id)genericGrayColorSpace {
    return [self spaceWithName:NSCalibratedWhiteColorSpace];
}
+ (id)deviceGrayColorSpace {
    return [self spaceWithName:NSDeviceWhiteColorSpace];
}
+ (id)deviceCMYKColorSpace {
    return [self spaceWithName:NSDeviceCMYKColorSpace];
}
- (int)colorSpaceModel {
    if ([spaceName isEqual:NSDeviceCMYKColorSpace])
        return 2;
    return [spaceName rangeOfString:@"White"].location != NSNotFound ? 0 : 1;
}
- (int)numberOfColorComponents {
    int model = [self colorSpaceModel];
    return model == 0 ? 1 : (model == 2 ? 4 : 3);
}
- (NSString *)localizedName {
    return spaceName;
}
- (void)dealloc {
    [spaceName release];
    [super dealloc];
}
@end
@implementation NSColor (SnowColorSpace)
- (id)colorSpace {
    return [NSColorSpace spaceWithName:[self colorSpaceName]];
}
- (id)colorUsingColorSpace:(NSColorSpace *)space {
    return [self colorUsingColorSpaceName:space->spaceName];
}
@end

@interface NSGradient : NSObject {
    NSArray *snowColors;
    float *snowLocations;
}
- initWithColors:(NSArray *)colors
     atLocations:(const float *)locations
      colorSpace:(NSColorSpace *)space;
- (NSColor *)interpolatedColorAtLocation:(float)location;
- (void)drawInRect:(NSRect)rect angle:(float)angle;
@end
@implementation NSGradient
- initWithColors:(NSArray *)colors
     atLocations:(const float *)locations
      colorSpace:(NSColorSpace *)space {
    unsigned i, count = [colors count];
    self = [super init];
    if (count < 2) {
        [self release];
        return nil;
    }
    snowColors = [colors snowCopy];
    snowLocations = malloc(count * sizeof(float));
    if (!snowLocations) {
        [self release];
        return nil;
    }
    for (i = 0; i < count; i++) {
        snowLocations[i] = locations ? locations[i] : (float)i / (count - 1);
        if (snowLocations[i] < 0 || snowLocations[i] > 1 ||
            (i && snowLocations[i] < snowLocations[i - 1])) {
            [self release];
            return nil;
        }
    }
    return self;
}
- initWithColors:(NSArray *)colors {
    return [self initWithColors:colors atLocations:NULL colorSpace:nil];
}
- initWithStartingColor:(NSColor *)start endingColor:(NSColor *)end {
    return [self initWithColors:[NSArray arrayWithObjects:start, end, nil]];
}
- (unsigned)numberOfColorStops {
    return [snowColors count];
}
- (id)colorSpace {
    return [NSColorSpace genericRGBColorSpace];
}
- (void)getColor:(NSColor **)color location:(float *)location atIndex:(unsigned)index {
    NSColor *value = [snowColors objectAtIndex:index];
    if (color)
        *color = value;
    if (location)
        *location = snowLocations[index];
}
- (NSColor *)interpolatedColorAtLocation:(float)location {
    unsigned index = 1, count = [snowColors count];
    float a[4], b[4], fraction;
    if (location <= snowLocations[0])
        return [snowColors objectAtIndex:0];
    if (location >= snowLocations[count - 1])
        return [snowColors lastObject];
    while (index < count - 1 && location > snowLocations[index])
        index++;
    [[[snowColors objectAtIndex:index - 1] colorUsingColorSpaceName:NSCalibratedRGBColorSpace]
        getRed:a
         green:a + 1
          blue:a + 2
         alpha:a + 3];
    [[[snowColors objectAtIndex:index] colorUsingColorSpaceName:NSCalibratedRGBColorSpace]
        getRed:b
         green:b + 1
          blue:b + 2
         alpha:b + 3];
    fraction =
        (location - snowLocations[index - 1]) / (snowLocations[index] - snowLocations[index - 1]);
    return [NSColor colorWithCalibratedRed:a[0] + (b[0] - a[0]) * fraction
                                     green:a[1] + (b[1] - a[1]) * fraction
                                      blue:a[2] + (b[2] - a[2]) * fraction
                                     alpha:a[3] + (b[3] - a[3]) * fraction];
}
- (void)drawInRect:(NSRect)rect angle:(float)angle {
    float radians = angle * 3.14159265358979323846 / 180, c = cos(radians), s = sin(radians);
    float minx = 0, maxx = 0, miny = 0, maxy = 0;
    unsigned i, steps;
    if (rect.size.width <= 0 || rect.size.height <= 0)
        return;
    for (i = 0; i < 4; i++) {
        float x = (i & 1) ? NSMaxX(rect) : NSMinX(rect), y = (i & 2) ? NSMaxY(rect) : NSMinY(rect);
        float u = c * x + s * y, v = -s * x + c * y;
        if (!i || u < minx)
            minx = u;
        if (!i || u > maxx)
            maxx = u;
        if (!i || v < miny)
            miny = v;
        if (!i || v > maxy)
            maxy = v;
    }
    if (maxx <= minx)
        return;
    steps = ceil(maxx - minx);
    if (steps > 512)
        steps = 512;
    if (!steps)
        steps = 1;
    PSgsave();
    NSRectClip(rect);
    PSrotate(angle);
    for (i = 0; i < steps; i++) {
        snowCompositeColor(
            [self interpolatedColorAtLocation:steps == 1 ? 0 : (float)i / (steps - 1)],
            NSMakeRect(minx + (maxx - minx) * i / steps, miny, (maxx - minx) / steps, maxy - miny));
    }
    PSgrestore();
}
- (void)drawInBezierPath:(NSBezierPath *)path angle:(float)angle {
    PSgsave();
    [path addClip];
    [self drawInRect:[path bounds] angle:angle];
    PSgrestore();
}
- (void)drawInRect:(NSRect)rect relativeCenterPosition:(NSPoint)relative {
    NSPoint start, end;
    float radius = 0;
    unsigned i, steps;
    if (rect.size.width <= 0 || rect.size.height <= 0)
        return;
    if (relative.x < -1 || relative.x > 1 || relative.y < -1 || relative.y > 1)
        [NSException raise:NSInvalidArgumentException
                    format:@"Gradient center must lie within the rectangle"];
    start = NSMakePoint(NSMidX(rect), NSMidY(rect));
    end = NSMakePoint(start.x + relative.x * rect.size.width / 2,
                      start.y + relative.y * rect.size.height / 2);
    for (i = 0; i < 4; i++) {
        float x = ((i & 1) ? NSMaxX(rect) : NSMinX(rect)) - end.x;
        float y = ((i & 2) ? NSMaxY(rect) : NSMinY(rect)) - end.y;
        float distance = sqrt(x * x + y * y);
        if (distance > radius)
            radius = distance;
    }
    steps = ceil(radius * 2);
    if (steps > 512)
        steps = 512;
    if (!steps)
        steps = 1;
    /* The start is a point at the rectangle's center; the end circle is
     * offset and encloses all four corners. Paint nested circles outside in. */
    PSgsave();
    NSRectClip(rect);
    for (i = steps; i > 0; i--) {
        float t = (float)i / steps;
        float inner = (float)(i - 1) / steps;
        PSgsave();
        PSnewpath();
        PSarc(start.x + (end.x - start.x) * t, start.y + (end.y - start.y) * t, radius * t, 0, 360);
        PSclosepath();
        if (i > 1) {
            /* Paint each annulus once so translucent colors do not accumulate. */
            PSmoveto(start.x + (end.x - start.x) * inner + radius * inner,
                     start.y + (end.y - start.y) * inner);
            PSarc(start.x + (end.x - start.x) * inner, start.y + (end.y - start.y) * inner,
                  radius * inner, 0, 360);
            PSclosepath();
        }
        PSeoclip();
        snowCompositeColor([self interpolatedColorAtLocation:inner], rect);
        PSgrestore();
    }
    PSgrestore();
}
- (void)drawInBezierPath:(NSBezierPath *)path relativeCenterPosition:(NSPoint)relative {
    PSgsave();
    [path addClip];
    [self drawInRect:[path bounds] relativeCenterPosition:relative];
    PSgrestore();
}
- (void)dealloc {
    [snowColors release];
    free(snowLocations);
    [super dealloc];
}
@end
