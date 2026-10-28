/* The comparison predicates used by Terminal's profiles, encodings and windows. */
#include <stdarg.h>
@interface NSPredicate : NSObject {
    NSString *snowPredicateKey;
    id snowPredicateValue;
    NSPredicate *snowPredicateLeft, *snowPredicateRight;
    unsigned snowPredicateOperation;
}
+ (id)predicateWithFormat:(NSString *)format, ...;
- (BOOL)evaluateWithObject:(id)object;
@end
@implementation NSPredicate
+ (id)predicateWithFormat:(NSString *)format arguments:(va_list *)arguments {
    NSPredicate *predicate = [[[self alloc] init] autorelease];
    NSRange split = [format rangeOfString:@" OR "];
    NSString *operator= nil, *value;
    NSArray *operators = [NSArray arrayWithObjects:@" == ", @" = ", @" != ", @" IN ", nil];
    unsigned i;
    if (split.location != NSNotFound)
        predicate->snowPredicateOperation = 5;
    else {
        split = [format rangeOfString:@" && "];
        if (split.location != NSNotFound)
            predicate->snowPredicateOperation = 4;
    }
    if (split.location != NSNotFound) {
        predicate->snowPredicateLeft =
            [[self predicateWithFormat:[format substringToIndex:split.location]
                             arguments:arguments] retain];
        predicate->snowPredicateRight =
            [[self predicateWithFormat:[format substringFromIndex:NSMaxRange(split)]
                             arguments:arguments] retain];
        return predicate;
    }
    for (i = 0; i < [operators count]; i++) {
        operator= [operators objectAtIndex:i]; split=[format rangeOfString:operator];
        if (split.location != NSNotFound)
            break;
    }
    if (split.location == NSNotFound)
        [NSException raise:NSInvalidArgumentException format:@"Unsupported predicate %@", format];
    predicate->snowPredicateKey = [[format substringToIndex:split.location] snowCopy];
    predicate->snowPredicateOperation = i == 2 ? 1 : (i == 3 ? 2 : 0);
    value = [format substringFromIndex:NSMaxRange(split)];
    if ([value isEqual:@"%@"])
        predicate->snowPredicateValue = [va_arg(*arguments, id) retain];
    else if ([value isEqual:@"YES"] || [value isEqual:@"TRUE"])
        predicate->snowPredicateValue = [[NSNumber numberWithBool:YES] retain];
    else if ([value isEqual:@"NO"] || [value isEqual:@"FALSE"])
        predicate->snowPredicateValue = [[NSNumber numberWithBool:NO] retain];
    else if ([value isEqual:@"nil"] || [value isEqual:@"NULL"])
        predicate->snowPredicateValue = nil;
    else
        [NSException raise:NSInvalidArgumentException
                    format:@"Unsupported predicate value %@", value];
    return predicate;
}
+ (id)predicateWithFormat:(NSString *)format, ... {
    va_list arguments;
    id result;
    va_start(arguments, format);
    result = [self predicateWithFormat:format arguments:&arguments];
    va_end(arguments);
    return result;
}
- (BOOL)evaluateWithObject:(id)object {
    id value;
    if (snowPredicateOperation == 4)
        return [snowPredicateLeft evaluateWithObject:object] &&
               [snowPredicateRight evaluateWithObject:object];
    if (snowPredicateOperation == 5)
        return [snowPredicateLeft evaluateWithObject:object] ||
               [snowPredicateRight evaluateWithObject:object];
    value = [object valueForKeyPath:snowPredicateKey];
    if (snowPredicateOperation == 2)
        return [snowPredicateValue containsObject:value];
    return (value == snowPredicateValue || [value isEqual:snowPredicateValue]) !=
           (snowPredicateOperation == 1);
}
- (void)dealloc {
    [snowPredicateKey release];
    [snowPredicateValue release];
    [snowPredicateLeft release];
    [snowPredicateRight release];
    [super dealloc];
}
@end
@implementation NSArray (SnowPredicates)
- (NSArray *)filteredArrayUsingPredicate:(NSPredicate *)predicate {
    NSMutableArray *result = [NSMutableArray array];
    unsigned i;
    for (i = 0; i < [self count]; i++)
        if ([predicate evaluateWithObject:[self objectAtIndex:i]])
            [result addObject:[self objectAtIndex:i]];
    return result;
}
@end
@implementation NSMutableArray (SnowPredicates)
- (void)filterUsingPredicate:(NSPredicate *)predicate {
    int i;
    for (i = [self count] - 1; i >= 0; i--)
        if (![predicate evaluateWithObject:[self objectAtIndex:i]])
            [self removeObjectAtIndex:i];
}
@end
