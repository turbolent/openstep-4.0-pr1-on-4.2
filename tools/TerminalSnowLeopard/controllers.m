/* Cocoa controllers retain the historical layout expected by stock subclasses. */
static NSMutableDictionary *snowControllerEditorLists;
static NSMutableArray *snowEditors(id controller, BOOL create) {
    NSValue *key = [NSValue valueWithPointer:controller];
    NSMutableArray *editors = [snowControllerEditorLists objectForKey:key];
    if (!editors && create) {
        if (!snowControllerEditorLists)
            snowControllerEditorLists = [[NSMutableDictionary alloc] init];
        editors = [NSMutableArray array];
        [snowControllerEditorLists setObject:editors forKey:key];
    }
    return editors;
}
@interface NSObject (SnowEditorCallbacks)
- (BOOL)commitEditing;
- (void)discardEditing;
@end
@interface NSObjectController : NSObject {
  @protected
    id snowContent;
    Class snowObjectClass;
    BOOL snowEditable;
}
- (id)content;
- (void)setContent:(id)content;
- (id)newObject;
@end
@implementation NSObjectController
- init {
    self = [super init];
    snowEditable = YES;
    snowObjectClass = [NSMutableDictionary class];
    return self;
}
- initWithContent:(id)value {
    self = [self init];
    [self setContent:value];
    return self;
}
- (id)content {
    return snowContent;
}
- (id)contentObject {
    return [self content];
}
- (void)setContentObject:(id)value {
    [self setContent:value];
}
- (void)setContent:(id)value {
    [value retain];
    [snowContent release];
    snowContent = value;
}
- (id)selection {
    return snowContent;
}
- (NSArray *)selectedObjects {
    return snowContent ? [NSArray arrayWithObject:snowContent] : [NSArray array];
}
- (void)setObjectClass:(Class)cls {
    snowObjectClass = cls;
}
- (Class)objectClass {
    return snowObjectClass;
}
- (id)newObject {
    return [[snowObjectClass alloc] init];
}
- (BOOL)canAdd {
    return snowEditable;
}
- (BOOL)canRemove {
    return snowEditable && snowContent != nil;
}
- (BOOL)isEditable {
    return snowEditable;
}
- (void)setEditable:(BOOL)value {
    snowEditable = value;
}
- (BOOL)commitEditing {
    NSArray *editors = [snowEditors(self, NO) snowCopy];
    unsigned i;
    BOOL committed = YES;
    for (i = 0; i < [editors count]; i++) {
        id editor = [[editors objectAtIndex:i] nonretainedObjectValue];
        if ([editor respondsToSelector:@selector(commitEditing)] && ![editor commitEditing])
            committed = NO;
    }
    [editors release];
    return committed;
}
- (BOOL)isEditing {
    return [snowEditors(self, NO) count] != 0;
}
- (void)objectDidBeginEditing:(id)editor {
    NSValue *value = [NSValue valueWithNonretainedObject:editor];
    NSMutableArray *editors = snowEditors(self, YES);
    if (![editors containsObject:value])
        [editors addObject:value];
}
- (void)objectDidEndEditing:(id)editor {
    [snowEditors(self, NO) removeObject:[NSValue valueWithNonretainedObject:editor]];
}
- (void)discardEditing {
    NSArray *editors = [snowEditors(self, NO) snowCopy];
    unsigned i;
    for (i = 0; i < [editors count]; i++) {
        id editor = [[editors objectAtIndex:i] nonretainedObjectValue];
        if ([editor respondsToSelector:@selector(discardEditing)])
            [editor discardEditing];
    }
    [editors release];
}
- (void)dealloc {
    [snowControllerEditorLists removeObjectForKey:[NSValue valueWithPointer:self]];
    [snowContent release];
    [super dealloc];
}
@end

