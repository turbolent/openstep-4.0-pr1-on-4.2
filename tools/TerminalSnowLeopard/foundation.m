/* Foundation additions backed by OPENSTEP collections and key-value coding. */
NSString *NSKeyValueChangeIndexesKey = @"indexes";
NSString *NSKeyValueChangeKindKey = @"kind";
NSString *NSKeyValueChangeNewKey = @"new";
NSString *NSKeyValueChangeOldKey = @"old";
NSString *NSKeyValueChangeNotificationIsPriorKey = @"notificationIsPrior";
NSString *NSLocaleCountryCode = @"kCFLocaleCountryCodeKey";
NSString *NSLocaleIdentifier = @"kCFLocaleIdentifierKey";
NSString *NSLocaleLanguageCode = @"kCFLocaleLanguageCodeKey";
NSString *NSLocalizedDescriptionKey = @"NSLocalizedDescription";
NSString *NSLocalizedRecoverySuggestionErrorKey = @"NSLocalizedRecoverySuggestion";
NSString *NSUnderlineColorAttributeName = @"NSUnderlineColor";
NSString *NSFilesPromisePboardType = @"NSFilesPromisePboardType";
NSString *NSMultipleTextSelectionPboardType = @"NSMultipleTextSelectionPboardType";
NSString *NSWorkspaceSessionDidBecomeActiveNotification =
    @"NSWorkspaceSessionDidBecomeActiveNotification";
NSString *NSWorkspaceSessionDidResignActiveNotification =
    @"NSWorkspaceSessionDidResignActiveNotification";
NSString *NSAccessibilityResizedNotification = @"NSAccessibilityResizedNotification";
NSString *NSAccessibilitySelectedTextRangesAttribute =
    @"NSAccessibilitySelectedTextRangesAttribute";
id NSMultipleValuesMarker;

static NSColor *snowTextSelectionColor(NSColor *color) {
    /* On OPENSTEP selectedControlColor is white. Cocoa used that catalog
     * entry for document selection; use the native document highlight. */
    if ([[color colorSpaceName] isEqual:NSNamedColorSpace] &&
        [[color catalogNameComponent] isEqual:@"System"] &&
        [[color colorNameComponent] isEqual:@"selectedControlColor"])
        return
            [[NSColor selectedTextBackgroundColor] colorWithAlphaComponent:[color alphaComponent]];
    return color;
}

NSArray *NSSearchPathForDirectoriesInDomains(unsigned directory, unsigned domains, BOOL expand) {
    NSMutableArray *paths = [NSMutableArray array];
    NSString *relative = nil;
    unsigned domain;
    switch (directory) {
    case 1:
        relative = @"Apps";
        break;
    case 5:
        relative = @"Library";
        break;
    case 9:
        relative = @"Documents";
        break;
    case 12:
        relative = @"Desktop";
        break;
    case 13:
        relative = @"Library/Caches";
        break;
    case 14:
        relative = @"Library/Application Support";
        break;
    case 15:
        relative = @"Downloads";
        break;
    default:
        return paths;
    }
    for (domain = 1; domain <= 8; domain <<= 1)
        if (domains & domain) {
            NSString *base =
                domain == 1 ? @"~"
                            : (domain == 2 ? @"/LocalLibrary"
                                           : (domain == 4 ? @"/Net/Library" : @"/NextLibrary"));
            NSString *path;
            if (domain == 1)
                path = [base stringByAppendingPathComponent:relative];
            else if (directory == 1)
                path = domain == 2 ? @"/LocalApps" : (domain == 4 ? @"/Net/Apps" : @"/NextApps");
            else if ([relative hasPrefix:@"Library"])
                path = [base stringByAppendingString:[relative substringFromIndex:7]];
            else
                continue;
            [paths addObject:expand ? [path stringByExpandingTildeInPath] : path];
        }
    return paths;
}

@implementation NSNumber (SnowInteger)
+ (id)numberWithInteger:(int)value {
    return [self numberWithInt:value];
}
+ (id)numberWithUnsignedInteger:(unsigned)value {
    return [self numberWithUnsignedInt:value];
}
- (int)integerValue {
    return [self intValue];
}
- (unsigned)unsignedIntegerValue {
    return [self unsignedIntValue];
}
@end
@implementation NSString (SnowInteger)
- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)target
                                        withString:(NSString *)replacement {
    NSMutableString *result = [NSMutableString string];
    unsigned cursor = 0, length = [self length];
    if (!target || !replacement)
        [NSException raise:NSInvalidArgumentException
                    format:@"Replacement strings must not be nil"];
    if (![target length])
        return [[self retain] autorelease];
    while (cursor < length) {
        NSRange found = [self rangeOfString:target
                                    options:0
                                      range:NSMakeRange(cursor, length - cursor)];
        if (found.location == NSNotFound)
            break;
        [result
            appendString:[self substringWithRange:NSMakeRange(cursor, found.location - cursor)]];
        [result appendString:replacement];
        cursor = NSMaxRange(found);
    }
    [result appendString:[self substringFromIndex:cursor]];
    return result;
}
- (NSString *)stringByTrimmingCharactersInSet:(NSCharacterSet *)set {
    unsigned first = 0, last = [self length];
    while (first < last && [set characterIsMember:[self characterAtIndex:first]])
        first++;
    while (last > first && [set characterIsMember:[self characterAtIndex:last - 1]])
        last--;
    return [self substringWithRange:NSMakeRange(first, last - first)];
}
- initWithBytesNoCopy:(void *)bytes
               length:(unsigned)length
             encoding:(unsigned)encoding
         freeWhenDone:(BOOL)freeWhenDone {
    id result = nil;
    NS_DURING
        result = [self initWithData:[NSData dataWithBytes:bytes length:length] encoding:encoding];
    NS_HANDLER
        if (freeWhenDone)
            free(bytes);
        [localException raise];
    NS_ENDHANDLER
    if (freeWhenDone)
        free(bytes);
    return result;
}
+ (id)stringWithCString:(const char *)bytes encoding:(unsigned)encoding {
    return [[[self alloc] initWithCString:bytes encoding:encoding] autorelease];
}
- initWithBytes:(const void *)bytes length:(unsigned)length encoding:(unsigned)encoding {
    return [self initWithData:[NSData dataWithBytes:bytes length:length] encoding:encoding];
}
- (unsigned)lengthOfBytesUsingEncoding:(unsigned)encoding {
    return [[self dataUsingEncoding:encoding] length];
}
- (int)localizedCompare:(NSString *)other {
    return [self compare:other];
}
- (int)localizedCaseInsensitiveCompare:(NSString *)other {
    return [self caseInsensitiveCompare:other];
}
- (int)integerValue {
    return [self intValue];
}
- (unsigned)unsignedIntegerValue {
    return strtoul([self cString], NULL, 10);
}
- (unsigned)unsignedIntValue {
    return strtoul([self cString], NULL, 10);
}
- (BOOL)boolValue {
    return [self intValue] != 0 || [self hasPrefix:@"Y"] || [self hasPrefix:@"y"] ||
           [self hasPrefix:@"T"] || [self hasPrefix:@"t"];
}
@end
@implementation NSUserDefaults (SnowInteger)
- (id)valueForKey:(NSString *)key {
    return [self objectForKey:key];
}
- (void)setValue:(id)value forKey:(NSString *)key {
    [self setObject:value forKey:key];
}
- (int)integerForKey:(NSString *)key {
    return [[self objectForKey:key] intValue];
}
- (void)setInteger:(int)value forKey:(NSString *)key {
    [self setObject:[NSNumber numberWithInt:value] forKey:key];
}
- (double)doubleForKey:(NSString *)key {
    return [[self objectForKey:key] doubleValue];
}
- (void)setDouble:(double)value forKey:(NSString *)key {
    [self setObject:[NSNumber numberWithDouble:value] forKey:key];
}
- (NSDictionary *)dictionaryForKey:(NSString *)key {
    id value = [self objectForKey:key];
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}
- (NSArray *)arrayForKey:(NSString *)key {
    id value = [self objectForKey:key];
    return [value isKindOfClass:[NSArray class]] ? value : nil;
}
- (NSData *)dataForKey:(NSString *)key {
    id value = [self objectForKey:key];
    return [value isKindOfClass:[NSData class]] ? value : nil;
}
- (NSString *)stringForKey:(NSString *)key {
    id value = [self objectForKey:key];
    if ([value isKindOfClass:[NSString class]])
        return value;
    return [value isKindOfClass:[NSNumber class]] ? [value stringValue] : nil;
}
- (NSArray *)stringArrayForKey:(NSString *)key {
    NSArray *value = [self arrayForKey:key];
    unsigned i;
    for (i = 0; i < [value count]; i++)
        if (![[value objectAtIndex:i] isKindOfClass:[NSString class]])
            return nil;
    return value;
}
- (BOOL)boolForKey:(NSString *)key {
    return [[self objectForKey:key] boolValue];
}
- (float)floatForKey:(NSString *)key {
    return [[self objectForKey:key] floatValue];
}
- (void)setBool:(BOOL)value forKey:(NSString *)key {
    [self setObject:[NSNumber numberWithBool:value] forKey:key];
}
- (void)setFloat:(float)value forKey:(NSString *)key {
    [self setObject:[NSNumber numberWithFloat:value] forKey:key];
}
@end

