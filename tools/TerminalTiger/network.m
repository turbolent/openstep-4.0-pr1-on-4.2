/* The DNS-SD subset used by Terminal, over native BSD UDP sockets.
 * Queries use an ephemeral source port (legacy unicast mDNS responses).
 * This avoids requiring a privileged system-wide Bonjour daemon. */
#import <Foundation/Foundation.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

static unsigned tigerDNS16(const unsigned char *p) {
    return (p[0] << 8) | p[1];
}
static unsigned tigerDNS32(const unsigned char *p) {
    return ((unsigned)p[0] << 24) | ((unsigned)p[1] << 16) | (p[2] << 8) | p[3];
}
static NSString *tigerDNSName(const unsigned char *packet, unsigned length, unsigned *position) {
    unsigned p = *position, end = 0, hops = 0, total = 0, n;
    NSMutableString *name = [NSMutableString string];
    while (p < length && hops++ < 128) {
        n = packet[p++];
        if (!n) {
            *position = end ? end : p;
            return name;
        }
        if ((n & 192) == 192) {
            if (p >= length)
                return nil;
            if (!end)
                end = p + 1;
            p = ((n & 63) << 8) | packet[p];
            continue;
        }
        if (n > 63 || p + n > length || (total += n + 1) > 255)
            return nil;
        {
            NSString *label = [[[NSString alloc] initWithData:[NSData dataWithBytes:packet + p
                                                                             length:n]
                                                     encoding:NSUTF8StringEncoding] autorelease];
            if (!label)
                return nil;
            [name appendString:label];
            [name appendString:@"."];
        }
        p += n;
    }
    return nil;
}
static NSArray *tigerDNSRecords(const unsigned char *packet, unsigned length) {
    unsigned p = 12, i, count, questions;
    NSMutableArray *records = [NSMutableArray array];
    if (length < 12 || !(packet[2] & 128) || (packet[3] & 15))
        return records;
    questions = tigerDNS16(packet + 4);
    count = tigerDNS16(packet + 6) + tigerDNS16(packet + 8) + tigerDNS16(packet + 10);
    for (i = 0; i < questions; i++) {
        if (!tigerDNSName(packet, length, &p) || p + 4 > length)
            return records;
        p += 4;
    }
    for (i = 0; i < count; i++) {
        NSString *owner = tigerDNSName(packet, length, &p), *target = nil;
        unsigned type, bytes, ttl, start, port = 0;
        NSMutableDictionary *record;
        if (!owner || p + 10 > length)
            break;
        type = tigerDNS16(packet + p);
        ttl = tigerDNS32(packet + p + 4);
        bytes = tigerDNS16(packet + p + 8);
        p += 10;
        if (p + bytes > length)
            break;
        start = p;
        if ((tigerDNS16(packet + p - 8) & 32767) != 1) {
            p += bytes;
            continue;
        }
        if (type == 12)
            target = tigerDNSName(packet, length, &p);
        if (type == 33 && bytes >= 7) {
            port = tigerDNS16(packet + p + 4);
            p += 6;
            target = tigerDNSName(packet, length, &p);
        }
        record = [NSMutableDictionary
            dictionaryWithObjectsAndKeys:owner, @"owner", [NSNumber numberWithInt:type], @"type",
                                         [NSNumber numberWithUnsignedInt:ttl], @"ttl",
                                         [NSNumber numberWithInt:port], @"port",
                                         [NSData dataWithBytes:packet + start length:bytes],
                                         @"data", nil];
        if (target && p <= start + bytes)
            [record setObject:target forKey:@"target"];
        [records addObject:record];
        p = start + bytes;
    }
    return records;
}
static int tigerDNSLabel(unsigned char *packet, unsigned *position, NSString *label) {
    NSData *data = [label dataUsingEncoding:NSUTF8StringEncoding];
    unsigned n = [data length];
    if (!n || n > 63 || *position + n + 1 > 1000)
        return -1;
    packet[(*position)++] = n;
    memcpy(packet + *position, [data bytes], n);
    *position += n;
    return 0;
}
static int tigerDNSQuery(int fd, NSString *instance, NSString *type, NSString *domain,
                         unsigned recordType) {
    unsigned char packet[1024];
    unsigned p = 12, i;
    NSArray *labels;
    struct sockaddr_in address;
    memset(packet, 0, sizeof(packet));
    packet[5] = 1;
    if (instance && tigerDNSLabel(packet, &p, instance))
        return -1;
    labels = [[type stringByAppendingString:domain] componentsSeparatedByString:@"."];
    for (i = 0; i < [labels count]; i++)
        if ([[labels objectAtIndex:i] length] &&
            tigerDNSLabel(packet, &p, [labels objectAtIndex:i]))
            return -1;
    packet[p++] = 0;
    packet[p++] = recordType >> 8;
    packet[p++] = recordType;
    packet[p++] = 0;
    packet[p++] = 1;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(5353);
    address.sin_addr.s_addr = inet_addr("224.0.0.251");
    return sendto(fd, packet, p, 0, (struct sockaddr *)&address, sizeof(address)) == (int)p ? 0
                                                                                            : -1;
}
static int tigerDNSSocket(void) {
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in address;
    unsigned char ttl = 255;
    if (fd < 0)
        return -1;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) < 0 ||
        fcntl(fd, F_SETFL, FNDELAY) < 0) {
        close(fd);
        return -1;
    }
    setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, (char *)&ttl, sizeof(ttl));
    return fd;
}
static NSString *tigerDNSDomain(NSString *domain) {
    if (![domain length])
        return @"local.";
    return [domain hasSuffix:@"."] ? domain : [domain stringByAppendingString:@"."];
}
static NSString *tigerDNSType(NSString *type) {
    return [type hasSuffix:@"."] ? type : [type stringByAppendingString:@"."];
}

