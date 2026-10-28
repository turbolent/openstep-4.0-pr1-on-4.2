/* Cocoa paths replayed through Display PostScript. */
typedef struct {
    unsigned kind;
    NSPoint points[3];
} SnowPathElement;
static float snowDefaultPathWidth = 1;
@interface NSBezierPath : NSObject <NSCopying> {
    NSMutableData *snowElements;
    float snowLineWidth;
    int snowWindingRule;
}
+ (id)bezierPath;
- (void)moveToPoint:(NSPoint)point;
- (void)lineToPoint:(NSPoint)point;
- (void)curveToPoint:(NSPoint)end controlPoint1:(NSPoint)first controlPoint2:(NSPoint)second;
- (void)closePath;
- (void)appendBezierPathWithRect:(NSRect)rect;
- (void)stroke;
- (void)fill;
- (NSRect)bounds;
@end
static void snowExpandPathBounds(NSPoint point, NSPoint *minimum, NSPoint *maximum, BOOL *empty) {
    if (*empty) {
        *minimum = *maximum = point;
        *empty = NO;
        return;
    }
    if (point.x < minimum->x)
        minimum->x = point.x;
    if (point.y < minimum->y)
        minimum->y = point.y;
    if (point.x > maximum->x)
        maximum->x = point.x;
    if (point.y > maximum->y)
        maximum->y = point.y;
}
static NSPoint snowCubicPoint(NSPoint a, NSPoint b, NSPoint c, NSPoint d, double t) {
    double u = 1 - t;
    return NSMakePoint(
        u * u * u * a.x + 3 * u * u * t * b.x + 3 * u * t * t * c.x + t * t * t * d.x,
        u * u * u * a.y + 3 * u * u * t * b.y + 3 * u * t * t * c.y + t * t * t * d.y);
}
@implementation NSBezierPath
+ (void)setDefaultLineWidth:(float)width {
    snowDefaultPathWidth = width;
}
+ (float)defaultLineWidth {
    return snowDefaultPathWidth;
}
+ (id)bezierPath {
    return [[[self alloc] init] autorelease];
}
+ (id)bezierPathWithRect:(NSRect)rect {
    id path = [self bezierPath];
    [path appendBezierPathWithRect:rect];
    return path;
}
+ (void)fillRect:(NSRect)rect {
    NSRectFill(rect);
}
+ (void)strokeRect:(NSRect)rect {
    [[self bezierPathWithRect:rect] stroke];
}
+ (void)clipRect:(NSRect)rect {
    NSRectClip(rect);
}
+ (void)strokeLineFromPoint:(NSPoint)start toPoint:(NSPoint)end {
    id path = [self bezierPath];
    [path moveToPoint:start];
    [path lineToPoint:end];
    [path stroke];
}
- init {
    self = [super init];
    snowElements = [[NSMutableData alloc] init];
    snowLineWidth = snowDefaultPathWidth;
    return self;
}
- (void)setLineWidth:(float)width {
    snowLineWidth = width;
}
- (float)lineWidth {
    return snowLineWidth;
}
- (void)setWindingRule:(int)rule {
    snowWindingRule = rule;
}
- (int)windingRule {
    return snowWindingRule;
}
- (void)moveToPoint:(NSPoint)point {
    SnowPathElement e;
    memset(&e, 0, sizeof(e));
    e.points[0] = point;
    [snowElements appendBytes:&e length:sizeof(e)];
}
- (void)lineToPoint:(NSPoint)point {
    SnowPathElement e;
    memset(&e, 0, sizeof(e));
    e.kind = 1;
    e.points[0] = point;
    [snowElements appendBytes:&e length:sizeof(e)];
}
- (void)curveToPoint:(NSPoint)end controlPoint1:(NSPoint)first controlPoint2:(NSPoint)second {
    SnowPathElement e;
    e.kind = 2;
    e.points[0] = first;
    e.points[1] = second;
    e.points[2] = end;
    [snowElements appendBytes:&e length:sizeof(e)];
}
- (void)closePath {
    SnowPathElement e;
    memset(&e, 0, sizeof(e));
    e.kind = 3;
    [snowElements appendBytes:&e length:sizeof(e)];
}
- (void)appendBezierPathWithRect:(NSRect)rect {
    [self moveToPoint:rect.origin];
    [self lineToPoint:NSMakePoint(NSMaxX(rect), NSMinY(rect))];
    [self lineToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect))];
    [self lineToPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect))];
    [self closePath];
}
- (void)appendBezierPath:(NSBezierPath *)path {
    [snowElements appendData:path->snowElements];
}
- (void)removeAllPoints {
    [snowElements setLength:0];
}
- (BOOL)isEmpty {
    return [snowElements length] == 0;
}
- (NSRect)bounds {
    const SnowPathElement *elements = [snowElements bytes];
    unsigned i, count = [snowElements length] / sizeof(*elements);
    NSPoint minimum = NSZeroPoint, maximum = NSZeroPoint, last = NSZeroPoint, start = NSZeroPoint;
    BOOL empty = YES;
    for (i = 0; i < count; i++) {
        const SnowPathElement *e = elements + i;
        if (e->kind == 3)
            last = start;
        else if (e->kind != 2) {
            last = e->points[0];
            if (e->kind == 0)
                start = last;
        } else {
            unsigned axis;
            for (axis = 0; axis < 2; axis++) {
                double p0 = axis ? last.y : last.x, p1 = axis ? e->points[0].y : e->points[0].x;
                double p2 = axis ? e->points[1].y : e->points[1].x,
                       p3 = axis ? e->points[2].y : e->points[2].x;
                double a = -p0 + 3 * p1 - 3 * p2 + p3, b = 2 * (p0 - 2 * p1 + p2), c = p1 - p0,
                       roots[2];
                unsigned n = 0, j;
                if (fabs(a) < 1e-12) {
                    if (fabs(b) > 1e-12)
                        roots[n++] = -c / b;
                } else {
                    double discriminant = b * b - 4 * a * c;
                    if (discriminant >= 0) {
                        double root = sqrt(discriminant);
                        roots[n++] = (-b + root) / (2 * a);
                        roots[n++] = (-b - root) / (2 * a);
                    }
                }
                for (j = 0; j < n; j++)
                    if (roots[j] > 0 && roots[j] < 1)
                        snowExpandPathBounds(snowCubicPoint(last, e->points[0], e->points[1],
                                                            e->points[2], roots[j]),
                                             &minimum, &maximum, &empty);
            }
            last = e->points[2];
        }
        snowExpandPathBounds(last, &minimum, &maximum, &empty);
    }
    return NSMakeRect(minimum.x, minimum.y, maximum.x - minimum.x, maximum.y - minimum.y);
}
- (void)snowReplay {
    const SnowPathElement *elements = [snowElements bytes];
    unsigned i, count = [snowElements length] / sizeof(*elements);
    PSnewpath();
    for (i = 0; i < count; i++) {
        const NSPoint *p = elements[i].points;
        switch (elements[i].kind) {
        case 0:
            PSmoveto(p[0].x, p[0].y);
            break;
        case 1:
            PSlineto(p[0].x, p[0].y);
            break;
        case 2:
            PScurveto(p[0].x, p[0].y, p[1].x, p[1].y, p[2].x, p[2].y);
            break;
        case 3:
            PSclosepath();
            break;
        }
    }
}
- (void)stroke {
    PSgsave();
    [self snowReplay];
    PSsetlinewidth(snowLineWidth);
    PSstroke();
    PSgrestore();
}
- (void)fill {
    PSgsave();
    [self snowReplay];
    if (snowWindingRule)
        PSeofill();
    else
        PSfill();
    PSgrestore();
}
- (void)addClip {
    [self snowReplay];
    if (snowWindingRule)
        PSeoclip();
    else
        PSclip();
    PSnewpath();
}
- (void)setClip {
    PSinitclip();
    [self addClip];
}
- copyWithZone:(NSZone *)zone {
    NSBezierPath *path = [[[self class] allocWithZone:zone] init];
    [path->snowElements appendData:snowElements];
    path->snowLineWidth = snowLineWidth;
    path->snowWindingRule = snowWindingRule;
    return path;
}
- (void)dealloc {
    [snowElements release];
    [super dealloc];
}
@end
