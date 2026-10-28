/* C runtime layouts and entry points used by DR2 Intel binaries. */
#ifdef DR2_FRAMEWORK_RUNTIME
#import <Foundation/Foundation.h>
#else
#import <AppKit/AppKit.h>
#endif
#include <ctype.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/dir.h>
#include <sys/vfs.h>
#include "dr2-abi.h"

/* Both Intel handler structures reserve a jump buffer and four words.
 * DR2 accesses those words only through these three entry points. */
#ifndef DR2_FRAMEWORK_RUNTIME
void _NSAddHandler2(NSHandler *handler) {
    _NSAddHandler(handler);
}
void _NSRemoveHandler2(NSHandler *handler) {
    _NSRemoveHandler(handler);
}
id _NSExceptionObjectFromHandler2(NSHandler *handler) {
    return _NSExceptionObjectFromHandler(handler);
}
#endif

enum {
    DR2RuneCount = 256,
    DR2FileSize = 88,
    DR2FileEOF = 0x20,
    DR2FileError = 0x40
};
enum {
    DR2RuneAlpha = 0x100,
    DR2RuneControl = 0x200,
    DR2RuneDigit = 0x400,
    DR2RuneGraph = 0x800,
    DR2RuneLower = 0x1000,
    DR2RunePunctuation = 0x2000,
    DR2RuneSpace = 0x4000,
    DR2RuneUpper = 0x8000,
    DR2RuneHexDigit = 0x10000,
    DR2RuneBlank = 0x20000,
    DR2RunePrint = 0x40000
};
struct RuneLocale {
    char magic[8], encoding[32];
    void *get, *put;
    int invalid;
    unsigned long type[DR2RuneCount];
    int lower[DR2RuneCount], upper[DR2RuneCount];
    char unused[32];
};
struct RuneLocale _DefaultRuneLocale;
struct RuneLocale *_CurrentRuneLocale = &_DefaultRuneLocale;
unsigned long ___runetype(int c) {
    return (unsigned)c < DR2RuneCount ? _DefaultRuneLocale.type[c] : 0;
}
int ___tolower(int c) {
    return (unsigned)c < DR2RuneCount ? _DefaultRuneLocale.lower[c] : c;
}

typedef struct DR2File {
    unsigned char *position;
    int readCount, writeCount;
    unsigned short flags;
    short descriptor;
    char reserved[DR2FileSize - 16];
} DR2File;
typedef struct WrappedFile {
    DR2File dr;
    FILE *native;
} WrappedFile;
DR2File __sF[3];

static FILE *nativeFile(DR2File *file) {
    if (file == &__sF[0])
        return stdin;
    if (file == &__sF[1])
        return stdout;
    if (file == &__sF[2])
        return stderr;
    return ((WrappedFile *)file)->native;
}
static void updateFile(DR2File *file) {
    FILE *native = nativeFile(file);
    file->readCount = file->writeCount = 0;
    file->descriptor = fileno(native);
    file->flags = (feof(native) ? DR2FileEOF : 0) | (ferror(native) ? DR2FileError : 0);
}
static DR2File *wrapFile(FILE *file) {
    WrappedFile *result;
    if (!file)
        return NULL;
    result = calloc(1, sizeof(*result));
    if (!result) {
        fclose(file);
        return NULL;
    }
    result->native = file;
    updateFile(&result->dr);
    return &result->dr;
}
DR2File *DR2fopen(const char *path, const char *mode) {
    return wrapFile(fopen(path, mode));
}
DR2File *DR2fdopen(int fd, const char *mode) {
    return wrapFile(fdopen(fd, mode));
}
int DR2fclose(DR2File *file) {
    int result = fclose(nativeFile(file));
    if (file != &__sF[0] && file != &__sF[1] && file != &__sF[2])
        free(file);
    return result;
}
int __srget(DR2File *file) {
    int value = fgetc(nativeFile(file));
    updateFile(file);
    return value;
}
size_t DR2fread(void *data, size_t size, size_t count, DR2File *file) {
    size_t result = fread(data, size, count, nativeFile(file));
    updateFile(file);
    return result;
}
size_t DR2fwrite(const void *data, size_t size, size_t count, DR2File *file) {
    size_t result = fwrite(data, size, count, nativeFile(file));
    updateFile(file);
    return result;
}
int DR2fprintf(DR2File *file, const char *format, ...) {
    int result;
    va_list args;
    va_start(args, format);
    result = vfprintf(nativeFile(file), format, args);
    va_end(args);
    updateFile(file);
    return result;
}
int DR2fputc(int value, DR2File *file) {
    int result = fputc(value, nativeFile(file));
    updateFile(file);
    return result;
}
int DR2fputs(const char *value, DR2File *file) {
    int result = fputs(value, nativeFile(file));
    updateFile(file);
    return result;
}
void DR2setbuf(DR2File *file, char *buffer) {
    setbuf(nativeFile(file), buffer);
    updateFile(file);
}

