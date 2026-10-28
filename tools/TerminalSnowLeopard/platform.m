/* Services for which OPENSTEP has no corresponding system framework. */
/* NSLocale currently exposes en_US. Keep ICU's English quotation delimiters. */
void *ulocdata_open(const char *locale, int *status) {
    static const unsigned short delimiters[] = {0x201c, 0x201d, 0x2018, 0x2019};
    if (!status || *status > 0)
        return NULL;
    if (locale && *locale && strncmp(locale, "en", 2) && strcmp(locale, "root")) {
        *status = 2;
        return NULL;
    }
    return (void *)delimiters;
}
void ulocdata_close(void *locale) {}
int ulocdata_getDelimiter(const unsigned short *locale, unsigned kind, unsigned short *out,
                          int capacity, int *status) {
    if (!status || *status > 0)
        return 0;
    if (!locale || kind >= 4 || capacity < 0 || (!out && capacity)) {
        *status = 1;
        return 0;
    }
    if (capacity)
        out[0] = locale[kind];
    if (capacity > 1)
        out[1] = 0;
    else
        *status = capacity ? -124 : 15;
    return 1;
}

/* Native NSEvent has already passed through the OPENSTEP input manager.
 * Carbon raw-key translation cannot be used to bypass that manager. */
@implementation NSEvent (SnowCarbonEvent)
- (void *)eventRef {
    return NULL;
}
@end
int CreateEvent(void *allocator, unsigned eventClass, unsigned kind, double when, unsigned flags,
                void **out) {
    if (out)
        *out = NULL;
    return -9874; /* eventNotHandledErr */
}
double GetEventTime(void *event) {
    return 0;
}
int GetEventParameter(void *event, unsigned name, unsigned type, unsigned *actual,
                      unsigned capacity, unsigned *size, void *out) {
    if (size)
        *size = 0;
    if (actual)
        *actual = 0;
    return -9870; /* eventParameterNotFoundErr */
}
int SetEventParameter(void *event, unsigned name, unsigned type, unsigned size, const void *value) {
    return -9874;
}
unsigned TSMGetDeadKeyState(void) {
    return 0;
}
void TSMSetDeadKeyState(unsigned state) {}
int TSMProcessRawKeyCode(void *event) {
    return -9874;
}

/* Dictionary Services has no OPENSTEP dictionary database. CFRange uses
 * Darwin's EAX:EDX convention and kCFNotFound is -1, not NSNotFound. */
unsigned long long DCSGetTermRangeInString(void *dictionary, NSString *text, int index) {
    return 0xffffffffU;
}
int HIDictionaryWindowShow(void *dictionary, NSString *text, NSRange range, void *origin,
                           void *options) {
    NSRunAlertPanel(@"Dictionary", @"Dictionary lookup is unavailable on OPENSTEP.", @"OK", nil,
                    nil);
    return -4; /* unimpErr */
}

/* Read stack frames through Mach instead of dereferencing damaged frames. */
int backtrace(void **addresses, int capacity) {
    unsigned frame = 0, previous = 0;
    int count = 0;
    if (!addresses || capacity <= 0)
        return 0;
    asm("movl %%ebp,%0" : "=r"(frame));
    while (frame && count < capacity) {
        vm_address_t page = frame & ~(vm_page_size - 1), copy = 0;
        unsigned size = 0, words[2];
        if ((frame & 3) || frame <= previous || frame - page > vm_page_size - 8)
            break;
        if (vm_read(task_self(), page, vm_page_size, &copy, &size) != KERN_SUCCESS)
            break;
        memcpy(words, (const void *)(copy + frame - page), sizeof(words));
        vm_deallocate(task_self(), copy, size);
        if (!words[1])
            break;
        addresses[count++] = (void *)words[1];
        previous = frame;
        frame = words[0];
        if (frame - previous > 1024 * 1024)
            break;
    }
    return count;
}
char **backtrace_symbols(void *const *addresses, int count) {
    char **result, *strings;
    int i;
    if (count < 0 || count > INT_MAX / (sizeof(char *) + 32))
        return NULL;
    result = malloc(count * (sizeof(char *) + 32));
    if (!result)
        return NULL;
    strings = (char *)(result + count);
    for (i = 0; i < count; i++) {
        result[i] = strings + i * 32;
        sprintf(result[i], "0x%08x", (unsigned)addresses[i]);
    }
    return result;
}
/* OPENSTEP always follows normal application termination and cleanup. It
 * has no sudden-termination service to enable or disable. */
@implementation NSProcessInfo (SnowNormalTermination)
- (void)disableSuddenTermination {
}
- (void)enableSuddenTermination {
}
@end
