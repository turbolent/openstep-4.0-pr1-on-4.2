/* Appended after graphics.m and atsui.m; run in the desktop namespace. */
#include <stddef.h>

static unsigned checks, failures;
static void check(int passed, const char *name) {
    checks++;
    if (!passed)
        failures++;
    printf("%s %s\n", passed ? "PASS" : "FAIL", name);
}

static void checkBounds(TigerATSULayout *layout, unsigned start, unsigned length,
                        float baseX, float left, float right, const char *name) {
    TigerTrapezoid bounds;
    unsigned actual = 0;
    ATSUGetGlyphBounds(layout, X2Fix(baseX), 0, start, length, 0, 1, &bounds, &actual);
    check(actual == 1 && bounds.upperLeft.x == X2Fix(left) &&
              bounds.lowerLeft.x == X2Fix(left) && bounds.upperRight.x == X2Fix(right) &&
              bounds.lowerRight.x == X2Fix(right), name);
}

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    TigerATSULayout *layout;
    TigerATSUStyle *normal, *wide;
    unichar text[] = {'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'};
    unichar combining[] = {'A', 0x0301, 'B', 'C'};
    unsigned primary = 0, secondary;
    unsigned char leading;
    [NSApplication sharedApplication];
    ATSUCreateTextLayout(&layout);
    ATSUCreateStyle(&normal);
    ATSUCreateStyle(&wide);
    normal->width = 8;
    wide->width = 12;
    ATSUSetTextPointerLocation(layout, text, 0, 8, 8);
    ATSUSetRunStyle(layout, normal, 0, 8);
    /* Terminal reads the left edge at byte 24 and the right edge at byte 8. */
    check(sizeof(TigerTrapezoid) == 32 && offsetof(TigerTrapezoid, lowerLeft) == 24 &&
              offsetof(TigerTrapezoid, upperRight) == 8, "Tiger glyph-bounds layout");
    checkBounds(layout, 0, 8, 0, 0, 64, "whole line");
    checkBounds(layout, 2, 1, 0, 16, 24, "single character inside line");
    checkBounds(layout, 2, 4, 0, 16, 48, "drag right keeps the left edge anchored");
    checkBounds(layout, 1, 5, 0, 8, 48, "drag left keeps the right edge anchored");
    checkBounds(layout, 2, 4, 20, 36, 68, "line origin and selection offset both apply");
    ATSUPositionToOffset(layout, X2Fix(48), 0, &primary, &leading, &secondary);
    check(primary == 6 && secondary == 6, "hit testing agrees with highlight edge");
    ATSUSetRunStyle(layout, wide, 0, 2);
    checkBounds(layout, 2, 4, 0, 24, 56, "prefix uses its own style advances");
    ATSUSetTextPointerLocation(layout, combining, 0, 4, 4);
    ATSUSetRunStyle(layout, normal, 0, 4);
    checkBounds(layout, 2, 1, 0, 8, 16, "combining mark does not shift selection");
    ATSUDisposeTextLayout(layout);
    ATSUDisposeStyle(normal);
    ATSUDisposeStyle(wide);
    [pool release];
    printf("%u checks, %u failures\n", checks, failures);
    return failures ? 1 : 0;
}
