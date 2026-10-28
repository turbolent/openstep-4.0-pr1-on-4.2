#define DR2_FRAMEWORK_RUNTIME
#include "../dr2-abi.m"

#include <sys/param.h>
char *getcwd(char *buffer, unsigned size) {
    char native[MAXPATHLEN];
    unsigned length;
    if (!getwd(native))
        return NULL;
    length = strlen(native) + 1;
    if (!buffer) {
        if (!size)
            size = length;
        if (size < length) {
            errno = ERANGE;
            return NULL;
        }
        buffer = malloc(size);
        if (!buffer)
            return NULL;
    }
    if (length > size) {
        errno = ERANGE;
        return NULL;
    }
    memcpy(buffer, native, length);
    return buffer;
}

#include <streams/streams.h>
int vsnprintf(char *destination, unsigned capacity, const char *format, va_list arguments) {
    NXStream *stream = NXOpenMemory(NULL, 0, NX_READWRITE);
    char *text;
    int length, allocated;
    unsigned count;
    if (!stream) {
        errno = ENOMEM;
        return -1;
    }
    NXVPrintf(stream, format, arguments);
    NXGetMemoryBuffer(stream, &text, &length, &allocated);
    if (capacity) {
        count = length < capacity ? length : capacity - 1;
        memcpy(destination, text, count);
        destination[count] = 0;
    }
    NXCloseMemory(stream, NX_FREEBUFFER);
    return length;
}

int DR2fseek(DR2File *file, long offset, int whence) {
    int result = fseek(nativeFile(file), offset, whence);
    updateFile(file);
    return result;
}
long DR2ftell(DR2File *file) {
    return ftell(nativeFile(file));
}
int DR2setvbuf(DR2File *file, char *buffer, int mode, unsigned size) {
    int result = setvbuf(nativeFile(file), buffer, mode, size);
    updateFile(file);
    return result;
}
