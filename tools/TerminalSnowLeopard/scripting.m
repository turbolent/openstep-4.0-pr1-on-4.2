/* Cocoa scripting metadata can be evaluated in process. OPENSTEP has no
 * Apple-event transport or AppleScript interpreter. */
@interface NSAppleEventManager : NSObject {
    NSMutableDictionary *snowHandlers;
}
@end
@implementation NSAppleEventManager
+ (id)sharedAppleEventManager {
    static id manager;
    if (!manager)
        manager = [[self alloc] init];
    return manager;
}
- (void)setEventHandler:(id)handler
            andSelector:(SEL)selector
          forEventClass:(unsigned)eventClass
             andEventID:(unsigned)eventID {
    NSString *key = [NSString stringWithFormat:@"%x:%x", eventClass, eventID];
    if (!snowHandlers)
        snowHandlers = [[NSMutableDictionary alloc] init];
    if (handler && selector)
        [snowHandlers
            setObject:[NSArray arrayWithObjects:handler, NSStringFromSelector(selector), nil]
               forKey:key];
    else
        [snowHandlers removeObjectForKey:key];
}
- (void)removeEventHandlerForEventClass:(unsigned)eventClass andEventID:(unsigned)eventID {
    [snowHandlers removeObjectForKey:[NSString stringWithFormat:@"%x:%x", eventClass, eventID]];
}
- (id)currentAppleEvent {
    return nil;
}
- (id)currentReplyAppleEvent {
    return nil;
}
- (void)dealloc {
    [snowHandlers release];
    [super dealloc];
}
@end
@interface NSScriptObjectSpecifier : NSObject {
  @protected
    id snowDescription, snowContainer, snowIdentifier;
    NSString *snowProperty;
    int snowIndex, snowSpecifierKind;
}
- (id)initWithContainerClassDescription:(id)description
                     containerSpecifier:(id)container
                                    key:(NSString *)key;
- (id)objectsByEvaluatingSpecifier;
- (id)objectsByEvaluatingWithContainers:(id)containers;
@end
@implementation NSScriptObjectSpecifier
- (id)initWithContainerClassDescription:(id)description
                     containerSpecifier:(id)container
                                    key:(NSString *)key {
    self = [super init];
    snowDescription = [description retain];
    snowContainer = [container retain];
    snowProperty = [key copy];
    return self;
}
- (id)containerSpecifier {
    return snowContainer;
}
- (id)containerClassDescription {
    return snowDescription;
}
- (NSString *)key {
    return snowProperty;
}
- (id)objectsByEvaluatingSpecifier {
    return
        [self objectsByEvaluatingWithContainers:snowContainer
                                                    ? [snowContainer objectsByEvaluatingSpecifier]
                                                    : NSApp];
}
- (id)objectsByEvaluatingWithContainers:(id)containers {
    id values = [containers valueForKey:snowProperty];
    unsigned i;
    if (!snowSpecifierKind)
        return values;
    if (![values isKindOfClass:[NSArray class]])
        return nil;
    if (snowSpecifierKind == 1)
        return snowIndex >= 0 && (unsigned)snowIndex < [values count]
                   ? [values objectAtIndex:snowIndex]
                   : nil;
    for (i = 0; i < [values count]; i++) {
        id value = [values objectAtIndex:i], identifier = nil;
        if ([value respondsToSelector:@selector(uniqueID)])
            identifier = [value valueForKey:@"uniqueID"];
        else if ([value respondsToSelector:@selector(id)])
            identifier = [value valueForKey:@"id"];
        if ([identifier isEqual:snowIdentifier])
            return value;
    }
    return nil;
}
- (void)dealloc {
    [snowDescription release];
    [snowContainer release];
    [snowProperty release];
    [snowIdentifier release];
    [super dealloc];
}
@end
@interface NSPropertySpecifier : NSScriptObjectSpecifier
@end
@implementation NSPropertySpecifier
@end
@interface NSIndexSpecifier : NSScriptObjectSpecifier
@end
@implementation NSIndexSpecifier
- (id)initWithContainerClassDescription:(id)description
                     containerSpecifier:(id)container
                                    key:(NSString *)key
                                  index:(int)index {
    self = [super initWithContainerClassDescription:description
                                 containerSpecifier:container
                                                key:key];
    snowSpecifierKind = 1;
    snowIndex = index;
    return self;
}
- (int)index {
    return snowIndex;
}
- (void)setIndex:(int)index {
    snowIndex = index;
}
@end
@interface NSUniqueIDSpecifier : NSScriptObjectSpecifier
@end
@implementation NSUniqueIDSpecifier
- (id)initWithContainerClassDescription:(id)description
                     containerSpecifier:(id)container
                                    key:(NSString *)key
                               uniqueID:(id)identifier {
    self = [super initWithContainerClassDescription:description
                                 containerSpecifier:container
                                                key:key];
    snowSpecifierKind = 2;
    snowIdentifier = [identifier retain];
    return self;
}
- (id)uniqueID {
    return snowIdentifier;
}
@end