static IMP snowDefaultsSetObject;
static IMP snowDefaultsObjectForKey;
static const char snowDefaultsMagic[] = "SnowDefaultsArchive1";
static BOOL snowIsNativePlist(id value) {
    NSEnumerator *items;
    id item;
    if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSData class]])
        return YES;
    if ([value isKindOfClass:[NSArray class]])
        items = [value objectEnumerator];
    else if ([value isKindOfClass:[NSDictionary class]])
        items = [value objectEnumerator];
    else
        return NO;
    while ((item = [items nextObject]))
        if (!snowIsNativePlist(item))
            return NO;
    return YES;
}
static void snowSetDefault(id object, SEL action, id value, id key) {
    if (value) {
        if (!snowIsNativePlist(value)) {
            NSMutableData *data = [NSMutableData dataWithBytes:snowDefaultsMagic
                                                        length:sizeof(snowDefaultsMagic)];
            [data appendData:[NSArchiver archivedDataWithRootObject:value]];
            value = data;
        }
        ((void (*)(id, SEL, id, id))snowDefaultsSetObject)(object, action, value, key);
    } else
        [object removeObjectForKey:key];
}
static id snowDecodeDefault(id value) {
    if ([value isKindOfClass:[NSData class]] && [value length] > sizeof(snowDefaultsMagic) &&
        !memcmp([value bytes], snowDefaultsMagic, sizeof(snowDefaultsMagic)))
        return [NSUnarchiver
            unarchiveObjectWithData:[value subdataWithRange:NSMakeRange(
                                                                sizeof(snowDefaultsMagic),
                                                                [value length] -
                                                                    sizeof(snowDefaultsMagic))]];
    return value;
}
static id snowGetDefault(id object, SEL action, id key) {
    id value =
        snowDecodeDefault(((id(*)(id, SEL, id))snowDefaultsObjectForKey)(object, action, key));
    /* Cocoa callers can remove a defaults entry and then reinsert the returned
     * value. Native defaults release their borrowed value during removal. */
    return [[value retain] autorelease];
}
/* Keep native framework copies untouched. Only translated call sites use the
 * modern shallow collection semantics below. */
id SnowCopyObject(id object, NSZone *zone, BOOL mutable) {
    if ([object isKindOfClass:[NSArray class]])
        return [[(mutable ? [NSMutableArray class] : [NSArray class]) allocWithZone:zone]
            initWithArray:object];
    if ([object isKindOfClass:[NSDictionary class]])
        return [[(mutable ? [NSMutableDictionary class] : [NSDictionary class]) allocWithZone:zone]
            initWithDictionary:object];
    return mutable ? [object mutableCopyWithZone:zone] : [object copyWithZone:zone];
}
@implementation NSObject (SnowCollectionCopy)
- (id)snowCopy {
    return SnowCopyObject(self, NULL, NO);
}
- (id)snowMutableCopy {
    return SnowCopyObject(self, NULL, YES);
}
- (id)snowCopyWithZone:(NSZone *)zone {
    return SnowCopyObject(self, zone, NO);
}
- (id)snowMutableCopyWithZone:(NSZone *)zone {
    return SnowCopyObject(self, zone, YES);
}
@end
void SnowInitializeFoundation(void) {
    Method method = class_getInstanceMethod([NSUserDefaults class], @selector(setObject:forKey:));
    snowDefaultsSetObject = method->method_imp;
    method->method_imp = (IMP)snowSetDefault;
    method = class_getInstanceMethod([NSUserDefaults class], @selector(objectForKey:));
    snowDefaultsObjectForKey = method->method_imp;
    method->method_imp = (IMP)snowGetDefault;
    NSMultipleValuesMarker = [[NSObject alloc] init];
}

@interface NSNull : NSObject <NSCopying>
+ (id)null;
@end
@implementation NSNull
+ (id)null {
    static id value;
    if (!value)
        value = [[self alloc] init];
    return value;
}
- copyWithZone:(NSZone *)zone {
    return [self retain];
}
- (NSString *)description {
    return @"<null>";
}
@end