@interface NSArrayController : NSObjectController {
    NSMutableArray *snowArranged;
    id snowIndexes;
    NSArray *snowSort;
    id snowFilter;
    BOOL snowAvoidsEmpty, snowSelectsInserted, snowPreservesSelection;
    unsigned char snowReserved[96]; /* sizeof(NSArrayController) == 132 */
}
- (NSArray *)arrangedObjects;
- (void)rearrangeObjects;
- (void)setSelectionIndex:(unsigned)index;
- (void)setSelectionIndexes:(id)indexes;
- (unsigned)selectionIndex;
- (void)addObject:(id)object;
- (void)removeObject:(id)object;
@end
@implementation NSArrayController
- init {
    self = [super init];
    snowSelectsInserted = YES;
    snowArranged = [[NSMutableArray alloc] init];
    snowIndexes = [[NSClassFromString(@"NSMutableIndexSet") alloc] init];
    return self;
}
- (void)setContent:(id)value {
    if (value && ![value isKindOfClass:[NSArray class]])
        [NSException raise:NSInvalidArgumentException
                    format:@"Array controller content must be an array"];
    [super setContent:value];
    [self rearrangeObjects];
    SnowCommitBindingTarget(self, @"contentArray", snowContent);
}
- (void)setContentArray:(NSArray *)value {
    [self setContent:value];
}
- (NSArray *)contentArray {
    return snowContent;
}
- (NSArray *)arrangedObjects {
    return snowArranged;
}
- (void)rearrangeObjects {
    unsigned i;
    NSArray *previous = [self selectedObjects];
    [previous retain];
    [snowArranged removeAllObjects];
    for (i = 0; i < [snowContent count]; i++) {
        id object = [snowContent objectAtIndex:i];
        if (!snowFilter || [snowFilter evaluateWithObject:object])
            [snowArranged addObject:object];
    }
    if ([snowSort count])
        [snowArranged sortUsingDescriptors:snowSort];
    [snowIndexes removeAllIndexes];
    if (snowPreservesSelection)
        for (i = 0; i < [previous count]; i++) {
            unsigned index = [snowArranged indexOfObjectIdenticalTo:[previous objectAtIndex:i]];
            if (index != NSNotFound)
                [snowIndexes addIndex:index];
        }
    if (![snowIndexes count] && snowAvoidsEmpty && [snowArranged count])
        [snowIndexes addIndex:0];
    [previous release];
    [self didChangeValueForKey:@"arrangedObjects"];
    [self didChangeValueForKey:@"selection"];
}
- (void)setSortDescriptors:(NSArray *)value {
    [value retain];
    [snowSort release];
    snowSort = value;
    [self rearrangeObjects];
}
- (NSArray *)sortDescriptors {
    return snowSort;
}
- (void)setFilterPredicate:(id)value {
    [value retain];
    [snowFilter release];
    snowFilter = value;
    [self rearrangeObjects];
}
- (id)filterPredicate {
    return snowFilter;
}
- (id)selectionIndexes {
    return snowIndexes;
}
- (unsigned)selectionIndex {
    return [snowIndexes firstIndex];
}
- (void)setSelectionIndexes:(id)value {
    unsigned index;
    value = [value snowCopy];
    [snowIndexes removeAllIndexes];
    for (index = [value firstIndex]; value && index != NSNotFound;
         index = [value indexGreaterThanIndex:index])
        if (index < [snowArranged count])
            [snowIndexes addIndex:index];
    if (![snowIndexes count] && snowAvoidsEmpty && [snowArranged count])
        [snowIndexes addIndex:0];
    [value release];
    [self didChangeValueForKey:@"selection"];
    [self didChangeValueForKey:@"selectionIndexes"];
}
- (void)setSelectionIndex:(unsigned)index {
    id indexes = [[NSClassFromString(@"NSMutableIndexSet") alloc] init];
    if (index < [snowArranged count])
        [indexes addIndex:index];
    [self setSelectionIndexes:indexes];
    [indexes release];
}
- (NSArray *)selectedObjects {
    NSMutableArray *result = [NSMutableArray array];
    unsigned index;
    for (index = [snowIndexes firstIndex]; index != NSNotFound;
         index = [snowIndexes indexGreaterThanIndex:index])
        if (index < [snowArranged count])
            [result addObject:[snowArranged objectAtIndex:index]];
    return result;
}
- (BOOL)setSelectedObjects:(NSArray *)objects {
    id indexes = [[NSClassFromString(@"NSMutableIndexSet") alloc] init];
    unsigned i;
    for (i = 0; i < [objects count]; i++) {
        unsigned index = [snowArranged indexOfObjectIdenticalTo:[objects objectAtIndex:i]];
        if (index != NSNotFound)
            [indexes addIndex:index];
    }
    [self setSelectionIndexes:indexes];
    [indexes release];
    return YES;
}
- (id)selection {
    unsigned index = [self selectionIndex];
    return index < [snowArranged count] ? [snowArranged objectAtIndex:index] : nil;
}
- (int)numberOfRowsInTableView:(NSTableView *)table {
    return [snowArranged count];
}
- (id)tableView:(NSTableView *)table
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(int)row {
    return row >= 0 && row < [snowArranged count]
               ? [[snowArranged objectAtIndex:row] valueForKey:[column identifier]]
               : nil;
}
- (void)setAvoidsEmptySelection:(BOOL)value {
    snowAvoidsEmpty = value;
    if (value && ![snowIndexes count] && [snowArranged count])
        [self setSelectionIndex:0];
}
- (BOOL)avoidsEmptySelection {
    return snowAvoidsEmpty;
}
- (void)setPreservesSelection:(BOOL)value {
    snowPreservesSelection = value;
}
- (void)setSelectsInsertedObjects:(BOOL)value {
    snowSelectsInserted = value;
}
- (void)setAutomaticallyRearrangesObjects:(BOOL)value {
}
- (BOOL)canRemove {
    return snowEditable && [snowIndexes count] > 0;
}
- (void)addObject:(id)object {
    NSMutableArray *values = [snowContent snowMutableCopy];
    if (!values)
        values = [[NSMutableArray alloc] init];
    [values addObject:object];
    [self setContent:values];
    [values release];
    if (snowSelectsInserted)
        [self setSelectionIndex:[snowArranged indexOfObjectIdenticalTo:object]];
}
- (void)removeObject:(id)object {
    NSMutableArray *values = [snowContent snowMutableCopy];
    [values removeObjectIdenticalTo:object];
    [self setContent:values];
    [values release];
}
- (void)add:(id)sender {
    id object = [self newObject];
    [self addObject:object];
    [object release];
}
- (void)remove:(id)sender {
    NSArray *objects = [[self selectedObjects] retain];
    unsigned i;
    for (i = 0; i < [objects count]; i++)
        [self removeObject:[objects objectAtIndex:i]];
    [objects release];
}
- (void)dealloc {
    [snowArranged release];
    [snowIndexes release];
    [snowSort release];
    [snowFilter release];
    [super dealloc];
}
@end