@interface NSNetService : NSObject {
    NSString *tigerDomain, *tigerType, *tigerName;
    int tigerPort;
}
- initWithDomain:(NSString *)domain type:(NSString *)type name:(NSString *)name;
- (NSString *)domain;
- (NSString *)type;
- (NSString *)name;
@end
@implementation NSNetService
- initWithDomain:(NSString *)domain type:(NSString *)type name:(NSString *)name {
    self = [super init];
    tigerDomain = [tigerDNSDomain(domain) copy];
    tigerType = [tigerDNSType(type) copy];
    tigerName = [name copy];
    tigerPort = -1;
    return self;
}
- initWithDomain:(NSString *)domain type:(NSString *)type name:(NSString *)name port:(int)port {
    [self initWithDomain:domain type:type name:name];
    tigerPort = port;
    return self;
}
- (NSString *)domain {
    return tigerDomain;
}
- (NSString *)type {
    return tigerType;
}
- (NSString *)name {
    return tigerName;
}
- (int)port {
    return tigerPort;
}
- (void)stop {
}
- (BOOL)isEqual:(id)object {
    NSNetService *service = object;
    return [object isKindOfClass:[NSNetService class]] &&
           [tigerDomain caseInsensitiveCompare:[service domain]] == NSOrderedSame &&
           [tigerType caseInsensitiveCompare:[service type]] == NSOrderedSame &&
           [tigerName isEqual:[service name]];
}
- (unsigned)hash {
    return [tigerName hash];
}
- (void)dealloc {
    [tigerDomain release];
    [tigerType release];
    [tigerName release];
    [super dealloc];
}
@end

