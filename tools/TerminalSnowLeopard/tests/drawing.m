/* Explicit Quartz fill survives native drawing and graphics-state restores. */
#import <AppKit/AppKit.h>
#include <assert.h>
#include <stdio.h>
#ifndef SNOW_DRAWING_TEST_COMBINED
@interface NSGraphicsContext : NSObject
+ (void)saveGraphicsState;
+ (void)restoreGraphicsState;
@end
#endif
@interface NSColor (SnowDrawingTest)
- (void)setFill;
- (void)setStroke;
@end
extern void CGContextSetFont(void *, NSFont *);
extern void CGContextSetFontSize(void *, float);
extern void CGContextSetTextPosition(void *, float, float);
extern void CGContextShowGlyphsWithAdvances(void *, const unsigned short *, const NSSize *,
                                            unsigned);
static void drawSample(float x) {
    unsigned short glyphs[] = {'C', 'O', 'L', 'O', 'R'};
    NSSize advances[5];
    unsigned i;
    for (i = 0; i < 5; i++)
        advances[i] = NSMakeSize(12, 0);
    /* Reproduce AppKit changing the current DPS paint during font layout. */
    [[NSColor blackColor] set];
    CGContextSetTextPosition(NULL, x, 30);
    CGContextShowGlyphsWithAdvances(NULL, glyphs, advances, 5);
}
int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSImage *image;
    NSData *data;
    NSBitmapImageRep *pixels;
    BOOL saved;
    unsigned char *bytes;
    unsigned sample, x, y, counts[3] = {0, 0, 0};
    int stride, samples;
    [NSApplication sharedApplication];
    image = [[NSImage alloc] initWithSize:NSMakeSize(250, 60)];
    [image lockFocus];
    [[NSColor whiteColor] set];
    NSRectFill(NSMakeRect(0, 0, 250, 60));
    CGContextSetFont(NULL, [NSFont fontWithName:@"Courier" size:20]);
    CGContextSetFontSize(NULL, 20);
    [[NSColor redColor] setFill];
    [[NSColor blueColor] setStroke];
    drawSample(10);
    [NSGraphicsContext saveGraphicsState];
    [[NSColor greenColor] setFill];
    drawSample(90);
    [NSGraphicsContext restoreGraphicsState];
    drawSample(170);
    [image unlockFocus];
    data = [image TIFFRepresentation];
    saved = [data writeToFile:@"test-drawing.tiff" atomically:YES];
    pixels = [NSBitmapImageRep imageRepWithData:data];
    assert(pixels && ![pixels isPlanar] && [pixels bitsPerSample] == 8);
    assert([[pixels colorSpaceName] isEqual:NSDeviceRGBColorSpace] ||
           [[pixels colorSpaceName] isEqual:NSCalibratedRGBColorSpace]);
    assert([pixels pixelsWide] == 250 && [pixels pixelsHigh] == 60);
    bytes = (unsigned char *)[pixels bitmapData];
    stride = [pixels bytesPerRow];
    samples = [pixels samplesPerPixel];
    assert(bytes && samples >= 3);
    for (sample = 0; sample < 3; sample++)
        for (y = 0; y < 60; y++)
            for (x = 8 + sample * 80; x < 72 + sample * 80; x++) {
                unsigned char *pixel = bytes + y * stride + x * samples;
                if (sample == 1 ? pixel[1] > 180 && pixel[0] < 80 && pixel[2] < 80
                                : pixel[0] > 180 && pixel[1] < 80 && pixel[2] < 80)
                    counts[sample]++;
            }
    assert(counts[0] > 50 && counts[1] > 50 && counts[2] > 50);
    puts("PASS explicit text fill, independent stroke, and restored graphics state");
    [image release];
    [pool release];
    return saved ? 0 : 1;
}