@interface NSViewController : NSObject {
    NSString *snowViewNib;
    NSBundle *snowViewBundle;
    NSView *snowView;
    id snowRepresented;
    NSString *snowViewTitle;
    unsigned char snowViewReserved[28]; /* Stock subclasses start at offset 52. */
}
- initWithNibName:(NSString *)name bundle:(NSBundle *)bundle;
- (void)loadView;
- (NSView *)view;
- (void)setView:(NSView *)view;
@end
@implementation NSViewController
- initWithNibName:(NSString *)name bundle:(NSBundle *)bundle {
    self = [super init];
    snowViewNib = [name snowCopy];
    snowViewBundle = [bundle retain];
    return self;
}
- (NSString *)nibName {
    return snowViewNib;
}
- (NSBundle *)nibBundle {
    return snowViewBundle;
}
- (void)loadView {
    if (!TigerLoadNib(snowViewNib, self))
        [NSException raise:NSInvalidArgumentException format:@"Cannot load view %@", snowViewNib];
}
- (NSView *)view {
    if (!snowView)
        [self loadView];
    return snowView;
}
- (void)setView:(NSView *)view {
    [view retain];
    [snowView release];
    snowView = view;
}
- (id)representedObject {
    return snowRepresented;
}
- (void)setRepresentedObject:(id)value {
    [value retain];
    [snowRepresented release];
    snowRepresented = value;
}
- (NSString *)title {
    return snowViewTitle;
}
- (void)setTitle:(NSString *)title {
    [title retain];
    [snowViewTitle release];
    snowViewTitle = title;
}
- (BOOL)commitEditing {
    return YES;
}
- (void)dealloc {
    [snowViewNib release];
    [snowViewBundle release];
    [snowView release];
    [snowRepresented release];
    [snowViewTitle release];
    [super dealloc];
}
@end