static const char *snowValueType(const char *type) {
    while (*type && strchr("rnNoORV", *type))
        type++;
    return type;
}
static id snowBoxValue(const void *bytes, const char *type) {
    type = snowValueType(type);
    switch (*type) {
    case '@':
    case '#':
        return *(id *)bytes;
    case 'c':
        return [NSNumber numberWithChar:*(char *)bytes];
    case 'C':
    case 'B':
        return [NSNumber numberWithUnsignedChar:*(unsigned char *)bytes];
    case 's':
        return [NSNumber numberWithShort:*(short *)bytes];
    case 'S':
        return [NSNumber numberWithUnsignedShort:*(unsigned short *)bytes];
    case 'i':
    case 'l':
        return [NSNumber numberWithInt:*(int *)bytes];
    case 'I':
    case 'L':
        return [NSNumber numberWithUnsignedInt:*(unsigned *)bytes];
    case 'q':
        return [NSNumber numberWithLongLong:*(long long *)bytes];
    case 'Q':
        return [NSNumber numberWithUnsignedLongLong:*(unsigned long long *)bytes];
    case 'f':
        return [NSNumber numberWithFloat:*(float *)bytes];
    case 'd':
        return [NSNumber numberWithDouble:*(double *)bytes];
    default:
        return [NSValue value:bytes withObjCType:type];
    }
}
static void snowUnboxValue(id value, void *bytes, const char *type) {
    type = snowValueType(type);
    switch (*type) {
    case '@':
    case '#':
        *(id *)bytes = value;
        break;
    case 'c':
    case 'C':
    case 'B':
        *(char *)bytes = [value intValue];
        break;
    case 's':
    case 'S':
        *(short *)bytes = [value intValue];
        break;
    case 'i':
    case 'l':
    case 'I':
    case 'L':
        *(unsigned *)bytes = [value unsignedIntValue];
        break;
    case 'q':
    case 'Q':
        *(long long *)bytes = [value longLongValue];
        break;
    case 'f':
        *(float *)bytes = [value floatValue];
        break;
    case 'd':
        *(double *)bytes = [value doubleValue];
        break;
    default:
        [value getValue:bytes];
        break;
    }
}
@interface NSObject (SnowKeyValueCoding)
- (id)valueForKey:(NSString *)key;
- (id)valueForKeyPath:(NSString *)path;
- (void)setValue:(id)value forKey:(NSString *)key;
- (void)setValue:(id)value forKeyPath:(NSString *)path;
- (id)valueForUndefinedKey:(NSString *)key;
- (void)setValue:(id)value forUndefinedKey:(NSString *)key;
@end
static NSMutableDictionary *snowDependentKeys;
static unsigned snowDependentKeyGeneration;
/* Mutable KVC proxies must use collection accessors, even when the getter
 * publishes an immutable snapshot of its backing array. */
