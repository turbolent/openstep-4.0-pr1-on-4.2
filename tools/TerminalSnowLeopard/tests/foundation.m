/* Generate with tests/prepare.py, then compile and run on OPENSTEP. */
#import <AppKit/AppKit.h>
#include <assert.h>
#include <stdio.h>
extern void SnowInitializeFoundation(void);
extern void SnowInitializeFormatting(void);
@interface NSObject (SnowTestAPI)
- (id)valueForKey:(NSString *)key;
- (void)setValue:(id)value forKey:(NSString *)key;
- (void)bind:(NSString *)name
       toObject:(id)object
    withKeyPath:(NSString *)path
        options:(NSDictionary *)options;
- (void)unbind:(NSString *)name;
- (void)didChangeValueForKey:(NSString *)key;
- (void)addIndexesInRange:(NSRange)range;
- (void)removeIndexesInRange:(NSRange)range;
- (void)shiftIndexesStartingAtIndex:(unsigned)index by:(int)delta;
- (BOOL)containsIndex:(unsigned)index;
- (unsigned)rangeCount;
- (NSRange)rangeAtIndex:(unsigned)index;
@end
@interface SnowTestCollection : NSObject {
    NSMutableArray *items;
  @public
    unsigned mutations;
}
@end
@implementation SnowTestCollection
- init {
    self = [super init];
    items = [[NSMutableArray alloc] init];
    return self;
}
- (NSArray *)items {
    return [[[NSArray alloc] initWithArray:items] autorelease];
}
- (void)insertObject:(id)value inItemsAtIndex:(unsigned)index {
    mutations++;
    [items insertObject:value atIndex:index];
}
- (void)removeObjectFromItemsAtIndex:(unsigned)index {
    mutations++;
    [items removeObjectAtIndex:index];
}
- (void)replaceObjectInItemsAtIndex:(unsigned)index withObject:(id)value {
    mutations++;
    [items replaceObjectAtIndex:index withObject:value];
}
- (void)dealloc {
    [items release];
    [super dealloc];
}
@end
@interface SnowTestValue : NSObject {
    int count;
}
- (int)count;
- (void)setCount:(int)value;
- (BOOL)isPositive;
@end
@implementation SnowTestValue
- (int)count {
    return count;
}
- (void)setCount:(int)value {
    count = value;
}
- (BOOL)isPositive {
    return count > 0;
}
@end
@interface SnowTestObserver : NSObject {
  @public
    unsigned changes;
}
@end
@implementation SnowTestObserver
- (void)observeValueForKeyPath:(NSString *)path
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    changes++;
}
@end
@interface SnowTestRemovingObserver : SnowTestObserver {
  @public
    id nextObserver;
}
@end
@implementation SnowTestRemovingObserver
- (void)observeValueForKeyPath:(NSString *)path
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    changes++;
    [object removeObserver:nextObserver forKeyPath:path];
}
@end
int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    SnowTestValue *value = [[SnowTestValue alloc] init];
    NSMutableDictionary *source =
        [NSMutableDictionary dictionaryWithObject:[NSNumber numberWithInt:7] forKey:@"count"];
    NSMutableString *element = [NSMutableString stringWithString:@"original"];
    NSArray *array = [NSArray arrayWithObject:element], *copy;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id indexes = [[NSClassFromString(@"NSMutableIndexSet") alloc] init];
    NSRange range;
    SnowInitializeFoundation();
    assert([[@"a|b||c" stringByReplacingOccurrencesOfString:@"|"
                                                 withString:@" "] isEqual:@"a b  c"]);
    assert([[@"aa" stringByReplacingOccurrencesOfString:@"a" withString:@"aa"] isEqual:@"aaaa"]);
    assert([[@"abc" stringByReplacingOccurrencesOfString:@"" withString:@"x"] isEqual:@"abc"]);
    SnowInitializeFormatting();
    assert([[@"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        isEqual:@""]);
    assert([[@" \nword\t "
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        isEqual:@"word"]);
    assert([[@" \n\t"
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        isEqual:@""]);
    {
        unichar expected[] = {0x2014, ' ', 0xd7, ' ', 0x03b1};
        unichar text[] = {0x03b1, 0};
        NSString *formatted = [NSString stringWithFormat:@"%C %C %S", 0x2014, 0xd7, text];
        assert([formatted isEqual:[NSString stringWithCharacters:expected length:5]]);
        formatted = [NSString stringWithFormat:@"%@ %d %C %.2f %u", @"test", -12, '!', 2.5, 123U];
        assert([formatted isEqual:@"test -12 ! 2.50 123"]);
        formatted = [NSString stringWithFormat:@"%% %C %*d", 'X', 3, 7];
        assert([formatted isEqual:@"% X   7"]);
        {
            NSMutableString *mutable = [NSMutableString string];
            [mutable appendFormat:@"%d%C%d", 80, 0xd7, 24];
            expected[0] = '8';
            expected[1] = '0';
            expected[2] = 0xd7;
            expected[3] = '2';
            expected[4] = '4';
            assert([mutable isEqual:[NSString stringWithCharacters:expected length:5]]);
        }
    }
    copy = [array snowCopy];
    assert([copy objectAtIndex:0] == element);
    [copy release];
    {
        NSMutableArray *inner = [NSMutableArray arrayWithObject:element];
        NSMutableArray *nested = [NSMutableArray arrayWithObject:inner];
        NSArray *native = [nested copyWithZone:NULL];
        assert([native objectAtIndex:0] != inner);
        assert([[native objectAtIndex:0] objectAtIndex:0] != element);
        assert([[[native objectAtIndex:0] objectAtIndex:0] isEqual:element]);
        [native release];
        copy = [nested snowCopy];
        assert([copy objectAtIndex:0] == inner);
        [copy release];
    }
    [value setValue:[NSNumber numberWithInt:42] forKey:@"count"];
    assert([value count] == 42);
    assert([[value valueForKey:@"count"] intValue] == 42);
    {
        SnowTestObserver *observer = [[SnowTestObserver alloc] init];
        [value addObserver:observer forKeyPath:@"count" options:0 context:NULL];
        [value willChangeValueForKey:@"count"];
        [value didChangeValueForKey:@"count"];
        assert(observer->changes == 1); /* Manual notification also covers equal values. */
        [value removeObserver:observer forKeyPath:@"count"];
        [observer release];
    }
    assert([[value valueForKey:@"positive"] boolValue]);
    {
        SnowTestObserver *observer = [[SnowTestObserver alloc] init];
        [value addObserver:observer forKeyPath:@"positive" options:0 context:NULL];
        [value didChangeValueForKey:@"unobserved"]; /* Prime before dependencies are declared. */
        [SnowTestValue setKeys:[NSArray arrayWithObject:@"count"]
            triggerChangeNotificationsForDependentKey:@"positive"];
        [value setCount:43];
        [value didChangeValueForKey:@"count"];
        [value setCount:44];
        [value didChangeValueForKey:@"count"];
        assert(observer->changes == 2);
        [value removeObserver:observer forKeyPath:@"positive"];
        [observer release];
    }
    {
        SnowTestRemovingObserver *first = [[SnowTestRemovingObserver alloc] init];
        SnowTestObserver *second = [[SnowTestObserver alloc] init];
        first->nextObserver = second;
        [value addObserver:first forKeyPath:@"count" options:0 context:NULL];
        [value addObserver:second forKeyPath:@"count" options:0 context:NULL];
        [value willChangeValueForKey:@"count"];
        [value didChangeValueForKey:@"count"];
        assert(first->changes == 1 && second->changes == 0);
        [value removeObserver:first forKeyPath:@"count"];
        [first release];
        [second release];
    }
    [value bind:@"count" toObject:source withKeyPath:@"count" options:nil];
    assert([value count] == 7);
    [source setObject:[NSNumber numberWithInt:13] forKey:@"count"];
    [source didChangeValueForKey:@"count"];
    assert([value count] == 13);
    [value unbind:@"count"];
    [source setObject:[NSNumber numberWithInt:99] forKey:@"count"];
    [source didChangeValueForKey:@"count"];
    assert([value count] == 13);
    [defaults setObject:source forKey:@"SnowCompatibilityTest"];
    assert([[[defaults objectForKey:@"SnowCompatibilityTest"] objectForKey:@"count"] intValue] ==
           99);
    assert([[[defaults dictionaryForKey:@"SnowCompatibilityTest"] objectForKey:@"count"]
               intValue] == 99);
    [defaults setObject:nil forKey:@"SnowCompatibilityTest"];
    assert([defaults objectForKey:@"SnowCompatibilityTest"] == nil);
    {
        NSAutoreleasePool *writePool = [[NSAutoreleasePool alloc] init];
        NSString *frame = [[NSString alloc] initWithFormat:@"%d %d %d %d", 20, 30, 500, 350];
        id saved;
        NSAutoreleasePool *readPool;
        [defaults setObject:frame forKey:@"NSWindow Frame SnowCompatibilityFrameTest"];
        [frame release];
        [writePool release];
        readPool = [[NSAutoreleasePool alloc] init];
        saved = [defaults objectForKey:@"NSWindow Frame SnowCompatibilityFrameTest"];
        [NSWindow removeFrameUsingName:@"SnowCompatibilityFrameTest"];
        /* The stock window controller removes and reinserts its saved frame. */
        [defaults setObject:saved forKey:@"NSWindow Frame SnowCompatibilityFrameTest"];
        assert([[defaults objectForKey:@"NSWindow Frame SnowCompatibilityFrameTest"]
            isEqual:@"20 30 500 350"]);
        [readPool release];
        [NSWindow removeFrameUsingName:@"SnowCompatibilityFrameTest"];
    }
    {
        SnowTestCollection *owner = [[SnowTestCollection alloc] init];
        NSMutableArray *proxy = [owner mutableArrayValueForKey:@"items"];
        [proxy addObject:@"first"];
        [proxy insertObject:@"second" atIndex:0];
        [proxy replaceObjectAtIndex:1 withObject:@"third"];
        [proxy removeObjectAtIndex:0];
        assert(owner->mutations == 4 && [proxy count] == 1 &&
               [[proxy objectAtIndex:0] isEqual:@"third"]);
        [owner release];
    }
    [indexes addIndexesInRange:NSMakeRange(2, 5)];
    [indexes shiftIndexesStartingAtIndex:4 by:3];
    assert([indexes rangeCount] == 2 && [indexes containsIndex:3] && ![indexes containsIndex:4]);
    range = [indexes rangeAtIndex:1];
    assert(range.location == 7 && range.length == 3);
    [indexes shiftIndexesStartingAtIndex:7 by:-4];
    range = [indexes rangeAtIndex:0];
    assert(range.location == 2 && range.length == 4);
    [indexes shiftIndexesStartingAtIndex:0 by:-4];
    assert([indexes containsIndex:0] && [indexes containsIndex:1] && ![indexes containsIndex:2]);
    [indexes removeIndexesInRange:NSMakeRange(0, NSNotFound)];
    assert([indexes rangeCount] == 0);
    [indexes release];
    [value release];
    [pool release];
    puts(
        "Collection identity, Unicode formatting, scalar KVC, bindings, defaults, and index shifts passed");
    return 0;
}