@interface NSNetServiceBrowser : NSObject {
    id tigerDelegate;
    NSTimer *tigerBrowseTimer;
    NSString *tigerBrowseType, *tigerBrowseDomain;
    NSMutableDictionary *tigerBrowseCache;
    int tigerBrowseFD, tigerBrowseTicks;
}
- (void)stop;
- (void)tigerPoll:(id)timer;
@end
@implementation NSNetServiceBrowser
- init {
    self = [super init];
    tigerBrowseFD = -1;
    tigerBrowseCache = [[NSMutableDictionary alloc] init];
    return self;
}
- (void)setDelegate:(id)delegate {
    tigerDelegate = delegate;
}
- (id)delegate {
    return tigerDelegate;
}
- (void)searchForServicesOfType:(NSString *)type inDomain:(NSString *)domain {
    SEL will = sel_getUid("netServiceBrowserWillSearch:");
    [self stop];
    [tigerBrowseCache removeAllObjects];
    [tigerBrowseType release];
    [tigerBrowseDomain release];
    tigerBrowseType = [tigerDNSType(type) copy];
    tigerBrowseDomain = [tigerDNSDomain(domain) copy];
    tigerBrowseTicks = 0;
    if ([tigerDelegate respondsToSelector:will])
        [tigerDelegate performSelector:will withObject:self];
    tigerBrowseFD = tigerDNSSocket();
    if (tigerBrowseFD < 0 ||
        tigerDNSQuery(tigerBrowseFD, nil, tigerBrowseType, tigerBrowseDomain, 12)) {
        SEL failed = sel_getUid("netServiceBrowser:didNotSearch:");
        NSDictionary *error = [NSDictionary
            dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:-72000], @"NSNetServicesErrorCode",
                                         [NSNumber numberWithInt:10], @"NSNetServicesErrorDomain",
                                         nil];
        if ([tigerDelegate respondsToSelector:failed])
            [tigerDelegate performSelector:failed withObject:self withObject:error];
        [self stop];
        return;
    }
    tigerBrowseTimer = [[NSTimer scheduledTimerWithTimeInterval:0.1
                                                         target:self
                                                       selector:@selector(tigerPoll:)
                                                       userInfo:nil
                                                        repeats:YES] retain];
}
- (void)scheduleInRunLoop:(NSRunLoop *)loop forMode:(NSString *)mode {
    if (tigerBrowseTimer)
        [loop addTimer:tigerBrowseTimer forMode:mode];
}
- (void)tigerNotify:(NSNetService *)service found:(BOOL)found {
    SEL action = sel_getUid(found ? "netServiceBrowser:didFindService:moreComing:"
                                  : "netServiceBrowser:didRemoveService:moreComing:");
    if ([tigerDelegate respondsToSelector:action])
        ((void (*)(id, SEL, id, id, BOOL))[tigerDelegate methodForSelector:action])(
            tigerDelegate, action, self, service, NO);
}
- (void)tigerPoll:(id)timer {
    unsigned char packet[9000];
    int n, budget = 32;
    NSArray *keys;
    unsigned i;
    NSString *suffix = [tigerBrowseType stringByAppendingString:tigerBrowseDomain];
    while (budget-- && (n = recv(tigerBrowseFD, packet, sizeof(packet), 0)) > 0) {
        NSArray *records = tigerDNSRecords(packet, n);
        for (i = 0; i < [records count]; i++) {
            NSDictionary *record = [records objectAtIndex:i];
            NSString *target = [record objectForKey:@"target"];
            id entry;
            if ([[record objectForKey:@"type"] intValue] != 12 ||
                [[record objectForKey:@"owner"] caseInsensitiveCompare:suffix] != NSOrderedSame ||
                !target || ![target hasSuffix:suffix] || [target length] < [suffix length] + 2)
                continue;
            entry = [tigerBrowseCache objectForKey:target];
            if ([[record objectForKey:@"ttl"] unsignedIntValue]) {
                NSNetService *service =
                    entry ? [entry objectAtIndex:0]
                          : [[[NSNetService alloc]
                                initWithDomain:tigerBrowseDomain
                                          type:tigerBrowseType
                                          name:[target substringToIndex:[target length] -
                                                                        [suffix length] - 1]]
                                autorelease];
                [tigerBrowseCache
                    setObject:[NSArray arrayWithObjects:service,
                                                        [NSDate dateWithTimeIntervalSinceNow:
                                                                    [[record objectForKey:@"ttl"]
                                                                        unsignedIntValue]],
                                                        nil]
                       forKey:target];
                if (!entry)
                    [self tigerNotify:service found:YES];
            } else if (entry) {
                [self tigerNotify:[entry objectAtIndex:0] found:NO];
                [tigerBrowseCache removeObjectForKey:target];
            }
        }
    }
    keys = [tigerBrowseCache allKeys];
    for (i = 0; i < [keys count]; i++) {
        id key = [keys objectAtIndex:i], entry = [tigerBrowseCache objectForKey:key];
        if ([[entry objectAtIndex:1] timeIntervalSinceNow] < 0) {
            [self tigerNotify:[entry objectAtIndex:0] found:NO];
            [tigerBrowseCache removeObjectForKey:key];
        }
    }
    if (++tigerBrowseTicks % 100 == 0)
        tigerDNSQuery(tigerBrowseFD, nil, tigerBrowseType, tigerBrowseDomain, 12);
}
- (void)stop {
    [tigerBrowseTimer invalidate];
    [tigerBrowseTimer release];
    tigerBrowseTimer = nil;
    if (tigerBrowseFD >= 0)
        close(tigerBrowseFD);
    tigerBrowseFD = -1;
}
- (void)dealloc {
    [self stop];
    [tigerBrowseType release];
    [tigerBrowseDomain release];
    [tigerBrowseCache release];
    [super dealloc];
}
@end