@interface SnowMutableArrayProxy : NSMutableArray {
    id snowOwner;
    NSString *snowKey;
}
- initWithObject:(id)object key:(NSString *)key;
@end
@implementation SnowMutableArrayProxy
- initWithObject:(id)object key:(NSString *)key {
    self = [super init];
    snowOwner = [object retain];
    snowKey = [key copy];
    return self;
}
- (unsigned)count {
    return [[snowOwner valueForKey:snowKey] count];
}
- (id)objectAtIndex:(unsigned)index {
    return [[snowOwner valueForKey:snowKey] objectAtIndex:index];
}
- (NSString *)capitalKey {
    return [[[snowKey substringToIndex:1] uppercaseString]
        stringByAppendingString:[snowKey substringFromIndex:1]];
}
- (void)insertObject:(id)value atIndex:(unsigned)index {
    SEL selector = NSSelectorFromString(
        [NSString stringWithFormat:@"insertObject:in%@AtIndex:", [self capitalKey]]);
    if ([snowOwner respondsToSelector:selector])
        ((void (*)(id, SEL, id, unsigned))[snowOwner methodForSelector:selector])(
            snowOwner, selector, value, index);
    else {
        NSMutableArray *array =
            [[NSMutableArray alloc] initWithArray:[snowOwner valueForKey:snowKey]];
        [array insertObject:value atIndex:index];
        [snowOwner setValue:array forKey:snowKey];
        [array release];
    }
}
- (void)removeObjectAtIndex:(unsigned)index {
    SEL selector = NSSelectorFromString(
        [NSString stringWithFormat:@"removeObjectFrom%@AtIndex:", [self capitalKey]]);
    if ([snowOwner respondsToSelector:selector])
        ((void (*)(id, SEL, unsigned))[snowOwner methodForSelector:selector])(snowOwner, selector,
                                                                              index);
    else {
        NSMutableArray *array =
            [[NSMutableArray alloc] initWithArray:[snowOwner valueForKey:snowKey]];
        [array removeObjectAtIndex:index];
        [snowOwner setValue:array forKey:snowKey];
        [array release];
    }
}
- (void)replaceObjectAtIndex:(unsigned)index withObject:(id)value {
    SEL selector = NSSelectorFromString(
        [NSString stringWithFormat:@"replaceObjectIn%@AtIndex:withObject:", [self capitalKey]]);
    if ([snowOwner respondsToSelector:selector])
        ((void (*)(id, SEL, unsigned, id))[snowOwner methodForSelector:selector])(
            snowOwner, selector, index, value);
    else {
        NSMutableArray *array =
            [[NSMutableArray alloc] initWithArray:[snowOwner valueForKey:snowKey]];
        [array replaceObjectAtIndex:index withObject:value];
        [snowOwner setValue:array forKey:snowKey];
        [array release];
    }
}
- (void)addObject:(id)value {
    [self insertObject:value atIndex:[self count]];
}
- (void)removeLastObject {
    if ([self count])
        [self removeObjectAtIndex:[self count] - 1];
}
- (void)dealloc {
    [snowOwner release];
    [snowKey release];
    [super dealloc];
}
@end
@implementation NSObject (SnowKeyValueCoding)
- (id)valueForKey:(NSString *)key {
    SEL selector;
    Ivar ivar;
    NSString *capital;
    if (![key length])
        return [self valueForUndefinedKey:key];
    if ([key isEqual:@"self"])
        return self;
    capital = [NSString stringWithFormat:@"%@%@", [[key substringToIndex:1] uppercaseString],
                                         [key substringFromIndex:1]];
    selector = NSSelectorFromString([@"get" stringByAppendingString:capital]);
    if (![self respondsToSelector:selector])
        selector = NSSelectorFromString(key);
    if (![self respondsToSelector:selector])
        selector = NSSelectorFromString([@"is" stringByAppendingString:capital]);
    if (![self respondsToSelector:selector])
        selector = NSSelectorFromString([@"_" stringByAppendingString:key]);
    if ([self respondsToSelector:selector]) {
        NSMethodSignature *signature = [self methodSignatureForSelector:selector];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        void *bytes = calloc(1, [signature methodReturnLength] + 16);
        id result;
        [invocation setSelector:selector];
        [invocation invokeWithTarget:self];
        [invocation getReturnValue:bytes];
        result = snowBoxValue(bytes, [signature methodReturnType]);
        free(bytes);
        return result;
    }
    ivar =
        class_getInstanceVariable([self class], [[NSString stringWithFormat:@"_%@", key] cString]);
    if (!ivar)
        ivar = class_getInstanceVariable([self class],
                                         [[@"_is" stringByAppendingString:capital] cString]);
    if (!ivar)
        ivar = class_getInstanceVariable([self class], [key cString]);
    if (!ivar)
        ivar = class_getInstanceVariable([self class],
                                         [[@"is" stringByAppendingString:capital] cString]);
    if (ivar)
        return snowBoxValue((char *)self + ivar->ivar_offset, ivar->ivar_type);
    return [self valueForUndefinedKey:key];
}
- (id)valueForKeyPath:(NSString *)path {
    NSRange dot = [path rangeOfString:@"."];
    if (dot.location == NSNotFound)
        return [self valueForKey:path];
    return [[self valueForKey:[path substringToIndex:dot.location]]
        valueForKeyPath:[path substringFromIndex:dot.location + 1]];
}
- (void)setValue:(id)value forKey:(NSString *)key {
    NSString *name =
        [NSString stringWithFormat:@"set%@%@:", [[key substringToIndex:1] uppercaseString],
                                   [key substringFromIndex:1]];
    SEL selector = NSSelectorFromString(name);
    Ivar ivar;
    if ([self respondsToSelector:selector]) {
        NSMethodSignature *signature = [self methodSignatureForSelector:selector];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        unsigned size, align;
        void *bytes;
        NSGetSizeAndAlignment([signature getArgumentTypeAtIndex:2], &size, &align);
        bytes = calloc(1, size + 16);
        snowUnboxValue(value, bytes, [signature getArgumentTypeAtIndex:2]);
        [invocation setSelector:selector];
        [invocation setArgument:bytes atIndex:2];
        [invocation invokeWithTarget:self];
        free(bytes);
        return;
    }
    ivar =
        class_getInstanceVariable([self class], [[NSString stringWithFormat:@"_%@", key] cString]);
    if (!ivar)
        ivar = class_getInstanceVariable([self class], [key cString]);
    if (ivar) {
        void *bytes = (char *)self + ivar->ivar_offset;
        if (*ivar->ivar_type == '@') {
            [value retain];
            [*(id *)bytes release];
        }
        snowUnboxValue(value, bytes, ivar->ivar_type);
        return;
    }
    [self setValue:value forUndefinedKey:key];
}
- (void)setValue:(id)value forKeyPath:(NSString *)path {
    NSRange dot = [path rangeOfString:@"." options:NSBackwardsSearch];
    if (dot.location == NSNotFound)
        [self setValue:value forKey:path];
    else [[self valueForKeyPath:[path substringToIndex:dot.location]]
        setValue:value
          forKey:[path substringFromIndex:dot.location + 1]]
        ;
}
- (void)takeValue:(id)value forKey:(NSString *)key {
    [self setValue:value forKey:key];
}
- (void)takeValue:(id)value forKeyPath:(NSString *)key {
    [self setValue:value forKeyPath:key];
}
- (id)mutableArrayValueForKey:(NSString *)key {
    return [[[SnowMutableArrayProxy alloc] initWithObject:self key:key] autorelease];
}
- (id)mutableArrayValueForKeyPath:(NSString *)key {
    NSRange dot = [key rangeOfString:@"." options:NSBackwardsSearch];
    if (dot.location == NSNotFound)
        return [self mutableArrayValueForKey:key];
    return [[self valueForKeyPath:[key substringToIndex:dot.location]]
        mutableArrayValueForKey:[key substringFromIndex:dot.location + 1]];
}
- (NSDictionary *)dictionaryWithValuesForKeys:(NSArray *)keys {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    unsigned i;
    for (i = 0; i < [keys count]; i++) {
        id key = [keys objectAtIndex:i], value = [self valueForKey:key];
        [result setObject:value ? value : [NSNull null] forKey:key];
    }
    return result;
}
- (id)valueForUndefinedKey:(NSString *)key {
    [NSException raise:NSInvalidArgumentException
                format:@"Unknown key %@ on %@", key, [self class]];
    return nil;
}
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {
    [NSException raise:NSInvalidArgumentException
                format:@"Unknown key %@ on %@", key, [self class]];
}
- (id)handleQueryWithUnboundKey:(NSString *)key {
    return [self valueForUndefinedKey:key];
}
- (void)handleTakeValue:(id)value forUnboundKey:(NSString *)key {
    [self setValue:value forUndefinedKey:key];
}
+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key {
    return YES;
}
+ (void)setKeys:(NSArray *)keys triggerChangeNotificationsForDependentKey:(NSString *)key {
    NSMutableDictionary *map;
    if (!snowDependentKeys)
        snowDependentKeys = [[NSMutableDictionary alloc] init];
    map = [snowDependentKeys objectForKey:NSStringFromClass(self)];
    if (!map) {
        map = [NSMutableDictionary dictionary];
        [snowDependentKeys setObject:map forKey:NSStringFromClass(self)];
    }
    [map setObject:[NSSet setWithArray:keys] forKey:key];
    snowDependentKeyGeneration++;
}
+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key {
    NSMutableSet *result = [NSMutableSet set];
    Class cls = self;
    while (cls) {
        NSSet *keys = [[snowDependentKeys objectForKey:NSStringFromClass(cls)] objectForKey:key];
        if (keys)
            [result unionSet:keys];
        cls = cls->super_class;
    }
    return result;
}
@end
@implementation NSDictionary (SnowKeyValueCoding)
- (id)valueForKey:(NSString *)key {
    return [self objectForKey:key];
}
@end
@implementation NSMutableDictionary (SnowKeyValueCoding)
- (void)setValue:(id)value forKey:(NSString *)key {
    if (value)
        [self setObject:value forKey:key];
    else
        [self removeObjectForKey:key];
}
@end
@implementation NSArray (SnowKeyValueCoding)
- (id)valueForKey:(NSString *)key {
    NSMutableArray *result = [NSMutableArray array];
    unsigned i;
    if ([key isEqual:@"@count"])
        return [NSNumber numberWithUnsignedInt:[self count]];
    for (i = 0; i < [self count]; i++) {
        id value = [[self objectAtIndex:i] valueForKey:key];
        [result addObject:value ? value : [NSNull null]];
    }
    return result;
}
@end

@implementation NSObject (SnowComparison)
- (BOOL)isEqualTo:(id)object {
    return [self isEqual:object];
}
- (BOOL)isNotEqualTo:(id)object {
    return ![self isEqual:object];
}
- (BOOL)isGreaterThan:(id)object {
    return [self compare:object] == NSOrderedDescending;
}
- (BOOL)isLessThan:(id)object {
    return [self compare:object] == NSOrderedAscending;
}
- (BOOL)isGreaterThanOrEqualTo:(id)object {
    return [self compare:object] != NSOrderedAscending;
}
- (BOOL)isLessThanOrEqualTo:(id)object {
    return [self compare:object] != NSOrderedDescending;
}
@end

