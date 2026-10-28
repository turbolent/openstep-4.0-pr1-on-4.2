/* Tracking areas use OPENSTEP's mouse-entered/exited tracking rectangles. */
@interface NSTrackingArea : NSObject {
  @public
    NSRect snowRect;
    unsigned snowOptions;
    id snowOwner;
    NSDictionary *snowInfo;
    NSView *snowView;
    int snowTag;
}
- initWithRect:(NSRect)rect options:(unsigned)options owner:(id)owner userInfo:(NSDictionary *)info;
- (NSRect)rect;
- (unsigned)options;
- (id)owner;
- (NSDictionary *)userInfo;
@end
@implementation NSTrackingArea
- initWithRect:(NSRect)rect
       options:(unsigned)options
         owner:(id)owner
      userInfo:(NSDictionary *)info {
    self = [super init];
    snowRect = rect;
    snowOptions = options;
    snowOwner = owner;
    snowInfo = [info snowCopy];
    return self;
}
- (NSRect)rect {
    return snowRect;
}
- (unsigned)options {
    return snowOptions;
}
- (id)owner {
    return snowOwner;
}
- (NSDictionary *)userInfo {
    return snowInfo;
}
- (void)dealloc {
    [snowInfo release];
    [super dealloc];
}
@end
static NSMutableDictionary *snowTrackingAreas;
@implementation NSView (SnowTrackingAreas)
- (void)addTrackingArea:(NSTrackingArea *)area {
    NSValue *key = [NSValue valueWithPointer:self];
    NSMutableArray *areas;
    if (!snowTrackingAreas)
        snowTrackingAreas = [[NSMutableDictionary alloc] init];
    areas = [snowTrackingAreas objectForKey:key];
    if (!areas) {
        areas = [NSMutableArray array];
        [snowTrackingAreas setObject:areas forKey:key];
    }
    if ([areas containsObject:area])
        return;
    area->snowView = self;
    if (area->snowOptions & 1)
        area->snowTag =
            [self addTrackingRect:(area->snowOptions & 0x200) ? [self bounds] : area->snowRect
                            owner:area->snowOwner
                         userData:area
                     assumeInside:(area->snowOptions & 0x100) != 0];
    if (area->snowOptions & 2)
        [[self window] setAcceptsMouseMovedEvents:YES];
    [areas addObject:area];
}
- (void)removeTrackingArea:(NSTrackingArea *)area {
    NSValue *key = [NSValue valueWithPointer:self];
    NSMutableArray *areas = [snowTrackingAreas objectForKey:key];
    if (![areas containsObject:area])
        return;
    if (area->snowTag)
        [self removeTrackingRect:area->snowTag];
    area->snowView = nil;
    area->snowTag = 0;
    [areas removeObjectIdenticalTo:area];
    if (![areas count])
        [snowTrackingAreas removeObjectForKey:key];
}
- (NSArray *)trackingAreas {
    return
        [NSArray arrayWithArray:[snowTrackingAreas objectForKey:[NSValue valueWithPointer:self]]];
}
- (void)updateTrackingAreas {
}
@end
