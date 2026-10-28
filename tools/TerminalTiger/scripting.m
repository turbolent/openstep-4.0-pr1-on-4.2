/* In-process Apple-event values and Terminal's script-suite metadata.
 * OPENSTEP has no Apple Event Manager; this does not install a script server. */
#import <Foundation/Foundation.h>

@interface NSAppleEventDescriptor : NSObject {
    unsigned tigerDescriptorType;
    NSData *tigerDescriptorData;
    NSMutableArray *tigerDescriptorList;
    NSMutableDictionary *tigerDescriptorRecord;
}
+ (id)descriptorWithDescriptorType:(unsigned)type data:(NSData *)data;
+ (id)listDescriptor;
+ (id)recordDescriptor;
- (unsigned)descriptorType;
- (NSData *)data;
- (int)numberOfItems;
- (void)insertDescriptor:(id)descriptor atIndex:(int)index;
- (id)descriptorAtIndex:(int)index;
- (void)setDescriptor:(id)descriptor forKeyword:(unsigned)keyword;
- (id)descriptorForKeyword:(unsigned)keyword;
@end
@implementation NSAppleEventDescriptor
+ (id)descriptorWithDescriptorType:(unsigned)type data:(NSData *)data {
    NSAppleEventDescriptor *value = [[[self alloc] init] autorelease];
    value->tigerDescriptorType = type;
    value->tigerDescriptorData = [data copy];
    return value;
}
+ (id)listDescriptor {
    NSAppleEventDescriptor *value = [self descriptorWithDescriptorType:0x6c697374 data:nil];
    value->tigerDescriptorList = [[NSMutableArray alloc] init];
    return value;
}
+ (id)recordDescriptor {
    NSAppleEventDescriptor *value = [self descriptorWithDescriptorType:0x7265636f data:nil];
    value->tigerDescriptorRecord = [[NSMutableDictionary alloc] init];
    return value;
}
- (unsigned)descriptorType {
    return tigerDescriptorType;
}
- (NSData *)data {
    return tigerDescriptorData;
}
- (int)numberOfItems {
    return tigerDescriptorList ? [tigerDescriptorList count] : [tigerDescriptorRecord count];
}
- (void)insertDescriptor:(id)descriptor atIndex:(int)index {
    if (!tigerDescriptorList || !descriptor || index < 0 ||
        index > (int)[tigerDescriptorList count] + 1)
        [NSException raise:NSInvalidArgumentException format:@"Invalid Apple-event list insertion"];
    [tigerDescriptorList insertObject:descriptor
                              atIndex:index ? index - 1 : [tigerDescriptorList count]];
}
- (id)descriptorAtIndex:(int)index {
    return index > 0 && index <= (int)[tigerDescriptorList count]
               ? [tigerDescriptorList objectAtIndex:index - 1]
               : nil;
}
- (void)setDescriptor:(id)descriptor forKeyword:(unsigned)keyword {
    if (tigerDescriptorRecord && descriptor)
        [tigerDescriptorRecord setObject:descriptor
                                  forKey:[NSNumber numberWithUnsignedInt:keyword]];
}
- (id)descriptorForKeyword:(unsigned)keyword {
    return [tigerDescriptorRecord objectForKey:[NSNumber numberWithUnsignedInt:keyword]];
}
- (void)dealloc {
    [tigerDescriptorData release];
    [tigerDescriptorList release];
    [tigerDescriptorRecord release];
    [super dealloc];
}
@end

@interface NSScriptClassDescription : NSObject {
    NSDictionary *tigerScriptAttributes;
}
@end
@implementation NSScriptClassDescription
+ (id)classDescriptionForClass:(Class)class {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"Terminal" ofType:@"scriptSuite"];
    NSDictionary *suite = [NSDictionary dictionaryWithContentsOfFile:path];
    NSDictionary *definition =
        [[suite objectForKey:@"Classes"] objectForKey:NSStringFromClass(class)];
    NSScriptClassDescription *value;
    if (!definition)
        return nil;
    value = [[[self alloc] init] autorelease];
    value->tigerScriptAttributes = [[definition objectForKey:@"Attributes"] retain];
    return value;
}
- (NSString *)typeForKey:(NSString *)key {
    return [[tigerScriptAttributes objectForKey:key] objectForKey:@"Type"];
}
- (unsigned)appleEventCodeForKey:(NSString *)key {
    NSString *code = [[tigerScriptAttributes objectForKey:key] objectForKey:@"AppleEventCode"];
    unsigned i, result = 0;
    if ([code length] != 4)
        return 0;
    for (i = 0; i < 4; i++)
        result = (result << 8) | ([code characterAtIndex:i] & 255);
    return result;
}
- (NSArray *)attributeKeys {
    return [tigerScriptAttributes allKeys];
}
- (void)dealloc {
    [tigerScriptAttributes release];
    [super dealloc];
}
@end

/* The original DoScriptVerb/GetURLCommand subclasses expect a 40-byte base.
 * They can be invoked in-process; there is no external AppleScript transport. */
@interface NSScriptCommand : NSObject {
    NSDictionary *tigerScriptArguments;
    id tigerScriptDirectParameter;
    NSString *tigerScriptErrorString;
    int tigerScriptError;
    char tigerScriptReserved[20];
}
@end
@implementation NSScriptCommand
- (NSDictionary *)evaluatedArguments {
    return tigerScriptArguments ? tigerScriptArguments : [NSDictionary dictionary];
}
- (void)setArguments:(NSDictionary *)arguments {
    [arguments retain];
    [tigerScriptArguments release];
    tigerScriptArguments = arguments;
}
- (id)directParameter {
    return tigerScriptDirectParameter;
}
- (void)setDirectParameter:(id)parameter {
    [parameter retain];
    [tigerScriptDirectParameter release];
    tigerScriptDirectParameter = parameter;
}
- (void)setScriptErrorNumber:(int)number {
    tigerScriptError = number;
}
- (int)scriptErrorNumber {
    return tigerScriptError;
}
- (void)setScriptErrorString:(NSString *)string {
    [string retain];
    [tigerScriptErrorString release];
    tigerScriptErrorString = string;
}
- (NSString *)scriptErrorString {
    return tigerScriptErrorString;
}
- (id)performDefaultImplementation {
    [self setScriptErrorNumber:-1708];
    [self setScriptErrorString:@"This command is not handled on OPENSTEP."];
    return nil;
}
- (id)executeCommand {
    return [self performDefaultImplementation];
}
- (void)dealloc {
    [tigerScriptArguments release];
    [tigerScriptDirectParameter release];
    [tigerScriptErrorString release];
    [super dealloc];
}
@end
