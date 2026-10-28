/* Preference toolbar metadata; native tab buttons present its pane choices. */
@interface NSToolbarItem : NSObject {
    NSString *snowIdentifier, *snowLabel;
    id snowTarget;
    SEL snowAction;
    int snowTag;
    BOOL snowEnabled;
}
- initWithItemIdentifier:(NSString *)identifier;
@end
@implementation NSToolbarItem
- initWithItemIdentifier:(NSString *)identifier {
    self = [super init];
    snowIdentifier = [identifier snowCopy];
    snowEnabled = YES;
    return self;
}
- (NSString *)itemIdentifier {
    return snowIdentifier;
}
- (NSString *)label {
    return snowLabel;
}
- (void)setLabel:(NSString *)value {
    [value retain];
    [snowLabel release];
    snowLabel = value;
}
- (NSString *)paletteLabel {
    return snowLabel;
}
- (id)target {
    return snowTarget;
}
- (void)setTarget:(id)target {
    snowTarget = target;
}
- (SEL)action {
    return snowAction;
}
- (void)setAction:(SEL)action {
    snowAction = action;
}
- (int)tag {
    return snowTag;
}
- (void)setTag:(int)tag {
    snowTag = tag;
}
- (BOOL)isEnabled {
    return snowEnabled;
}
- (void)setEnabled:(BOOL)enabled {
    snowEnabled = enabled;
}
- (void)dealloc {
    [snowIdentifier release];
    [snowLabel release];
    [super dealloc];
}
@end
@interface NSToolbar : NSObject {
    NSString *snowIdentifier, *snowSelection;
    NSMutableArray *snowItems;
    id snowDelegate;
}
- initWithIdentifier:(NSString *)identifier;
- (void)setItems:(NSArray *)items;
@end
@implementation NSToolbar
- initWithIdentifier:(NSString *)identifier {
    self = [super init];
    snowIdentifier = [identifier snowCopy];
    snowItems = [[NSMutableArray alloc] init];
    return self;
}
- (NSString *)identifier {
    return snowIdentifier;
}
- (NSArray *)items {
    return snowItems;
}
- (NSArray *)visibleItems {
    return snowItems;
}
- (void)setItems:(NSArray *)items {
    [snowItems setArray:items];
    if ([items count])
        [self setSelectedItemIdentifier:[[items objectAtIndex:0] itemIdentifier]];
}
- (NSString *)selectedItemIdentifier {
    return snowSelection;
}
- (void)setSelectedItemIdentifier:(NSString *)identifier {
    [identifier retain];
    [snowSelection release];
    snowSelection = identifier;
}
- (void)setDelegate:(id)delegate {
    snowDelegate = delegate;
}
- (id)delegate {
    return snowDelegate;
}
- (void)dealloc {
    [snowIdentifier release];
    [snowSelection release];
    [snowItems release];
    [super dealloc];
}
@end
static NSMutableDictionary *snowWindowToolbars;
@implementation NSWindow (SnowToolbar)
- (void)setToolbar:(id)toolbar {
    NSValue *key = [NSValue valueWithPointer:self];
    if (!snowWindowToolbars)
        snowWindowToolbars = [[NSMutableDictionary alloc] init];
    if (toolbar)
        [snowWindowToolbars setObject:toolbar forKey:key];
    else
        [snowWindowToolbars removeObjectForKey:key];
}
- (id)toolbar {
    return [snowWindowToolbars objectForKey:[NSValue valueWithPointer:self]];
}
@end