@implementation NSNumberFormatter (SnowNumberStyle)
/* The native formatter supplies decimal formatting through format patterns. */
- (void)setFormatterBehavior:(unsigned)value {
    [self setLocalizesFormat:YES];
}
- (void)setNumberStyle:(unsigned)value {
    [self setAllowsFloats:YES];
    [self setHasThousandSeparators:value != 0];
    [self setFormat:@"0.###"];
}
- (void)setMaximumFractionDigits:(unsigned)digits {
    NSMutableString *format = [NSMutableString stringWithString:@"0"];
    unsigned i;
    if (digits > 32)
        digits = 32;
    if (digits)
        [format appendString:@"."];
    for (i = 0; i < digits; i++)
        [format appendString:@"#"];
    [self setFormat:format];
}
- (NSString *)stringFromNumber:(NSNumber *)number {
    return [self stringForObjectValue:number];
}
- (NSNumber *)numberFromString:(NSString *)string {
    id value = nil;
    return [self getObjectValue:&value forString:string errorDescription:NULL] ? value : nil;
}
@end

@interface SnowObservation : NSObject {
  @public
    id object, observer, previous, previousDependencies;
    NSString *path;
    unsigned options;
    BOOL readable, initialized, removed;
    NSSet *dependencyKeys;
    unsigned dependencyGeneration;
    void *context;
}
- (void)check:(BOOL)initial;
- (void)check:(BOOL)initial force:(BOOL)force;
@end
static NSMutableArray *snowObservations;
#ifdef SNOW_TESTING
NSString *SnowTestObservations(id object) {
    NSMutableString *result = [NSMutableString string];
    unsigned i;
    for (i = 0; i < [snowObservations count]; i++) {
        SnowObservation *record = [snowObservations objectAtIndex:i];
        if (record->object == object)
            [result appendFormat:
                        @"observer=%@ path=%@ options=%u context=%x initialized=%d readable=%d\n",
                        [record->observer class], record -> path, record -> options,
                        (unsigned)record -> context, record -> initialized, record -> readable];
    }
    return result;
}
#endif
static BOOL snowCheckingObservations;
static id snowObservationSnapshot(id value) {
    if ([value isKindOfClass:[NSArray class]])
        return [[NSArray alloc] initWithArray:value];
    if ([value isKindOfClass:[NSDictionary class]])
        return [[NSDictionary alloc] initWithDictionary:value];
    if ([value isKindOfClass:[NSString class]] ||
        [value isKindOfClass:NSClassFromString(@"NSIndexSet")])
        return [value snowCopy];
    return [value retain];
}
static NSDictionary *snowObservationDependencies(id object, NSSet *keys) {
    NSEnumerator *iterator;
    NSString *key;
    NSMutableDictionary *values;
    if (![keys count])
        return nil;
    values = [NSMutableDictionary dictionary];
    iterator = [keys objectEnumerator];
    while ((key = [iterator nextObject])) {
        id value = [object valueForKeyPath:key];
        id snapshot = value ? snowObservationSnapshot(value) : [[NSNull null] retain];
        [values setObject:snapshot forKey:key];
        [snapshot release];
    }
    return values;
}
@implementation SnowObservation
- (void)check:(BOOL)initial {
    [self check:initial force:NO];
}
- (void)check:(BOOL)initial force:(BOOL)force {
    id value = nil, dependencies;
    NSMutableDictionary *change;
    id old;
    if (!dependencyKeys || dependencyGeneration != snowDependentKeyGeneration) {
        NSSet *keys = [path rangeOfString:@"."].location == NSNotFound
                          ? [[object class] keyPathsForValuesAffectingValueForKey:path]
                          : [NSSet set];
        [dependencyKeys release];
        dependencyKeys = [keys retain];
        dependencyGeneration = snowDependentKeyGeneration;
    }
    dependencies = snowObservationDependencies(object, dependencyKeys);
    NS_DURING
        if (readable)
            value = [object valueForKeyPath:path];
    NS_HANDLER
        if (options & 3)
            [localException raise];
        readable = NO;
    NS_ENDHANDLER
    if (!initialized && !initial && !force) {
        previous = snowObservationSnapshot(value);
        previousDependencies = [dependencies retain];
        initialized = YES;
        return;
    }
    initialized = YES;
    if (!initial && !force && (!readable || previous == value || [previous isEqual:value]) &&
        (previousDependencies == dependencies || [previousDependencies isEqual:dependencies]))
        return;
    [dependencies retain];
    [previousDependencies release];
    previousDependencies = dependencies;
    old = [previous autorelease];
    previous = snowObservationSnapshot(value);
    change = [NSMutableDictionary dictionaryWithObject:[NSNumber numberWithInt:1]
                                                forKey:NSKeyValueChangeKindKey];
    if (options & 1)
        [change setObject:value ? value : [NSNull null] forKey:NSKeyValueChangeNewKey];
    if ((options & 2) && !initial)
        [change setObject:old ? old : [NSNull null] forKey:NSKeyValueChangeOldKey];
    [observer observeValueForKeyPath:path ofObject:object change:change context:context];
}
- (void)dealloc {
    [previous release];
    [previousDependencies release];
    [dependencyKeys release];
    [path release];
    [super dealloc];
}
@end

static void SnowPrimeObservation(id object, id observer, NSString *path, id value) {
    unsigned i;
    for (i = 0; i < [snowObservations count]; i++) {
        SnowObservation *record = [snowObservations objectAtIndex:i];
        if (record->object == object && record->observer == observer &&
            [record->path isEqual:path]) {
            [record->previous release];
            record->previous = snowObservationSnapshot(value);
            record->initialized = YES;
        }
    }
}

