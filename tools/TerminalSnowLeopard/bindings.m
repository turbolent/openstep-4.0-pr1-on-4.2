/* Cocoa bindings used by the shell and profile controllers. */
@interface SnowBinding : NSObject {
  @public
    id target, source, transformer;
    NSString *name, *path;
    NSDictionary *options;
    BOOL updating;
}
- (void)update;
@end
static NSMutableDictionary *snowBindings;
static void SnowApplyBinding(id target, NSString *name, id value);
@implementation SnowBinding
- (void)update {
    id value;
    if (updating)
        return;
    updating = YES;
    NS_DURING
        value = [source valueForKeyPath:path];
        SnowPrimeObservation(source, self, path, value);
        if (transformer)
            value = [transformer transformedValue:value];
        if (!value || value == [NSNull null])
            value = [options objectForKey:@"NSNullPlaceholder"];
        SnowApplyBinding(target, name, value);
    NS_HANDLER
        updating = NO;
        [localException raise];
    NS_ENDHANDLER
    updating = NO;
}
- (void)observeValueForKeyPath:(NSString *)key
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    [self update];
}
- (void)dealloc {
    [source removeObserver:self forKeyPath:path];
    [source release];
    [transformer release];
    [name release];
    [path release];
    [options release];
    [super dealloc];
}
@end

