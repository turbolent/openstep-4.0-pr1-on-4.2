/* Core Foundation entry points shared with Foundation objects. */
NSString *kCFPreferencesAnyHost = @"AnyHost";
NSString *kCFPreferencesCurrentApplication = @"CurrentApplication";
NSString *kCFPreferencesCurrentUser = @"CurrentUser";
NSString *kLSQuarantineAgentNameKey = @"LSQuarantineAgentName";
double CFAbsoluteTimeGetCurrent(void) {
    return [NSDate timeIntervalSinceReferenceDate];
}
int CFArrayGetCount(NSArray *array) {
    return [array count];
}
id CFArrayGetValueAtIndex(NSArray *array, int index) {
    return [array objectAtIndex:index];
}
id CFDictionaryGetValue(NSDictionary *dictionary, id key) {
    return [dictionary objectForKey:key];
}
unsigned CFHash(id object) {
    return [object hash];
}
id CFLocaleCopyCurrent(void) {
    return [[NSLocale currentLocale] retain];
}
void CFStringGetCharacters(NSString *string, NSRange range, unichar *characters) {
    [string getCharacters:characters range:range];
}
const unichar *CFStringGetCharactersPtr(NSString *string) {
    return NULL;
}
unsigned CFStringGetMostCompatibleMacStringEncoding(unsigned encoding) {
    return 0;
}
const unsigned *CFStringGetListOfAvailableEncodings(void) {
    static unsigned encodings[] = {0,     0x100, 0x201,     0x500,     0x600,
                                   0x820, 0xa01, 0x8000100, 0xffffffff};
    return encodings;
}
static NSDictionary *snowPreferences(NSString *application) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *stored = [application isEqual:kCFPreferencesCurrentApplication]
                               ? [defaults dictionaryRepresentation]
                               : [defaults persistentDomainForName:application];
    NSMutableDictionary *decoded = [NSMutableDictionary dictionary];
    NSEnumerator *keys = [stored keyEnumerator];
    id key, value;
    while ((key = [keys nextObject])) {
        value = snowDecodeDefault([stored objectForKey:key]);
        if (value)
            [decoded setObject:value forKey:key];
    }
    return decoded;
}
id CFPreferencesCopyKeyList(id application, id user, id host) {
    return [[snowPreferences(application) allKeys] snowCopy];
}
id CFPreferencesCopyMultiple(NSArray *keys, id application, id user, id host) {
    NSDictionary *source = snowPreferences(application);
    NSMutableDictionary *result;
    unsigned i;
    if (!keys)
        return [source snowCopy];
    result = [[NSMutableDictionary alloc] init];
    for (i = 0; i < [keys count]; i++) {
        id key = [keys objectAtIndex:i], value = [source objectForKey:key];
        if (value)
            [result setObject:value forKey:key];
    }
    return result;
}
id CFUUIDCreate(void *allocator) {
    struct timeval time;
    unsigned words[4];
    static unsigned sequence;
    gettimeofday(&time, NULL);
    words[0] = time.tv_sec;
    words[1] = time.tv_usec;
    words[2] = getpid();
    words[3] = ++sequence;
    ((unsigned char *)words)[6] = (((unsigned char *)words)[6] & 15) | 0x40;
    ((unsigned char *)words)[8] = (((unsigned char *)words)[8] & 63) | 0x80;
    return [[NSData alloc] initWithBytes:words length:16];
}
typedef struct {
    unsigned char bytes[16];
} SnowUUIDBytes;
id CFUUIDCreateFromUUIDBytes(void *allocator, SnowUUIDBytes bytes) {
    return [[NSData alloc] initWithBytes:bytes.bytes length:16];
}
void SnowUUIDBytesWrite(SnowUUIDBytes *out, NSData *uuid) {
    memset(out, 0, 16);
    [uuid getBytes:out length:16];
}
asm(".text\n.align 2\n.globl _CFUUIDGetUUIDBytes\n_CFUUIDGetUUIDBytes:\n"
    "pushl %ebp\nmovl %esp,%ebp\npushl 12(%ebp)\npushl 8(%ebp)\ncall _SnowUUIDBytesWrite\nmovl 8(%ebp),%eax\nleave\nret $4\n");
id CFUUIDCreateString(void *allocator, NSData *uuid) {
    const unsigned char *b = [uuid bytes];
    return [[NSString alloc]
        initWithFormat:@"%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
                       b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11],
                       b[12], b[13], b[14], b[15]];
}
