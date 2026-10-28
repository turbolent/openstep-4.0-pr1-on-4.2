/* Appended after core.m, struct-return.m, abi.m, and unicode.m for native cc. */
#include <sys/wait.h>
#include <sys/time.h>

static unsigned failures, checks;
static void check(int passed, const char *name) {
    checks++;
    if (!passed)
        failures++;
    printf("%s %s\n", passed ? "PASS" : "FAIL", name);
}
static int tigerResolveTestPassed;
static void tigerResolveTest(TigerDNSReference *reference, unsigned flags, unsigned index,
                             int error, const char *full, const char *host, unsigned short port,
                             unsigned short length, const unsigned char *txt, void *context) {
    tigerResolveTestPassed = !error && !strcmp(full, "Test._ssh._tcp.local.") &&
                             !strcmp(host, "host.local.") && ntohs(port) == 22;
}
@interface TigerABIFixture : NSObject
- (NSRect)nativeRectangle:(float)value;
- (NSRect)stackRectangle:(float)value;
@end
@implementation TigerABIFixture
- (NSRect)nativeRectangle:(float)value {
    return NSMakeRect(value, 10, 20, 30);
}
- (NSRect)stackRectangle:(float)value {
    return NSZeroRect;
}
@end
extern void TigerTestSendRect(NSRect *, id, SEL, float);
extern void TigerTestOffset(NSRect *, NSRect, float, float);
extern void TigerTestStackRect(void);
asm(".text\n.align 2\n.globl _TigerTestSendRect\n_TigerTestSendRect:\n"
    "pushl %ebp\nmovl %esp,%ebp\npushl 20(%ebp)\npushl 16(%ebp)\npushl 12(%ebp)\npushl 8(%ebp)\n"
    "call _objc_msgSend_stret\naddl $12,%esp\nleave\nret\n"
    ".globl _TigerTestOffset\n_TigerTestOffset:\n"
    "pushl %ebp\nmovl %esp,%ebp\npushl 32(%ebp)\npushl 28(%ebp)\npushl 24(%ebp)\npushl 20(%ebp)\npushl 16(%ebp)\npushl 12(%ebp)\npushl 8(%ebp)\n"
    "call _TigerNSOffsetRect\naddl $24,%esp\nleave\nret\n"
    ".globl _TigerTestStackRect\n_TigerTestStackRect:\n"
    "movl 4(%esp),%eax\nmovl 16(%esp),%edx\nmovl %edx,(%eax)\nmovl $0x41200000,4(%eax)\nmovl $0x41a00000,8(%eax)\nmovl $0x41f00000,12(%eax)\nret $4\n");

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    TigerABIFixture *object = [[TigerABIFixture alloc] init];
    Method method;
    NSRect rect;
    TigerStat statValue;
    struct stat nativeStat;
    TigerUnicodeMapping mapping = {0x100, 0x08000100, -1};
    TigerTextConverter *converter;
    unsigned readCount, written, mappedCount, offsets[3] = {0, 1, 3}, mapped[3];
    unichar output[16];
    int status, pid, master, count, total = 0;
    union wait childStatus;
    char bytes[64];
    struct winsize windowSize = {30, 100, 600, 420};
    struct timeval before, after;
    long elapsed;
    check(sizeof(TigerFILE) == 88 && sizeof(TigerStat) == 96 && sizeof(TigerPasswd) == 44 &&
              sizeof(TigerTermios) == 44,
          "Darwin structure sizes");
    TigerInitializeCABI();
    check(Tigerstat("/bin/sh", &statValue) == 0 && stat("/bin/sh", &nativeStat) == 0 &&
              statValue.size == nativeStat.st_size && statValue.mode == nativeStat.st_mode,
          "stat translation");
    TigerTestSendRect(&rect, object, @selector(nativeRectangle:), 7);
    check(rect.origin.x == 7 && rect.origin.y == 10 && rect.size.width == 20 &&
              rect.size.height == 30,
          "Tiger to native Objective-C struct return");
    method = class_getInstanceMethod([TigerABIFixture class], @selector(stackRectangle:));
    method->method_imp = (IMP)TigerTestStackRect;
    TigerWrapStructMethod([TigerABIFixture class], @selector(stackRectangle:));
    rect = [object stackRectangle:9];
    check(rect.origin.x == 9 && rect.origin.y == 10 && rect.size.width == 20 &&
              rect.size.height == 30,
          "native to Tiger Objective-C struct return");
    TigerTestOffset(&rect, NSMakeRect(1, 2, 3, 4), 5, 7);
    check(rect.origin.x == 6 && rect.origin.y == 9 && rect.size.width == 3 && rect.size.height == 4,
          "Tiger C struct return");
    status = CreateTextToUnicodeInfo(&mapping, &converter);
    check(status == 0 && converter != NULL, "UTF-8 converter creation");
    if (!status) {
        status = ConvertFromTextToUnicode(
            converter, 7, (const unsigned char *)"A\303\251\360\237\230\200", 0, 3, offsets,
            &mappedCount, mapped, sizeof(output), &readCount, &written, output);
        check(status == 0 && readCount == 7 && written == 8 && output[0] == 'A' &&
                  output[1] == 0xe9 && output[2] == 0xd83d && output[3] == 0xde00,
              "UTF-8 BMP and supplementary conversion");
        check(mappedCount == 3 && mapped[0] == 0 && mapped[1] == 2 && mapped[2] == 4,
              "source byte to UTF-16 byte offsets");
        status = ConvertFromTextToUnicode(converter, 3, (const unsigned char *)"ABC", 0, 0, NULL,
                                          NULL, NULL, 2, &readCount, &written, output);
        check(status == -8785 && readCount == 1 && written == 2 && output[0] == 'A',
              "bounded conversion output");
        status =
            ConvertFromTextToUnicode(converter, 2, (const unsigned char *)"\342\202", 64, 0, NULL,
                                     NULL, NULL, sizeof(output), &readCount, &written, output);
        check(status == -8753 && readCount == 0 && written == 0, "partial multibyte input");
        status = ConvertFromTextToUnicode(converter, 2, (const unsigned char *)"\377X", 1, 0, NULL,
                                          NULL, NULL, sizeof(output), &readCount, &written, output);
        check(status == -8783 && readCount == 2 && written == 4 && output[0] == 0xfffd &&
                  output[1] == 'X',
              "invalid-byte fallback");
        DisposeTextToUnicodeInfo(&converter);
        check(converter == NULL, "converter disposal");
    }
    gettimeofday(&before, NULL);
    Tigerusleep(20000);
    gettimeofday(&after, NULL);
    elapsed = (after.tv_sec - before.tv_sec) * 1000000 + after.tv_usec - before.tv_usec;
    check(elapsed >= 15000 && elapsed < 1000000, "Mach timed wait");
    pid = Tigerforkpty(&master, NULL, NULL, &windowSize);
    if (pid == 0) {
        TigerTermios terminal;
        struct winsize size;
        if (Tigertcgetattr(0, &terminal) < 0 || Tigertcsetattr(0, 0, &terminal) < 0 ||
            ioctl(0, TIOCGWINSZ, &size) < 0 || size.ws_col != 100 || size.ws_row != 30)
            _exit(21);
        write(1, "PTY_OK\n", 7);
        _exit(0);
    }
    if (pid > 0) {
        alarm(5);
        while (total < sizeof(bytes) - 1 &&
               (count = read(master, bytes + total, sizeof(bytes) - 1 - total)) > 0)
            total += count;
        bytes[total] = 0;
        wait4(pid, &childStatus, 0, NULL);
        Tigerclose(master);
        alarm(0);
        check(strstr(bytes, "PTY_OK") != NULL && WIFEXITED(childStatus) &&
                  childStatus.w_retcode == 0,
              "PTY creation, termios, winsize, and clean child exit");
    } else
        check(0, "PTY creation");
    {
        char slaveName[64];
        int query[4] = {1, 14, 4, 0}, found = 0;
        unsigned length = 0, small = 1, offset;
        unsigned char guard = 0x5a, *processes;
        struct stat slaveStat;
        pid = Tigerforkpty(&master, slaveName, NULL, NULL);
        if (pid == 0) {
            write(1, "READY\n", 6);
            read(0, bytes, 1);
            _exit(0);
        }
        if (pid > 0) {
            alarm(10);
            read(master, bytes, sizeof(bytes));
            stat(slaveName, &slaveStat);
            query[3] = slaveStat.st_rdev;
            status = sysctl(query, 4, NULL, &length, NULL, 0);
            processes = malloc(length ? length : 1);
            if (!status && !sysctl(query, 4, processes, &length, NULL, 0))
                for (offset = 0; offset + 492 <= length; offset += 492)
                    if (*(int *)(processes + offset + 0x18) == pid &&
                        *(int *)(processes + offset + 0x1a0) == getpid())
                        found = 1;
            check(found, "process status contains live PTY child and parent");
            check(sysctl(query, 4, &guard, &small, NULL, 0) == -1 && errno == ENOMEM &&
                      guard == 0x5a && small == length,
                  "process status rejects undersized output without writing");
            free(processes);
            kill(pid, SIGTERM);
            wait4(pid, &childStatus, 0, NULL);
            Tigerclose(master);
            alarm(0);
            check(tigerPTYCount == 0, "closed PTYs release registry slots");
        } else
            check(0, "process-query PTY creation");
    }
    {
        unsigned char packet[] = {0,   0,   0x84, 0,   0,   0,   0,   1,   0,    0,   0, 0,
                                  4,   '_', 's',  's', 'h', 4,   '_', 't', 'c',  'p', 5, 'l',
                                  'o', 'c', 'a',  'l', 0,   0,   12,  0,   1,    0,   0, 0,
                                  120, 0,   7,    4,   'T', 'e', 's', 't', 0xc0, 12};
        NSArray *records = tigerDNSRecords(packet, sizeof(packet));
        NSDictionary *record = [records count] ? [records objectAtIndex:0] : nil;
        unsigned char cycle[] = {0xc0, 0};
        unsigned offset = 0;
        check([records count] == 1 &&
                  [[record objectForKey:@"target"] isEqual:@"Test._ssh._tcp.local."] &&
                  [[record objectForKey:@"ttl"] intValue] == 120,
              "DNS compressed PTR and TTL parsing");
        check(tigerDNSName(cycle, sizeof(cycle), &offset) == nil &&
                  [tigerDNSRecords(packet, sizeof(packet) - 1) count] == 0,
              "DNS pointer cycles and truncated record rejection");
    }
    {
        NSAppleEventDescriptor *list = [NSAppleEventDescriptor listDescriptor],
                               *record = [NSAppleEventDescriptor recordDescriptor];
        NSAppleEventDescriptor *value = [NSAppleEventDescriptor
            descriptorWithDescriptorType:0x54455854
                                    data:[NSData dataWithBytes:"abc" length:3]];
        [list insertDescriptor:value atIndex:0];
        [record setDescriptor:value forKeyword:0x706e616d];
        check([list numberOfItems] == 1 && [list descriptorAtIndex:1] == value &&
                  [record descriptorForKeyword:0x706e616d] == value && [[value data] length] == 3,
              "Apple-event descriptor list, record, and data values");
        check(((Class)[NSScriptCommand class])->instance_size == 40,
              "Tiger script-command base layout");
    }
    {
        unsigned char packet[] = {0,   0,   0x84, 0,   0,   0,   0,   1,   0,   0,  0,   0,   4,
                                  'T', 'e', 's',  't', 4,   '_', 's', 's', 'h', 4,  '_', 't', 'c',
                                  'p', 5,   'l',  'o', 'c', 'a', 'l', 0,   0,   33, 0,   1,   0,
                                  0,   0,   120,  0,   18,  0,   0,   0,   0,   0,  22,  4,   'h',
                                  'o', 's', 't',  5,   'l', 'o', 'c', 'a', 'l', 0};
        struct sockaddr_in address;
        int length = sizeof(address), sender = socket(AF_INET, SOCK_DGRAM, 0);
        TigerDNSReference reference;
        reference.fd = tigerDNSSocket();
        reference.fullName = @"Test._ssh._tcp.local.";
        reference.reply = tigerResolveTest;
        reference.context = NULL;
        if (sender >= 0 && reference.fd >= 0 &&
            getsockname(reference.fd, (struct sockaddr *)&address, &length) == 0) {
            address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
            sendto(sender, packet, sizeof(packet), 0, (struct sockaddr *)&address, sizeof(address));
            Tigerusleep(20000);
            DNSServiceProcessResult(&reference);
        }
        check(tigerResolveTestPassed,
              "DNS-SD SRV resolution through native UDP socket and callback");
        if (sender >= 0)
            close(sender);
        if (reference.fd >= 0)
            close(reference.fd);
    }
    [object release];
    [pool release];
    printf("%u checks, %u failures\n", checks, failures);
    return failures ? 1 : 0;
}