static void convertStat(struct DR2Stat *out, struct stat *in) {
    memset(out, 0, sizeof(*out));
    out->dev = in->st_dev;
    out->ino = in->st_ino;
    out->mode = in->st_mode;
    out->links = in->st_nlink;
    out->uid = in->st_uid;
    out->gid = in->st_gid;
    out->rdev = in->st_rdev;
    out->accessTime = in->st_atime;
    out->modifyTime = in->st_mtime;
    out->changeTime = in->st_ctime;
    out->size = in->st_size;
    out->blocks = in->st_blocks;
    out->blocksize = in->st_blksize;
}
int DR2stat(const char *path, struct DR2Stat *out) {
    struct stat native;
    int result = stat(path, &native);
    if (!result)
        convertStat(out, &native);
    return result;
}
int DR2fstat(int fd, struct DR2Stat *out) {
    struct stat native;
    int result = fstat(fd, &native);
    if (!result)
        convertStat(out, &native);
    return result;
}
int DR2connect(int fd, const struct sockaddr *address, int size) {
    struct sockaddr native;
    if (size != sizeof(native)) {
        errno = EINVAL;
        return -1;
    }
    memcpy(&native, address, sizeof(native));
    native.sa_family = ((const unsigned char *)address)[1];
    return connect(fd, &native, size);
}

void DR2InitializeCABI(void) {
    int c;
    for (c = 0; c < DR2RuneCount; c++) {
        unsigned long flags = 0;
        if (isalpha(c))
            flags |= DR2RuneAlpha;
        if (iscntrl(c))
            flags |= DR2RuneControl;
        if (isdigit(c))
            flags |= DR2RuneDigit;
        if (isgraph(c))
            flags |= DR2RuneGraph;
        if (islower(c))
            flags |= DR2RuneLower;
        if (ispunct(c))
            flags |= DR2RunePunctuation;
        if (isspace(c))
            flags |= DR2RuneSpace;
        if (isupper(c))
            flags |= DR2RuneUpper;
        if (isxdigit(c))
            flags |= DR2RuneHexDigit;
        if (c == ' ' || c == '\t')
            flags |= DR2RuneBlank;
        if (isprint(c))
            flags |= DR2RunePrint;
        _DefaultRuneLocale.type[c] = flags;
        _DefaultRuneLocale.lower[c] = tolower(c);
        _DefaultRuneLocale.upper[c] = toupper(c);
    }
    for (c = 0; c < 3; c++)
        updateFile(&__sF[c]);
}

int DR2fflush(DR2File *file) {
    int result = fflush(file ? nativeFile(file) : NULL);
    if (file)
        updateFile(file);
    return result;
}
char *DR2fgets(char *buffer, int size, DR2File *file) {
    char *result = fgets(buffer, size, nativeFile(file));
    updateFile(file);
    return result;
}
int DR2lstat(const char *path, struct DR2Stat *out) {
    struct stat native;
    int result = lstat(path, &native);
    if (!result)
        convertStat(out, &native);
    return result;
}
struct DR2Dirent {
    unsigned long inode;
    unsigned short reclen;
    unsigned char type, length;
    char name[MAXNAMLEN + 1];
};
struct DR2Dirent *DR2readdir(DIR *dir) {
    static struct DR2Dirent result;
    struct direct *entry = readdir(dir);
    if (!entry)
        return NULL;
    result.inode = entry->d_fileno;
    result.reclen = sizeof(result);
    result.type = 0;
    result.length = entry->d_namlen;
    strcpy(result.name, entry->d_name);
    return &result;
}
struct DR2StatFS {
    short type, flags;
    long bsize, iosize, blocks, bfree, bavail, files, ffree;
    fsid_t fsid;
    unsigned owner;
    long spare[4];
    char typename[15], mounted[90], source[90];
};
int DR2statfs(const char *path, struct DR2StatFS *out) {
    struct statfs native;
    int result = statfs(path, &native);
    if (result)
        return result;
    memset(out, 0, sizeof(*out));
    out->type = native.f_type;
    out->bsize = out->iosize = native.f_bsize;
    out->blocks = native.f_blocks;
    out->bfree = native.f_bfree;
    out->bavail = native.f_bavail;
    out->files = native.f_files;
    out->ffree = native.f_ffree;
    out->fsid = native.f_fsid;
    return 0;
}
long long strtoq(const char *text, char **end, int base) {
    const char *p = text;
    unsigned long long value = 0, limit = 0x7fffffffffffffffULL;
    int negative = 0, digit, any = 0, overflow = 0;
    while (isspace((unsigned char)*p))
        p++;
    if (*p == '-' || *p == '+')
        negative = *p++ == '-';
    if (base && (base < 2 || base > 36)) {
        errno = EINVAL;
        if (end)
            *end = (char *)text;
        return 0;
    }
    if ((base == 0 || base == 16) && p[0] == '0' && (p[1] == 'x' || p[1] == 'X') &&
        isxdigit((unsigned char)p[2])) {
        base = 16;
        p += 2;
    }
    if (!base)
        base = *p == '0' ? 8 : 10;
    if (negative)
        limit++;
    for (;; p++) {
        unsigned char c = *p;
        digit = c >= '0' && c <= '9'   ? c - '0'
                : c >= 'a' && c <= 'z' ? c - 'a' + 10
                : c >= 'A' && c <= 'Z' ? c - 'A' + 10
                                       : 36;
        if (digit >= base)
            break;
        any = 1;
        if (value > (limit - digit) / base)
            overflow = 1;
        else
            value = value * base + digit;
    }
    if (end)
        *end = (char *)(any ? p : text);
    if (overflow) {
        errno = ERANGE;
        value = limit;
    }
    return negative ? (long long)(0ULL - value) : (long long)value;
}

@interface DR2CRuntime : NSObject
@end
@implementation DR2CRuntime
+ (void)load {
    DR2InitializeCABI();
}
@end
