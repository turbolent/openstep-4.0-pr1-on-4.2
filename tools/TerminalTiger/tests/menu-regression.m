/* Include after appkit.m in a diagnostic build, and call after launch.
 * Each native menu matrix receives mouseDown:, with mouse-up queued in NSApp. */
@interface NSMenu (TigerMenuTest)
- (NSMatrix *)itemMatrix;
@end

static IMP tigerTestNativeMenuTrack;
static unsigned tigerTestMenuTracks;
static BOOL tigerTestMenuTrack(id item, SEL selector, NSEvent *event, NSRect rect, NSView *view,
                               BOOL untilUp) {
    BOOL result;
    tigerTestMenuTracks++;
    result = ((BOOL(*)(id, SEL, id, NSRect, id, BOOL))tigerTestNativeMenuTrack)(
        item, selector, event, rect, view, untilUp);
    fprintf(stderr, "TEST native menu tracking returned %s\n", [[item title] cString]);
    return result;
}
static unsigned tigerTestMenuTree(NSMenu *menu) {
    NSArray *items = [menu itemArray];
    unsigned i, count = 1;
    [menu update];
    [menu sizeToFit];
    for (i = 0; i < [items count]; i++) {
        id item = [items objectAtIndex:i];
        if ([item hasSubmenu])
            count += tigerTestMenuTree([item target]);
    }
    return count;
}
@interface TigerMenuTest : NSObject {
    unsigned index;
}
- (void)click:(NSTimer *)timer;
@end
@implementation TigerMenuTest
- (void)click:(NSTimer *)timer {
    NSMenu *menu = [NSApp mainMenu];
    NSMatrix *matrix = [menu itemMatrix];
    NSWindow *window = [matrix window];
    NSRect rect;
    NSPoint point;
    NSEvent *down, *up;
    if (index >= [menu numberOfItems]) {
        fprintf(stderr, "TEST menu clicks completed=%u nativeTracking=%u\n", index,
                tigerTestMenuTracks);
        [timer invalidate];
        return;
    }
    rect = [matrix cellFrameAtRow:index column:0];
    point = [matrix convertPoint:NSMakePoint(NSMidX(rect), NSMidY(rect)) toView:nil];
    fprintf(stderr, "TEST menu click %u %s\n", index, [[[menu itemAtIndex:index] title] cString]);
    down = [NSEvent mouseEventWithType:NSLeftMouseDown
                              location:point
                         modifierFlags:0
                             timestamp:0
                          windowNumber:[window windowNumber]
                               context:[NSDPSContext currentContext]
                           eventNumber:index * 2
                            clickCount:1
                              pressure:1];
    up = [NSEvent mouseEventWithType:NSLeftMouseUp
                            location:point
                       modifierFlags:0
                           timestamp:0
                        windowNumber:[window windowNumber]
                             context:[NSDPSContext currentContext]
                         eventNumber:index * 2 + 1
                          clickCount:1
                            pressure:0];
    index++;
    [NSApp postEvent:up atStart:YES];
    [matrix mouseDown:down];
}
@end
static void TigerTestMenus(void) {
    NSMenu *parent = [[NSMenu alloc] initWithTitle:@"Ownership test"];
    id item = [parent addItemWithTitle:@"Child" action:NULL keyEquivalent:@""];
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSMenu *child = [[[NSMenu alloc] initWithTitle:@"Retained child"] autorelease];
    NSTimer *timer;
    Method method;
    NSValue *key = [[NSValue valueWithPointer:parent] retain];
    [parent setSubmenu:child forItem:item];
    [pool release];
    fprintf(stderr, "TEST submenu survives autorelease=%d\n",
            [[[item target] title] isEqual:@"Retained child"]);
    [parent setSubmenu:nil forItem:item];
    fprintf(stderr, "TEST submenu detach=%d\n",
            ![item hasSubmenu] && [[tigerMenuChildren objectForKey:key] count] == 0);
    child = [[[NSMenu alloc] initWithTitle:@"Replacement"] autorelease];
    [parent setSubmenu:child forItem:item];
    [parent removeItem:item];
    fprintf(stderr, "TEST removed submenu ownership cleared=%d\n",
            [[tigerMenuChildren objectForKey:key] count] == 0);
    [parent release];
    fprintf(stderr, "TEST parent ownership cleared=%d\n",
            [tigerMenuChildren objectForKey:key] == nil);
    [key release];
    fprintf(stderr, "TEST menu tree updated=%u\n", tigerTestMenuTree([NSApp mainMenu]));
    method = class_getInstanceMethod([[[NSApp mainMenu] itemAtIndex:0] class],
                                     @selector(trackMouse:inRect:ofView:untilMouseUp:));
    tigerTestNativeMenuTrack = method->method_imp;
    method->method_imp = (IMP)tigerTestMenuTrack;
    [NSApp activateIgnoringOtherApps:YES];
    timer = [NSTimer timerWithTimeInterval:0.4
                                    target:[[[TigerMenuTest alloc] init] autorelease]
                                  selector:@selector(click:)
                                  userInfo:nil
                                   repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSEventTrackingRunLoopMode];
}