static SnowBinding *snowBindingFor(id object, NSString *name) {
    return [[snowBindings objectForKey:[NSValue valueWithPointer:object]] objectForKey:name];
}
static void SnowCommitBindingTarget(id object, NSString *name, id value) {
    SnowBinding *binding = snowBindingFor(object, name);
    if (!binding || binding->updating)
        return;
    if (binding->transformer) {
        if (![[binding->transformer class] allowsReverseTransformation])
            return;
        value = [binding->transformer reverseTransformedValue:value];
    }
    binding->updating = YES;
    NS_DURING
        [binding->source setValue:value forKeyPath:binding->path];
        SnowPrimeObservation(binding->source, binding, binding->path,
                             [binding->source valueForKeyPath:binding->path]);
    NS_HANDLER
        binding->updating = NO;
        [localException raise];
    NS_ENDHANDLER
    binding->updating = NO;
}
static void SnowCommitControlBindings(id control) {
    NSDictionary *bindings = [snowBindings objectForKey:[NSValue valueWithPointer:control]];
    NSArray *names = [bindings allKeys];
    unsigned i;
    for (i = 0; i < [names count]; i++) {
        NSString *name = [names objectAtIndex:i];
        id value = nil;
        if ([name isEqual:@"value"]) {
            if ([control isKindOfClass:[NSColorWell class]])
                value = [control color];
            else if ([control isKindOfClass:[NSButton class]])
                value = [NSNumber numberWithInt:[control state]];
            else if ([control isKindOfClass:[NSControl class]])
                value = [control objectValue];
            else
                continue;
        } else if ([name isEqual:@"selectedTag"]) {
            value = [NSNumber numberWithInt:[control isKindOfClass:[NSMatrix class]]
                                                ? [[control selectedCell] tag]
                                                : [[control selectedItem] tag]];
        } else if ([name isEqual:@"selectedIndex"]) {
            int index =
                [control isKindOfClass:[NSMatrix class]]
                    ? [control selectedRow] * [control numberOfColumns] + [control selectedColumn]
                    : [control indexOfSelectedItem];
            value = [NSNumber numberWithInt:index];
        } else if ([name isEqual:@"selectedObject"] || [name isEqual:@"selectedValue"]) {
            SnowBinding *items = snowBindingFor(
                control, [name isEqual:@"selectedValue"] ? @"contentValues" : @"contentObjects");
            NSArray *values;
            int index = [control indexOfSelectedItem];
            if (!items)
                items = snowBindingFor(control, @"content");
            values = items ? [items->source valueForKeyPath:items->path] : nil;
            if (values && index >= 0 && index < [values count])
                value = [values objectAtIndex:index];
            else
                value = [[control selectedItem] title];
        } else
            continue;
        SnowCommitBindingTarget(control, name, value);
    }
}
static IMP snowNativeSendAction;
static BOOL snowBindingSendAction(NSApplication *application, SEL method, SEL action, id target,
                                  id sender) {
    if (sender)
        SnowCommitControlBindings(sender);
    return ((BOOL(*)(id, SEL, SEL, id, id))snowNativeSendAction)(application, method, action,
                                                                 target, sender);
}
@interface SnowBindingEditor : NSObject
+ (void)endEditing:(NSNotification *)notification;
@end
@implementation SnowBindingEditor
+ (void)endEditing:(NSNotification *)notification {
    SnowCommitControlBindings([notification object]);
}
@end
static void SnowInitializeBindings(void) {
    Method method = class_getInstanceMethod([NSApplication class], @selector(sendAction:to:from:));
    snowNativeSendAction = method->method_imp;
    method->method_imp = (IMP)snowBindingSendAction;
    [[NSNotificationCenter defaultCenter] addObserver:[SnowBindingEditor class]
                                             selector:@selector(endEditing:)
                                                 name:NSControlTextDidEndEditingNotification
                                               object:nil];
}
static NSMutableDictionary *snowTableModels;
@interface SnowTableModel : NSObject {
  @public
    NSTableView *table;
    NSArray *rows;
    NSArray *sortDescriptors;
    NSMutableDictionary *columns;
}
@end
@implementation SnowTableModel
- init {
    self = [super init];
    columns = [[NSMutableDictionary alloc] init];
    return self;
}
- (int)numberOfRowsInTableView:(NSTableView *)view {
    return [rows count];
}
- (id)tableView:(NSTableView *)view objectValueForTableColumn:(NSTableColumn *)column row:(int)row {
    NSArray *values = [columns objectForKey:[NSValue valueWithPointer:column]];
    return row >= 0 && row < [values count] ? [values objectAtIndex:row] : nil;
}
- (void)tableView:(NSTableView *)view
    setObjectValue:(id)value
    forTableColumn:(NSTableColumn *)column
               row:(int)row {
    SnowBinding *binding = snowBindingFor(column, @"value");
    NSRange dot;
    if (!binding || row < 0 || row >= [rows count])
        return;
    dot = [binding->path rangeOfString:@"."];
    if (dot.location != NSNotFound)
        [[rows objectAtIndex:row] setValue:value
                                forKeyPath:[binding->path substringFromIndex:dot.location + 1]];
    [binding update];
}
- (void)selectionChanged:(NSNotification *)note {
    SnowBinding *binding = snowBindingFor(table, @"selectionIndexes");
    id indexes = [[NSClassFromString(@"NSMutableIndexSet") alloc] init];
    NSEnumerator *selected = [table selectedRowEnumerator];
    NSNumber *row;
    while ((row = [selected nextObject]))
        [indexes addIndex:[row unsignedIntValue]];
    if (binding && !binding->updating)
        [binding->source setValue:indexes forKeyPath:binding->path];
    [indexes release];
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [rows release];
    [sortDescriptors release];
    [columns release];
    [super dealloc];
}
@end
static SnowTableModel *snowTableModel(NSTableView *table) {
    NSValue *key = [NSValue valueWithPointer:table];
    SnowTableModel *model;
    if (!snowTableModels)
        snowTableModels = [[NSMutableDictionary alloc] init];
    model = [snowTableModels objectForKey:key];
    if (!model) {
        model = [[[SnowTableModel alloc] init] autorelease];
        model->table = table;
        [snowTableModels setObject:model forKey:key];
        [[NSNotificationCenter defaultCenter] addObserver:model
                                                 selector:@selector(selectionChanged:)
                                                     name:NSTableViewSelectionDidChangeNotification
                                                   object:table];
        [table setDataSource:model];
    }
    return model;
}
@implementation NSTableView (SnowSortDescriptors)
- (NSArray *)sortDescriptors {
    NSArray *descriptors = snowTableModel(self)->sortDescriptors;
    return descriptors ? descriptors : [NSArray array];
}
- (void)setSortDescriptors:(NSArray *)descriptors {
    SnowTableModel *model = snowTableModel(self);
    descriptors = [descriptors snowCopy];
    [model->sortDescriptors release];
    model->sortDescriptors = descriptors;
    SnowCommitBindingTarget(self, @"sortDescriptors", descriptors);
}
@end
static void SnowApplyBinding(id target, NSString *name, id value) {
    if ([value isKindOfClass:[NSNull class]])
        value = nil;
    if ([target isKindOfClass:[NSTableColumn class]] && [name isEqual:@"value"]) {
        SnowTableModel *model = snowTableModel([target tableView]);
        if (value)
            [model->columns setObject:value forKey:[NSValue valueWithPointer:target]];
        else
            [model->columns removeObjectForKey:[NSValue valueWithPointer:target]];
        [model->table reloadData];
        return;
    }
    if ([target isKindOfClass:[NSTableView class]]) {
        SnowTableModel *model = snowTableModel(target);
        if ([name isEqual:@"content"]) {
            [value retain];
            [model->rows release];
            model->rows = value;
            [target reloadData];
            return;
        }
        if ([name isEqual:@"selectionIndexes"]) {
            unsigned index;
            BOOL extend = NO;
            [target deselectAll:nil];
            for (index = [value firstIndex]; value && index != NSNotFound;
                 index = [value indexGreaterThanIndex:index])
                if (index < [model->rows count]) {
                    [target selectRow:index byExtendingSelection:extend];
                    if (![target allowsMultipleSelection])
                        break;
                    extend = YES;
                }
            return;
        }
    }
    if ([target isKindOfClass:[NSPopUpButton class]]) {
        if ([name isEqual:@"content"] || [name isEqual:@"contentObjects"])
            return;
        if ([name isEqual:@"contentValues"]) {
            unsigned i;
            [target removeAllItems];
            for (i = 0; i < [value count]; i++)
                [target addItemWithTitle:[[value objectAtIndex:i] description]];
            return;
        }
        if ([name isEqual:@"selectedObject"] || [name isEqual:@"selectedValue"]) {
            SnowBinding *binding = snowBindingFor(
                target, [name isEqual:@"selectedValue"] ? @"contentValues" : @"contentObjects");
            NSArray *values;
            if (!binding)
                binding = snowBindingFor(target, @"content");
            values = binding ? [binding->source valueForKeyPath:binding->path] : nil;
            if (values) {
                unsigned index = [values indexOfObject:value];
                if (index != NSNotFound)
                    [target selectItemAtIndex:index];
            } else if (value)
                [target selectItemWithTitle:[value description]];
            return;
        }
    }
    if ([name isEqual:@"enabled"] || [name isEqual:@"enabled2"]) {
        SnowBinding *other =
            snowBindingFor(target, [name isEqual:@"enabled"] ? @"enabled2" : @"enabled");
        BOOL enabled = [value boolValue];
        if (other) {
            id another = [other->source valueForKeyPath:other->path];
            if (other->transformer)
                another = [other->transformer transformedValue:another];
            enabled = enabled && [another boolValue];
        }
        [target setEnabled:enabled];
        return;
    }
    if ([name isEqual:@"selectedTag"]) {
        if ([target isKindOfClass:[NSMatrix class]])
            [target selectCellWithTag:[value intValue]];
        else
            [target selectItemWithTag:[value intValue]];
        return;
    }
    if ([name isEqual:@"selectedIndex"]) {
        if ([target isKindOfClass:NSClassFromString(@"NSTabView")])
            [target selectTabViewItemAtIndex:[value intValue]];
        else if ([target isKindOfClass:[NSMatrix class]]) {
            int columns = [target numberOfColumns], index = [value intValue];
            if (columns > 0 && index >= 0 && index < [target numberOfRows] * columns) {
                [target selectCellAtRow:index / columns column:index % columns];
                /* Native matrices can already name the selected slot when
                 * its archived cell has just replaced the prototype. */
                [[target cellAtRow:index / columns column:index % columns] setState:1];
                [target setNeedsDisplay:YES];
            }
        } else
            [target selectItemAtIndex:[value intValue]];
        return;
    }
    if ([name isEqual:@"value"] && [target isKindOfClass:[NSControl class]]) {
        if ([target isKindOfClass:[NSColorWell class]]) {
            if (value)
                [target setColor:snowTextSelectionColor(value)];
        } else if ([target isKindOfClass:[NSButton class]])
            [target setState:[value intValue]];
        else
            [target setObjectValue:value ? value : @""];
        return;
    }
    [target setValue:value forKey:name];
}
@implementation NSObject (SnowBindings)
+ (void)exposeBinding:(NSString *)binding {
}
- (void)unbind:(NSString *)binding {
    NSValue *key = [NSValue valueWithPointer:self];
    NSMutableDictionary *bindings = [snowBindings objectForKey:key];
    SnowBinding *record = [bindings objectForKey:binding];
    if (record)
        [record->source removeObserver:record forKeyPath:record->path];
    [bindings removeObjectForKey:binding];
    if (![bindings count])
        [snowBindings removeObjectForKey:key];
}
- (void)bind:(NSString *)binding
       toObject:(id)object
    withKeyPath:(NSString *)keyPath
        options:(NSDictionary *)settings {
    NSValue *key = [NSValue valueWithPointer:self];
    NSMutableDictionary *bindings;
    SnowBinding *record;
    [self unbind:binding];
    if (!object || !binding || !keyPath)
        [NSException raise:NSInvalidArgumentException
                    format:@"A binding requires an object, name, and key path"];
    if (!snowBindings)
        snowBindings = [[NSMutableDictionary alloc] init];
    bindings = [snowBindings objectForKey:key];
    if (!bindings) {
        bindings = [NSMutableDictionary dictionary];
        [snowBindings setObject:bindings forKey:key];
    }
    record = [[[SnowBinding alloc] init] autorelease];
    record->target = self;
    record->source = [object retain];
    record->name = [binding snowCopy];
    record->path = [keyPath snowCopy];
    record->options = [settings snowCopy];
    record->transformer = [[settings objectForKey:@"NSValueTransformer"] retain];
    if (!record->transformer)
        record->transformer = [[NSValueTransformer
            valueTransformerForName:[settings objectForKey:@"NSValueTransformerName"]] retain];
    [bindings setObject:record forKey:binding];
    [object addObserver:record forKeyPath:keyPath options:0 context:NULL];
    [record update];
}
- (NSDictionary *)infoForBinding:(NSString *)binding {
    SnowBinding *record =
        [[snowBindings objectForKey:[NSValue valueWithPointer:self]] objectForKey:binding];
    if (!record)
        return nil;
    return [NSDictionary
        dictionaryWithObjectsAndKeys:record->source, @"NSObservedObject", record->path,
                                     @"NSObservedKeyPath",
                                     record->options ? record->options : [NSDictionary dictionary],
                                     @"NSOptions", nil];
}
@end
