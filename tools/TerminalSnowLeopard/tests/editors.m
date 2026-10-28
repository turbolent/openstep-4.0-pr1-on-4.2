/* Native persistence and edit-history regressions. No Apple binary required. */
#include <assert.h>
@interface SnowUndoValue : NSObject {
  @public
    NSUndoManager *undo;
    int number;
}
- (void)setNumber:(int)value;
@end
@implementation SnowUndoValue
- (void)setNumber:(int)value {
    [[undo prepareWithInvocationTarget:self] setNumber:number];
    number = value;
}
@end
@interface SnowControllerEditor : NSObject {
  @public
    NSObjectController *owner;
    unsigned commits;
}
@end
@implementation SnowControllerEditor
- (BOOL)commitEditing {
    commits++;
    return YES;
}
- (void)discardEditing {
    [owner objectDidEndEditing:self];
}
@end
int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSUndoManager *undo = [[NSUndoManager alloc] init];
    SnowUndoValue *value = [[SnowUndoValue alloc] init];
    NSArrayController *controller = [[NSArrayController alloc] init];
    NSDictionary *dictionary;
    unsigned format;
    unsigned char bytes[] = {0, 1, 2, 127, 128, 254, 255};
    SnowInitializeFoundation();
    SnowInitializeFormatting();
    value->undo = undo;
    [undo beginUndoGrouping];
    [value setNumber:12];
    [value setNumber:34];
    [undo endUndoGrouping];
    assert(value->number == 34 && [undo canUndo]);
    [undo undo];
    assert(value->number == 0 && [undo canRedo]);
    [undo redo];
    assert(value->number == 34 && [undo canUndo]);
    [undo removeAllActionsWithTarget:value];
    assert(![undo canUndo]);
    [value release];
    [undo release];
    assert([NSArrayController class]->instance_size == 132);
    assert([NSViewController class]->instance_size == 52);
    {
        NSObjectController *object = [[NSObjectController alloc] init];
        SnowControllerEditor *editor = [[SnowControllerEditor alloc] init];
        editor->owner = object;
        assert(![object isEditing]);
        [object objectDidBeginEditing:editor];
        [object objectDidBeginEditing:editor];
        assert([object isEditing] && [object commitEditing] && editor->commits == 1);
        [object discardEditing];
        assert(![object isEditing]);
        [editor release];
        [object setContentObject:@"inspected window"];
        assert([[object content] isEqual:@"inspected window"]);
        [object setContent:@"new window"];
        assert([[object contentObject] isEqual:@"new window"]);
        [object release];
    }
    [controller setContent:[NSArray arrayWithObjects:@"a", @"b", @"c", nil]];
    [controller setSelectionIndex:1];
    [controller setSelectionIndexes:[controller selectionIndexes]];
    assert([controller selectionIndex] == 1);
    [controller setPreservesSelection:YES];
    [controller rearrangeObjects];
    assert([[controller selection] isEqual:@"b"]);
    [controller release];
    dictionary = [NSDictionary
        dictionaryWithObjectsAndKeys:@"  title <&>\n ", @"title",
                                     [NSNumber numberWithLongLong:-1234567890123LL], @"integer",
                                     [NSNumber numberWithDouble:1.25], @"real",
                                     [NSNumber numberWithBool:YES], @"bool",
                                     [NSData dataWithBytes:bytes length:sizeof(bytes)], @"bytes",
                                     [NSDate dateWithTimeIntervalSinceReferenceDate:12345], @"date",
                                     [NSArray arrayWithObjects:@"one", @"two", nil], @"array", nil];
    for (format = 100; format <= 200; format += 100) {
        NSString *error = nil;
        unsigned actual = 0;
        NSData *data = [NSPropertyListSerialization dataFromPropertyList:dictionary
                                                                  format:format
                                                        errorDescription:&error];
        id parsed;
        assert(data && !error);
        [data writeToFile:format == 100 ? @"test-profile.xml" : @"test-profile.binary"
               atomically:YES];
        parsed = [NSPropertyListSerialization propertyListFromData:data
                                                  mutabilityOption:0
                                                            format:&actual
                                                  errorDescription:&error];
        if (error)
            fprintf(stderr, "plist: %s\n", [error cString]);
        assert(parsed && !error && actual == format);
        assert([[parsed objectForKey:@"title"] isEqual:[dictionary objectForKey:@"title"]]);
        assert([[parsed objectForKey:@"integer"] longLongValue] == -1234567890123LL);
        assert([[parsed objectForKey:@"real"] doubleValue] == 1.25);
        assert([[parsed objectForKey:@"bool"] boolValue]);
        assert([[parsed objectForKey:@"bytes"] isEqual:[dictionary objectForKey:@"bytes"]]);
        assert([[parsed objectForKey:@"date"] isEqual:[dictionary objectForKey:@"date"]]);
        assert([[parsed objectForKey:@"array"] isEqual:[dictionary objectForKey:@"array"]]);
    }
    assert(![NSPropertyListSerialization dataFromPropertyList:[NSNull null]
                                                       format:200
                                             errorDescription:NULL]);
    puts("PASS native editors: undo/redo, controller selection, XML and binary property lists");
    [pool release];
    return 0;
}
