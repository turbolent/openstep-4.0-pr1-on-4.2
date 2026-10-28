/* Snow Leopard libc structures and calls translated at the native boundary. */
TigerFILE *__stderrp = &__sF[2];
unsigned __stack_chk_guard = 0x53a796c1;
void __stack_chk_fail(void) {
    fprintf(stderr, "Snow Leopard Terminal: stack corruption\n");
    abort();
}
void __assert_rtn(const char *function, const char *file, int line, const char *expression) {
    fprintf(stderr, "%s:%d: %s: assertion failed: %s\n", file, line, function, expression);
    abort();
}
void SnowUnexpectedLazyBinding(void) {
    fprintf(stderr, "Unexpected Snow Leopard lazy binding\n");
    abort();
}
char *Snowfgets(char *buffer, int size, TigerFILE *file) {
    return fgets(buffer, size, tigerNativeFile(file));
}
unsigned Snowfwrite(const void *bytes, unsigned size, unsigned count, TigerFILE *file) {
    return fwrite(bytes, size, count, tigerNativeFile(file));
}
float ceilf(float value) {
    return ceil(value);
}
float floorf(float value) {
    return floor(value);
}
double round(double value) {
    return value < 0 ? ceil(value - 0.5) : floor(value + 0.5);
}
float roundf(float value) {
    return round(value);
}
long lrintf(float value) {
    return (long)rint(value);
}
unsigned strlcpy(char *destination, const char *source, unsigned size) {
    unsigned length = strlen(source);
    if (size) {
        unsigned count = length < size - 1 ? length : size - 1;
        memcpy(destination, source, count);
        destination[count] = 0;
    }
    return length;
}
int unsetenv(const char *name) {
    unsigned length = strlen(name), i = 0, j;
    if (!length || strchr(name, '=')) {
        errno = EINVAL;
        return -1;
    }
    while (_environ && _environ[i]) {
        if (!strncmp(_environ[i], name, length) && _environ[i][length] == '=') {
            for (j = i; _environ[j]; j++)
                _environ[j] = _environ[j + 1];
        } else
            i++;
    }
    return 0;
}
int Snowsetenv(const char *name, const char *value, int overwrite) {
    /* The installed termcap predates xterm-color. Keep shell applications
     * on a terminal description that OPENSTEP can actually resolve. */
    if (name && value && !strcmp(name, "TERM") && tgetent(NULL, value) == 0)
        value = "xterm";
    return Tigersetenv(name, value, overwrite);
}
typedef struct {
    unsigned device;
    unsigned short mode, links;
    unsigned long long inode;
    unsigned uid, gid, rdevice;
    int times[8];
    long long size, blocks;
    unsigned blocksize, flags, generation;
    int spare;
    long long reserved[2];
} SnowStat64;
int Snowstat64(const char *path, SnowStat64 *out) {
    struct stat native;
    int result = stat(path, &native);
    if (result)
        return result;
    memset(out, 0, sizeof(*out));
    out->device = native.st_dev;
    out->mode = native.st_mode;
    out->links = native.st_nlink;
    out->inode = native.st_ino;
    out->uid = native.st_uid;
    out->gid = native.st_gid;
    out->rdevice = native.st_rdev;
    out->times[0] = native.st_atime;
    out->times[2] = native.st_mtime;
    out->times[4] = native.st_ctime;
    out->size = native.st_size;
    out->blocks = native.st_blocks;
    out->blocksize = native.st_blksize;
    return 0;
}
typedef struct {
    unsigned blockSize;
    int ioSize;
    unsigned long long blocks, freeBlocks, availableBlocks, files, freeFiles;
    int fsid[2];
    unsigned owner, type, flags, subtype;
    char typeName[16], mountedOn[1024], mountedFrom[1024];
    unsigned reserved[8];
} SnowStatfs64;
typedef char SnowStatfs64SizeCheck[sizeof(SnowStatfs64) == 2168 ? 1 : -1];
int Snowstatfs64(const char *path, SnowStatfs64 *out) {
    struct statfs native;
    int result = statfs(path, &native), savedError = errno;
    if (result)
        return result;
    memset(out, 0, sizeof(*out));
    out->blockSize = native.f_bsize;
    out->ioSize = native.f_bsize;
    out->blocks = native.f_blocks;
    out->freeBlocks = native.f_bfree;
    out->availableBlocks = native.f_bavail;
    out->files = native.f_files;
    out->freeFiles = native.f_ffree;
    memcpy(out->fsid, &native.f_fsid, sizeof(out->fsid));
    out->type = native.f_type;
    /* OPENSTEP statfs has no mount flags; Terminal only tests MNT_RDONLY. */
    out->flags = (access(path, W_OK) < 0 && errno == EROFS) ? 1 : 0;
    errno = savedError;
    return 0;
}
/* The low-swap monitor is optional; OPENSTEP has no Darwin event queue. */
int kqueue(void) {
    errno = EOPNOTSUPP;
    return -1;
}
int kevent(int queue, const void *changes, int count, void *events, int capacity,
           const void *timeout) {
    errno = EOPNOTSUPP;
    return -1;
}
int fsctl(const char *path, unsigned command, void *data, unsigned options) {
    errno = EOPNOTSUPP;
    return -1;
}
void SnowWriteInsetRect(NSRect *out, NSRect rect, float x, float y) {
    *out = NSInsetRect(rect, x, y);
}
void SnowWriteIntegralRect(NSRect *out, NSRect rect) {
    *out = NSIntegralRect(rect);
}
void SnowWriteTiledRects(NSRect *out, NSRect rect, NSRect clip, const NSRectEdge *edges,
                         const float *grays, int count) {
    *out = NSDrawTiledRects(rect, clip, edges, grays, count);
}
asm(".text\n.align 2\n.globl _SnowNSDrawTiledRects\n_SnowNSDrawTiledRects:\n"
    "pushl %ebp\nmovl %esp,%ebp\nsubl $48,%esp\npushl %esi\npushl %edi\n"
    "leal 8(%ebp),%esi\nleal -48(%ebp),%edi\nmovl $12,%ecx\ncld\nrep\nmovsl\n"
    "popl %edi\npopl %esi\ncall _SnowWriteTiledRects\nmovl 8(%ebp),%eax\nleave\nret $4\n");
asm(".text\n.align 2\n.globl _SnowNSInsetRect\n_SnowNSInsetRect:\n"
    "pushl %ebp\nmovl %esp,%ebp\nsubl $28,%esp\npushl %esi\npushl %edi\n"
    "leal 8(%ebp),%esi\nleal -28(%ebp),%edi\nmovl $7,%ecx\ncld\nrep\nmovsl\n"
    "popl %edi\npopl %esi\ncall _SnowWriteInsetRect\nmovl 8(%ebp),%eax\nleave\nret $4\n"
    ".align 2\n.globl _SnowNSIntegralRect\n_SnowNSIntegralRect:\n"
    "pushl %ebp\nmovl %esp,%ebp\nsubl $20,%esp\npushl %esi\npushl %edi\n"
    "leal 8(%ebp),%esi\nleal -20(%ebp),%edi\nmovl $5,%ecx\ncld\nrep\nmovsl\n"
    "popl %edi\npopl %esi\ncall _SnowWriteIntegralRect\nmovl 8(%ebp),%eax\nleave\nret $4\n");