@implementation NSArray (SnowIndexedObservation)
- (void)addObserver:(id)observer
    toObjectsAtIndexes:(id)indexes
            forKeyPath:(NSString *)path
               options:(unsigned)options
               context:(void *)context {
    unsigned index;
    for (index = [indexes firstIndex]; indexes && index != NSNotFound;
         index = [indexes indexGreaterThanIndex:index])
        [[self objectAtIndex:index] addObserver:observer
                                     forKeyPath:path
                                        options:options
                                        context:context];
}
- (void)removeObserver:(id)observer fromObjectsAtIndexes:(id)indexes forKeyPath:(NSString *)path {
    unsigned index;
    for (index = [indexes firstIndex]; indexes && index != NSNotFound;
         index = [indexes indexGreaterThanIndex:index])
        [[self objectAtIndex:index] removeObserver:observer forKeyPath:path];
}
@end
@interface SnowObservationPump : NSObject
+ (void)poll:(id)sender;
@end
@implementation SnowObservationPump
+ (void)poll:(id)sender {
    NSArray *snapshot;
    NSAutoreleasePool *pool;
    unsigned i;
    if (snowCheckingObservations)
        return;
    snowCheckingObservations = YES;
    /* Native timer-only run-loop turns need not drain the application's pool. */
    pool = [[NSAutoreleasePool alloc] init];
    snapshot = [[NSArray alloc] initWithArray:snowObservations];
    NS_DURING
        for (i = 0; i < [snapshot count]; i++) {
            SnowObservation *observation = [snapshot objectAtIndex:i];
            if (!observation->removed)
                [observation check:NO];
        }
    NS_HANDLER
        [localException retain];
        [snapshot release];
        snowCheckingObservations = NO;
        [pool release];
        [[localException autorelease] raise];
    NS_ENDHANDLER
    [snapshot release];
    [pool release];
    snowCheckingObservations = NO;
}
@end
@implementation NSObject (SnowObservation)
- (void)addObserver:(id)observer
         forKeyPath:(NSString *)path
            options:(unsigned)options
            context:(void *)context {
    SnowObservation *record;
    if (!snowObservations) {
        NSTimer *timer;
        snowObservations = [[NSMutableArray alloc] init];
        timer = [NSTimer timerWithTimeInterval:0.1
                                        target:[SnowObservationPump class]
                                      selector:@selector(poll:)
                                      userInfo:nil
                                       repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
        [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSEventTrackingRunLoopMode];
        [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSModalPanelRunLoopMode];
    }
    record = [[[SnowObservation alloc] init] autorelease];
    record->object = self;
    record->observer = observer;
    record->path = [path snowCopy];
    record->options = options;
    record->context = context;
    record->readable = YES;
    /* Registering an observer must not invoke a lazy getter. Stock profile
     * getters register their dependent observers before publishing state. */
    [snowObservations addObject:record];
    if (options & 4)
        [record check:YES];
}
- (void)removeObserver:(id)observer forKeyPath:(NSString *)path {
    int i;
    for (i = [snowObservations count] - 1; i >= 0; i--) {
        SnowObservation *record = [snowObservations objectAtIndex:i];
        if (record->object == self && record->observer == observer && [record->path isEqual:path]) {
            record->removed = YES;
            [snowObservations removeObjectAtIndex:i];
        }
    }
}
- (void)willChangeValueForKey:(NSString *)key {
    NSArray *records = [[NSArray alloc] initWithArray:snowObservations];
    unsigned i;
    for (i = 0; i < [records count]; i++) {
        SnowObservation *record = [records objectAtIndex:i];
        if (record->object == self && !record->initialized && [record->path isEqual:key])
            [record check:NO];
    }
    [records release];
}
- (void)didChangeValueForKey:(NSString *)key {
    NSArray *records = [[NSArray alloc] initWithArray:snowObservations];
    unsigned i;
    for (i = 0; i < [records count]; i++) {
        SnowObservation *record = [records objectAtIndex:i];
        if (record->object == self && [record->path isEqual:key] && !record->removed)
            [record check:NO force:YES];
    }
    [records release];
    [SnowObservationPump poll:nil];
}
- (void)willChange:(unsigned)kind valuesAtIndexes:(id)indexes forKey:(NSString *)key {
}
- (void)didChange:(unsigned)kind valuesAtIndexes:(id)indexes forKey:(NSString *)key {
    [SnowObservationPump poll:nil];
}
@end

@interface NSValueTransformer : NSObject
+ (void)setValueTransformer:(id)transformer forName:(NSString *)name;
+ (id)valueTransformerForName:(NSString *)name;
- (id)transformedValue:(id)value;
- (id)reverseTransformedValue:(id)value;
@end
static NSMutableDictionary *snowTransformers;
@interface SnowNegateBooleanTransformer : NSValueTransformer
@end
@implementation SnowNegateBooleanTransformer
+ (Class)transformedValueClass {
    return [NSNumber class];
}
+ (BOOL)allowsReverseTransformation {
    return YES;
}
- (id)transformedValue:(id)value {
    return [NSNumber numberWithBool:![value boolValue]];
}
- (id)reverseTransformedValue:(id)value {
    return [self transformedValue:value];
}
@end
@implementation NSValueTransformer
+ (void)setValueTransformer:(id)transformer forName:(NSString *)name {
    if (!snowTransformers)
        snowTransformers = [[NSMutableDictionary alloc] init];
    [snowTransformers setObject:transformer forKey:name];
}
+ (id)valueTransformerForName:(NSString *)name {
    id transformer;
    if (!name)
        return nil;
    transformer = [snowTransformers objectForKey:name];
    if (!transformer && [name isEqual:@"NSNegateBoolean"]) {
        transformer = [[[SnowNegateBooleanTransformer alloc] init] autorelease];
        [self setValueTransformer:transformer forName:name];
    }
    return transformer;
}
+ (Class)transformedValueClass {
    return [NSObject class];
}
+ (BOOL)allowsReverseTransformation {
    return NO;
}
- (id)transformedValue:(id)value {
    return value;
}
- (id)reverseTransformedValue:(id)value {
    return value;
}
@end

@interface NSIndexSet : NSObject <NSCopying, NSMutableCopying> {
  @public
    NSMutableSet *snowIndexes;
}
+ (id)indexSet;
+ (id)indexSetWithIndex:(unsigned)index;
- initWithIndex:(unsigned)index;
- initWithIndexesInRange:(NSRange)range;
- (BOOL)containsIndex:(unsigned)index;
- (unsigned)count;
- (unsigned)firstIndex;
- (unsigned)indexGreaterThanIndex:(unsigned)index;
@end
@interface NSMutableIndexSet : NSIndexSet
- (void)addIndex:(unsigned)index;
- (void)removeIndex:(unsigned)index;
@end
@implementation NSIndexSet
- init {
    self = [super init];
    snowIndexes = [[NSMutableSet alloc] init];
    return self;
}
+ (id)indexSet {
    return [[[self alloc] init] autorelease];
}
+ (id)indexSetWithIndex:(unsigned)index {
    return [[[self alloc] initWithIndex:index] autorelease];
}
+ (id)indexSetWithIndexesInRange:(NSRange)range {
    return [[[self alloc] initWithIndexesInRange:range] autorelease];
}
- initWithIndex:(unsigned)index {
    self = [self init];
    [snowIndexes addObject:[NSNumber numberWithUnsignedInt:index]];
    return self;
}
- initWithIndexesInRange:(NSRange)range {
    unsigned i;
    self = [self init];
    for (i = 0; i < range.length; i++)
        [snowIndexes addObject:[NSNumber numberWithUnsignedInt:range.location + i]];
    return self;
}
- (BOOL)containsIndex:(unsigned)index {
    return [snowIndexes containsObject:[NSNumber numberWithUnsignedInt:index]];
}
- (unsigned)count {
    return [snowIndexes count];
}
- (unsigned)rangeCount {
    unsigned index = [self firstIndex], previous = NSNotFound, count = 0;
    while (index != NSNotFound) {
        if (previous == NSNotFound || index != previous + 1)
            count++;
        previous = index;
        index = [self indexGreaterThanIndex:index];
    }
    return count;
}
- (NSRange)rangeAtIndex:(unsigned)wanted {
    unsigned index = [self firstIndex], count = 0;
    NSRange range = NSMakeRange(NSNotFound, 0);
    while (index != NSNotFound) {
        if (range.location == NSNotFound || index != range.location + range.length) {
            if (range.location != NSNotFound && count++ == wanted)
                return range;
            range = NSMakeRange(index, 1);
        } else
            range.length++;
        index = [self indexGreaterThanIndex:index];
    }
    if (range.location != NSNotFound && count == wanted)
        return range;
    [NSException raise:NSRangeException format:@"Index-set range is out of bounds"];
    return NSMakeRange(NSNotFound, 0);
}
- (unsigned)countOfIndexesInRange:(NSRange)range {
    NSEnumerator *items = [snowIndexes objectEnumerator];
    NSNumber *item;
    unsigned count = 0;
    while ((item = [items nextObject])) {
        unsigned index = [item unsignedIntValue];
        if (index >= range.location && index - range.location < range.length)
            count++;
    }
    return count;
}
- (BOOL)intersectsIndexesInRange:(NSRange)range {
    return [self countOfIndexesInRange:range] != 0;
}
- (BOOL)containsIndexesInRange:(NSRange)range {
    return [self countOfIndexesInRange:range] == range.length;
}
- (unsigned)indexGreaterThanOrEqualToIndex:(unsigned)index {
    return [self containsIndex:index] ? index : [self indexGreaterThanIndex:index];
}
- (unsigned)indexLessThanIndex:(unsigned)index {
    NSEnumerator *items = [snowIndexes objectEnumerator];
    NSNumber *item;
    unsigned result = NSNotFound;
    while ((item = [items nextObject])) {
        unsigned value = [item unsignedIntValue];
        if (value < index && (result == NSNotFound || value > result))
            result = value;
    }
    return result;
}
- (unsigned)indexLessThanOrEqualToIndex:(unsigned)index {
    return [self containsIndex:index] ? index : [self indexLessThanIndex:index];
}
- (unsigned)firstIndex {
    return [self indexGreaterThanIndex:NSNotFound];
}
- (unsigned)lastIndex {
    NSEnumerator *e = [snowIndexes objectEnumerator];
    NSNumber *n;
    unsigned result = NSNotFound;
    while ((n = [e nextObject]))
        if (result == NSNotFound || [n unsignedIntValue] > result)
            result = [n unsignedIntValue];
    return result;
}
- (unsigned)indexGreaterThanIndex:(unsigned)index {
    NSEnumerator *e = [snowIndexes objectEnumerator];
    NSNumber *n;
    unsigned result = NSNotFound, value;
    while ((n = [e nextObject])) {
        value = [n unsignedIntValue];
        if ((index == NSNotFound || value > index) && (result == NSNotFound || value < result))
            result = value;
    }
    return result;
}
- copyWithZone:(NSZone *)zone {
    NSIndexSet *other = [[[self class] allocWithZone:zone] init];
    [other->snowIndexes unionSet:snowIndexes];
    return other;
}
- mutableCopyWithZone:(NSZone *)zone {
    NSIndexSet *other = [[NSMutableIndexSet allocWithZone:zone] init];
    [other->snowIndexes unionSet:snowIndexes];
    return other;
}
- (BOOL)isEqual:(id)other {
    return [other isKindOfClass:[NSIndexSet class]] &&
           [snowIndexes isEqual:((NSIndexSet *)other)->snowIndexes];
}
- (void)dealloc {
    [snowIndexes release];
    [super dealloc];
}
@end
@implementation NSMutableIndexSet
- (void)shiftIndexesStartingAtIndex:(unsigned)start by:(int)delta {
    NSMutableSet *shifted = [NSMutableSet set];
    NSEnumerator *items = [snowIndexes objectEnumerator];
    NSNumber *item;
    long long lower = (long long)start + delta;
    while ((item = [items nextObject])) {
        unsigned index = [item unsignedIntValue];
        long long destination = index;
        if (index >= start)
            destination += delta;
        else if (delta < 0 && (long long)index >= lower)
            continue;
        if (destination < 0)
            continue;
        if (destination >= NSNotFound)
            [NSException raise:NSRangeException format:@"Shifted index is out of range"];
        [shifted addObject:[NSNumber numberWithUnsignedInt:(unsigned)destination]];
    }
    [snowIndexes setSet:shifted];
}
- (void)addIndexes:(NSIndexSet *)indexes {
    [snowIndexes unionSet:indexes->snowIndexes];
}
- (void)removeIndexes:(NSIndexSet *)indexes {
    [snowIndexes minusSet:indexes->snowIndexes];
}
- (void)removeIndexesInRange:(NSRange)range {
    NSArray *items = [snowIndexes allObjects];
    unsigned i;
    for (i = 0; i < [items count]; i++) {
        NSNumber *item = [items objectAtIndex:i];
        unsigned index = [item unsignedIntValue];
        if (index >= range.location && index - range.location < range.length)
            [snowIndexes removeObject:item];
    }
}
- (void)addIndex:(unsigned)index {
    [snowIndexes addObject:[NSNumber numberWithUnsignedInt:index]];
}
- (void)removeIndex:(unsigned)index {
    [snowIndexes removeObject:[NSNumber numberWithUnsignedInt:index]];
}
- (void)addIndexesInRange:(NSRange)range {
    unsigned i;
    for (i = 0; i < range.length; i++)
        [self addIndex:range.location + i];
}
- (void)removeAllIndexes {
    [snowIndexes removeAllObjects];
}
@end

@interface NSError : NSObject {
    NSString *snowDomain;
    int snowCode;
    NSDictionary *snowInfo;
}
+ (id)errorWithDomain:(NSString *)domain code:(int)code userInfo:(NSDictionary *)info;
- (NSString *)localizedDescription;
@end
@implementation NSError
+ (id)errorWithDomain:(NSString *)domain code:(int)code userInfo:(NSDictionary *)info {
    NSError *value = [[[self alloc] init] autorelease];
    value->snowDomain = [domain snowCopy];
    value->snowCode = code;
    value->snowInfo = [info snowCopy];
    return value;
}
- (NSString *)domain {
    return snowDomain;
}
- (int)code {
    return snowCode;
}
- (NSDictionary *)userInfo {
    return snowInfo;
}
- (NSString *)localizedDescription {
    return [snowInfo objectForKey:NSLocalizedDescriptionKey]
               ? [snowInfo objectForKey:NSLocalizedDescriptionKey]
               : [NSString stringWithFormat:@"%@ error %d", snowDomain, snowCode];
}
- (NSString *)localizedRecoverySuggestion {
    return [snowInfo objectForKey:NSLocalizedRecoverySuggestionErrorKey];
}
- (void)dealloc {
    [snowDomain release];
    [snowInfo release];
    [super dealloc];
}
@end

@interface NSLocale : NSObject
+ (id)currentLocale;
- (id)objectForKey:(NSString *)key;
@end
@implementation NSLocale
+ (id)currentLocale {
    static id locale;
    if (!locale)
        locale = [[self alloc] init];
    return locale;
}
- initWithLocaleIdentifier:(NSString *)identifier {
    return [self init];
}
- (id)objectForKey:(NSString *)key {
    if ([key isEqual:NSLocaleCountryCode])
        return @"US";
    if ([key isEqual:NSLocaleLanguageCode])
        return @"en";
    if ([key isEqual:NSLocaleIdentifier])
        return @"en_US";
    return nil;
}
- (NSString *)localeIdentifier {
    return @"en_US";
}
@end

@interface NSSortDescriptor : NSObject {
    NSString *snowKey;
    SEL snowSelector;
    BOOL snowAscending;
}
- initWithKey:(NSString *)key ascending:(BOOL)ascending;
- initWithKey:(NSString *)key ascending:(BOOL)ascending selector:(SEL)selector;
- (int)compareObject:(id)a toObject:(id)b;
@end
@implementation NSSortDescriptor
- initWithKey:(NSString *)key ascending:(BOOL)ascending {
    return [self initWithKey:key ascending:ascending selector:@selector(compare:)];
}
- initWithKey:(NSString *)key ascending:(BOOL)ascending selector:(SEL)selector {
    self = [super init];
    snowKey = [key snowCopy];
    snowAscending = ascending;
    snowSelector = selector;
    return self;
}
- (int)compareObject:(id)a toObject:(id)b {
    int value;
    if (snowKey) {
        a = [a valueForKeyPath:snowKey];
        b = [b valueForKeyPath:snowKey];
    }
    value = (int)[a performSelector:snowSelector withObject:b];
    return snowAscending ? value : -value;
}
- (NSString *)key {
    return snowKey;
}
- (BOOL)ascending {
    return snowAscending;
}
- (void)dealloc {
    [snowKey release];
    [super dealloc];
}
@end
static int snowCompareDescriptors(id a, id b, void *context) {
    NSArray *descriptors = context;
    unsigned i;
    for (i = 0; i < [descriptors count]; i++) {
        int result = [[descriptors objectAtIndex:i] compareObject:a toObject:b];
        if (result)
            return result;
    }
    return 0;
}
@implementation NSArray (SnowSorting)
- (NSArray *)sortedArrayUsingDescriptors:(NSArray *)descriptors {
    return [self sortedArrayUsingFunction:snowCompareDescriptors context:descriptors];
}
- (NSArray *)objectsAtIndexes:(NSIndexSet *)indexes {
    NSMutableArray *result = [NSMutableArray array];
    unsigned index;
    for (index = [indexes firstIndex]; index != NSNotFound;
         index = [indexes indexGreaterThanIndex:index])
        [result addObject:[self objectAtIndex:index]];
    return result;
}
@end
@implementation NSMutableArray (SnowSorting)
- (void)sortUsingDescriptors:(NSArray *)descriptors {
    [self sortUsingFunction:snowCompareDescriptors context:descriptors];
}
@end

@implementation NSUserDefaults (SnowKeyValueCoding)
- (id)valueForKey:(NSString *)key {
    return [self objectForKey:key];
}
- (void)setValue:(id)value forKey:(NSString *)key {
    if (value)
        [self setObject:value forKey:key];
    else
        [self removeObjectForKey:key];
}
@end
@interface NSUserDefaultsController : NSObject {
    NSDictionary *snowInitialValues;
}
+ (id)sharedUserDefaultsController;
- (id)values;
@end
@implementation NSUserDefaultsController
+ (id)sharedUserDefaultsController {
    static id controller;
    if (!controller)
        controller = [[self alloc] init];
    return controller;
}
- (id)values {
    return [NSUserDefaults standardUserDefaults];
}
- (id)defaults {
    return [NSUserDefaults standardUserDefaults];
}
- (void)setInitialValues:(NSDictionary *)values {
    [values retain];
    [snowInitialValues release];
    snowInitialValues = values;
    [[NSUserDefaults standardUserDefaults] registerDefaults:values];
}
- (id)initialValues {
    return snowInitialValues;
}
- (BOOL)appliesImmediately {
    return YES;
}
- (void)save:(id)sender {
    [[NSUserDefaults standardUserDefaults] synchronize];
}
- (void)revertToInitialValues:(id)sender {
    NSEnumerator *keys = [snowInitialValues keyEnumerator];
    id key;
    while ((key = [keys nextObject]))
        [[NSUserDefaults standardUserDefaults] setObject:[snowInitialValues objectForKey:key]
                                                  forKey:key];
}
- (void)dealloc {
    [snowInitialValues release];
    [super dealloc];
}
@end

@implementation NSString (SnowFileContents)
- initWithContentsOfFile:(NSString *)path encoding:(unsigned)encoding error:(id *)error {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        if (error)
            *error = [NSError errorWithDomain:@"NSPOSIXErrorDomain" code:errno userInfo:nil];
        [self release];
        return nil;
    }
    self = [self initWithData:data encoding:encoding];
    if (!self && error)
        *error = [NSError errorWithDomain:@"NSCocoaErrorDomain" code:261 userInfo:nil];
    return self;
}
+ (id)stringWithContentsOfFile:(NSString *)path encoding:(unsigned)encoding error:(id *)error {
    return [[[self alloc] initWithContentsOfFile:path encoding:encoding error:error] autorelease];
}
- (BOOL)writeToFile:(NSString *)path
         atomically:(BOOL)atomic
           encoding:(unsigned)encoding
              error:(id *)error {
    NSData *data = [self dataUsingEncoding:encoding];
    if (!data) {
        if (error)
            *error = [NSError errorWithDomain:@"NSCocoaErrorDomain" code:517 userInfo:nil];
        return NO;
    }
    if ([data writeToFile:path atomically:atomic])
        return YES;
    if (error)
        *error = [NSError errorWithDomain:@"NSPOSIXErrorDomain" code:errno userInfo:nil];
    return NO;
}
@end

@implementation NSFileManager (SnowFiles)
- (NSDictionary *)attributesOfItemAtPath:(NSString *)path error:(id *)error {
    NSDictionary *attributes = [self fileAttributesAtPath:path traverseLink:YES];
    if (!attributes && error)
        *error = [NSError errorWithDomain:@"NSPOSIXErrorDomain" code:errno userInfo:nil];
    return attributes;
}
- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path error:(id *)error {
    NSArray *contents = [self directoryContentsAtPath:path];
    if (!contents && error)
        *error = [NSError errorWithDomain:@"NSPOSIXErrorDomain" code:errno userInfo:nil];
    return contents;
}
- (BOOL)removeItemAtPath:(NSString *)path error:(id *)error {
    if ([self removeFileAtPath:path handler:nil])
        return YES;
    if (error)
        *error = [NSError errorWithDomain:@"NSPOSIXErrorDomain" code:errno userInfo:nil];
    return NO;
}
@end