typedef struct TigerDNSReference TigerDNSReference;
typedef void (*TigerDNSReply)(TigerDNSReference *, unsigned, unsigned, int, const char *,
                              const char *, unsigned short, unsigned short, const unsigned char *,
                              void *);
struct TigerDNSReference {
    int fd;
    NSString *fullName;
    TigerDNSReply reply;
    void *context;
};
int DNSServiceResolve(TigerDNSReference **result, unsigned flags, unsigned interfaceIndex,
                      const char *name, const char *type, const char *domain, TigerDNSReply reply,
                      void *context) {
    TigerDNSReference *reference;
    NSString *n, *t, *d;
    if (!result || !name || !type || !domain || !reply)
        return -65540;
    *result = 0;
    if (flags || interfaceIndex)
        return -65544;
    n = [[[NSString alloc] initWithData:[NSData dataWithBytes:name length:strlen(name)]
                               encoding:NSUTF8StringEncoding] autorelease];
    t = tigerDNSType([[[NSString alloc] initWithData:[NSData dataWithBytes:type length:strlen(type)]
                                            encoding:NSUTF8StringEncoding] autorelease]);
    d = tigerDNSDomain([[[NSString alloc] initWithData:[NSData dataWithBytes:domain
                                                                      length:strlen(domain)]
                                              encoding:NSUTF8StringEncoding] autorelease]);
    if (!n || !t || !d)
        return -65540;
    reference = calloc(1, sizeof(*reference));
    if (!reference)
        return -65539;
    reference->fd = tigerDNSSocket();
    if (reference->fd < 0 || tigerDNSQuery(reference->fd, n, t, d, 33)) {
        if (reference->fd >= 0)
            close(reference->fd);
        free(reference);
        return -65537;
    }
    reference->fullName = [[NSString stringWithFormat:@"%@.%@%@", n, t, d] copy];
    reference->reply = reply;
    reference->context = context;
    *result = reference;
    return 0;
}
int DNSServiceRefSockFD(TigerDNSReference *reference) {
    return reference ? reference->fd : -1;
}
void DNSServiceRefDeallocate(TigerDNSReference *reference) {
    if (reference) {
        close(reference->fd);
        [reference->fullName release];
        free(reference);
    }
}
int DNSServiceProcessResult(TigerDNSReference *reference) {
    unsigned char packet[9000];
    int n;
    NSArray *records;
    unsigned i, j;
    if (!reference)
        return -65541;
    n = recv(reference->fd, packet, sizeof(packet), 0);
    if (n < 0)
        return errno == EWOULDBLOCK ? 0 : -65537;
    records = tigerDNSRecords(packet, n);
    for (i = 0; i < [records count]; i++) {
        NSDictionary *record = [records objectAtIndex:i];
        NSString *host = [record objectForKey:@"target"];
        NSData *txt = nil;
        if ([[record objectForKey:@"type"] intValue] != 33 || !host ||
            [[record objectForKey:@"owner"] caseInsensitiveCompare:reference->fullName] !=
                NSOrderedSame)
            continue;
        for (j = 0; j < [records count]; j++) {
            NSDictionary *other = [records objectAtIndex:j];
            if ([[other objectForKey:@"type"] intValue] == 16 &&
                [[other objectForKey:@"owner"] caseInsensitiveCompare:reference->fullName] ==
                    NSOrderedSame)
                txt = [other objectForKey:@"data"];
        }
        {
            NSData *full = [reference->fullName dataUsingEncoding:NSUTF8StringEncoding],
                   *target = [host dataUsingEncoding:NSUTF8StringEncoding];
            char f[1024], h[1024];
            if ([full length] >= sizeof(f) || [target length] >= sizeof(h))
                return -65540;
            memcpy(f, [full bytes], [full length]);
            f[[full length]] = 0;
            memcpy(h, [target bytes], [target length]);
            h[[target length]] = 0;
            reference->reply(reference, 0, 0, 0, f, h,
                             htons([[record objectForKey:@"port"] intValue]), [txt length],
                             [txt bytes], reference -> context);
        }
        return 0; /* The callback may deallocate reference. */
    }
    return 0;
}
