/* Darwin i386 C layouts adapted to OPENSTEP's BSD interfaces. */
#import <Foundation/Foundation.h>
#include <libc.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <pwd.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/vfs.h>
#include <mach/mach.h>

int *__error(void) {
    return &errno;
}
/* The old BSD usleep uses process-wide SIGALRM and hangs worker threads.
 * Mach's timed wait sleeps only the calling thread, rounded up to a tick. */
int Tigerusleep(unsigned microseconds) {
    unsigned milliseconds = microseconds / 1000 + (microseconds % 1000 != 0);
    if (!milliseconds)
        return 0;
    if (thread_switch(0, SWITCH_OPTION_WAIT, milliseconds) != KERN_SUCCESS) {
        errno = EINTR;
        return -1;
    }
    return 0;
}
double fmax(double a, double b) {
    return a != a ? b : (b != b || a > b ? a : b);
}
float modff(float value, float *integer) {
    double n, f = modf(value, &n);
    *integer = n;
    return f;
}
void *reallocf(void *old, unsigned size) {
    void *p = realloc(old, size);
    if (!p && size)
        free(old);
    return p;
}

typedef struct {
    char magic[8], encoding[32];
    void *get, *put;
    int invalid;
    unsigned type[256];
    int lower[256], upper[256];
    char spare[32];
} TigerRuneLocale;
TigerRuneLocale _DefaultRuneLocale;
unsigned __maskrune(int value, unsigned mask) {
    return value >= 0 && value < 256 ? _DefaultRuneLocale.type[value] & mask : 0;
}

typedef struct {
    unsigned char *position;
    int readCount, writeCount;
    unsigned short flags;
    short descriptor;
    char rest[72];
} TigerFILE;
typedef struct {
    TigerFILE tiger;
    FILE *native;
} TigerWrappedFILE;
TigerFILE __sF[3];
static FILE *tigerNativeFile(TigerFILE *file) {
    if (file == &__sF[0])
        return stdin;
    if (file == &__sF[1])
        return stdout;
    if (file == &__sF[2])
        return stderr;
    return file ? ((TigerWrappedFILE *)file)->native : NULL;
}
int Tigerfprintf(TigerFILE *file, const char *format, ...) {
    int result;
    va_list args;
    va_start(args, format);
    result = vfprintf(tigerNativeFile(file), format, args);
    va_end(args);
    return result;
}
int Tigerfputc(int value, TigerFILE *file) {
    return fputc(value, tigerNativeFile(file));
}
int Tigerfflush(TigerFILE *file) {
    return fflush(tigerNativeFile(file));
}
TigerFILE *Tigerpopen(const char *command, const char *mode) {
    TigerWrappedFILE *wrapped;
    FILE *file = popen(command, mode);
    if (!file)
        return NULL;
    wrapped = calloc(1, sizeof(*wrapped));
    if (!wrapped) {
        pclose(file);
        return NULL;
    }
    wrapped->native = file;
    wrapped->tiger.descriptor = fileno(file);
    return &wrapped->tiger;
}
int Tigerpclose(TigerFILE *file) {
    int result = pclose(tigerNativeFile(file));
    free(file);
    return result;
}

typedef struct {
    unsigned dev, ino;
    unsigned short mode, links;
    unsigned uid, gid, rdev;
    int atime, ansec, mtime, mnsec, ctime, cnsec;
    long long size, blocks;
    unsigned blocksize, flags, generation;
    int spare;
    long long spare2[2];
} TigerStat;
static void tigerCopyStat(TigerStat *out, struct stat *in) {
    memset(out, 0, sizeof(*out));
    out->dev = in->st_dev;
    out->ino = in->st_ino;
    out->mode = in->st_mode;
    out->links = in->st_nlink;
    out->uid = in->st_uid;
    out->gid = in->st_gid;
    out->rdev = in->st_rdev;
    out->atime = in->st_atime;
    out->mtime = in->st_mtime;
    out->ctime = in->st_ctime;
    out->size = in->st_size;
    out->blocks = in->st_blocks;
    out->blocksize = in->st_blksize;
}
int Tigerstat(const char *path, TigerStat *out) {
    struct stat value;
    int r = stat(path, &value);
    if (!r)
        tigerCopyStat(out, &value);
    return r;
}
int Tigerfstat(int fd, TigerStat *out) {
    struct stat value;
    int r = fstat(fd, &value);
    if (!r)
        tigerCopyStat(out, &value);
    return r;
}
int Tigerstatfs(const char *path, void *out) {
    struct statfs value;
    int r = statfs(path, &value);
    unsigned *v = out;
    if (r)
        return r;
    memset(out, 0, 256);
    v[1] = value.f_bsize;
    v[3] = value.f_blocks;
    v[4] = value.f_bfree;
    v[5] = value.f_bavail;
    v[6] = value.f_files;
    v[7] = value.f_ffree;
    /* Terminal only asks whether its root volume is read-only. */
    v[12] = (access(path, W_OK) < 0 && errno == EROFS) ? 1 : 0;
    return 0;
}

typedef struct {
    char *name, *password;
    unsigned uid, gid;
    int change;
    char *className, *gecos, *directory, *shell;
    int expire, fields;
} TigerPasswd;
static TigerPasswd *tigerCopyPasswd(struct passwd *p) {
    static TigerPasswd result;
    if (!p)
        return NULL;
    memset(&result, 0, sizeof(result));
    result.name = p->pw_name;
    result.password = p->pw_passwd;
    result.uid = p->pw_uid;
    result.gid = p->pw_gid;
    result.className = "";
    result.gecos = p->pw_gecos;
    result.directory = p->pw_dir;
    result.shell = p->pw_shell;
    return &result;
}
TigerPasswd *Tigergetpwuid(unsigned uid) {
    return tigerCopyPasswd(getpwuid(uid));
}
TigerPasswd *Tigergetpwnam(const char *name) {
    return tigerCopyPasswd(getpwnam(name));
}

int Tigersetenv(const char *name, const char *value, int overwrite) {
    extern char **environ;
    unsigned n = 0, i, length;
    char **copy, *entry;
    if (!name || !*name || strchr(name, '=') || !value) {
        errno = EINVAL;
        return -1;
    }
    length = strlen(name);
    while (environ[n])
        n++;
    for (i = 0; i < n; i++)
        if (!strncmp(environ[i], name, length) && environ[i][length] == '=')
            break;
    if (i < n && !overwrite)
        return 0;
    entry = malloc(length + strlen(value) + 2);
    if (!entry)
        return -1;
    sprintf(entry, "%s=%s", name, value);
    copy = malloc((n + 2) * sizeof(char *));
    if (!copy) {
        free(entry);
        return -1;
    }
    memcpy(copy, environ, (n + 1) * sizeof(char *));
    copy[i] = entry;
    if (i == n)
        copy[n + 1] = NULL;
    environ = copy;
    return 0;
}

typedef struct {
    unsigned input, output, control, local;
    unsigned char chars[20];
    unsigned ispeed, ospeed;
} TigerTermios;
static struct {
    int master, device;
} tigerPTYs[128];
static unsigned tigerPTYCount;
static NSLock *tigerProcessLock;
int Tigerclose(int fd) {
    unsigned i;
    [tigerProcessLock lock];
    for (i = 0; i < tigerPTYCount; i++)
        if (tigerPTYs[i].master == fd) {
            tigerPTYs[i] = tigerPTYs[--tigerPTYCount];
            break;
        }
    [tigerProcessLock unlock];
    return close(fd);
}
static const unsigned tigerSpeeds[] = {0,     50,    75,    110,   134,   150,  200,
                                       300,   600,   1200,  1800,  2400,  4800, 9600,
                                       19200, 38400, 14400, 28800, 43200, 57600};
static const unsigned char tigerCharMap[17] = {0,  1,  3, 5, 8,  9,  10, 12, 13,
                                               16, 17, 4, 6, 14, 15, 11, 19};
static const unsigned tigerLocalBits[][2] = {
    {1, ECHOKE},    {2, ECHOE},           {4, ECHOK},          {8, ECHO},     {16, ECHONL},
    {32, ECHOPRT},  {64, ECHOCTL},        {128, ISIG},         {256, ICANON}, {512, ALTWERASE},
    {1024, IEXTEN}, {0x00400000, TOSTOP}, {0x80000000, NOFLSH}};
int Tigertcgetattr(int fd, TigerTermios *out) {
    struct termios native;
    unsigned i;
    int r = ioctl(fd, TIOCGETA, &native);
    if (r < 0)
        return r;
    memset(out, 0, sizeof(*out));
    out->input = native.c_iflag;
    out->output = native.c_oflag;
    out->control = native.c_cflag;
    for (i = 0; i < sizeof(tigerLocalBits) / sizeof(tigerLocalBits[0]); i++)
        if (native.c_lflag & tigerLocalBits[i][1])
            out->local |= tigerLocalBits[i][0];
    memset(out->chars, 255, sizeof(out->chars));
    for (i = 0; i < 17; i++)
        out->chars[tigerCharMap[i]] = native.c_cc[i];
    out->ispeed =
        (unsigned char)native.c_ispeed < 20 ? tigerSpeeds[(unsigned char)native.c_ispeed] : 9600;
    out->ospeed =
        (unsigned char)native.c_ospeed < 20 ? tigerSpeeds[(unsigned char)native.c_ospeed] : 9600;
    return 0;
}
int Tigertcsetattr(int fd, int action, const TigerTermios *in) {
    struct termios native;
    unsigned i;
    memset(&native, 0, sizeof(native));
    native.c_iflag = in->input;
    native.c_oflag = in->output;
    native.c_cflag = in->control;
    for (i = 0; i < sizeof(tigerLocalBits) / sizeof(tigerLocalBits[0]); i++)
        if (in->local & tigerLocalBits[i][0])
            native.c_lflag |= tigerLocalBits[i][1];
    /* OPENSTEP splits visual erase into backspacing (ECHOE) and wiping the
     * displayed character (ECHOCRT). Darwin's ECHOE requests both. */
    if (in->local & 2)
        native.c_lflag |= ECHOCRT;
    for (i = 0; i < 17; i++)
        native.c_cc[i] = in->chars[tigerCharMap[i]];
    native.c_ispeed = native.c_ospeed = B9600;
    for (i = 0; i < 20; i++) {
        if (in->ispeed == tigerSpeeds[i])
            native.c_ispeed = i;
        if (in->ospeed == tigerSpeeds[i])
            native.c_ospeed = i;
    }
    return ioctl(fd, action == 1 ? TIOCSETAW : action == 2 ? TIOCSETAF : TIOCSETA, &native);
}
int Tigerioctl(int fd, unsigned request, void *argument) {
    if (request == 0x4004741a)
        request = TIOCGETD;
    else if (request == 0x8004741b)
        request = TIOCSETD;
    return ioctl(fd, request, argument);
}
static int (*tigerPTYAvailable)(const char *slave);
int Tigerforkpty(int *masterOut, char *name, const TigerTermios *settings,
                 const struct winsize *size) {
    int master = -1, pid, slave, tty, pgrp, group, digit;
    char masterName[] = "/dev/ptyp0", slaveName[] = "/dev/ttyp0";
    const char *groups = "pqrstuvwxyz", *digits = "0123456789abcdef";
    for (group = 0; groups[group] && master < 0; group++)
        for (digit = 0; digit < 16; digit++) {
            masterName[8] = groups[group];
            masterName[9] = digits[digit];
            slaveName[8] = groups[group];
            slaveName[9] = digits[digit];
            if (tigerPTYAvailable && !tigerPTYAvailable(slaveName))
                continue;
            master = open(masterName, O_RDWR);
            if (master >= 0)
                break;
        }
    if (master < 0)
        return -1;
    slaveName[8] = masterName[8];
    slaveName[9] = masterName[9];
    if (name)
        strcpy(name, slaveName);
    [tigerProcessLock lock];
    pid = fork();
    [tigerProcessLock unlock];
    if (pid < 0) {
        close(master);
        return -1;
    }
    if (pid) {
        struct stat ttyStat;
        unsigned slot;
        *masterOut = master;
        if (stat(slaveName, &ttyStat) == 0) {
            [tigerProcessLock lock];
            for (slot = 0; slot < tigerPTYCount && tigerPTYs[slot].master != master; slot++)
                ;
            if (slot < 128) {
                tigerPTYs[slot].master = master;
                tigerPTYs[slot].device = ttyStat.st_rdev;
                if (slot == tigerPTYCount)
                    tigerPTYCount++;
            }
            [tigerProcessLock unlock];
        }
        return pid;
    }
    close(master);
    pgrp = getpid();
    setpgrp(0, pgrp);
    tty = open("/dev/tty", O_RDWR);
    if (tty >= 0) {
        ioctl(tty, TIOCNOTTY, 0);
        close(tty);
    }
    slave = open(slaveName, O_RDWR);
    if (slave < 0)
        _exit(126);
    ioctl(slave, TIOCSPGRP, &pgrp);
    if (settings)
        Tigertcsetattr(slave, 0, settings);
    if (size)
        ioctl(slave, TIOCSWINSZ, size);
    dup2(slave, 0);
    dup2(slave, 1);
    dup2(slave, 2);
    if (slave > 2)
        close(slave);
    return 0;
}

int tgetent(char *buffer, const char *name) {
    char line[2048];
    FILE *file = fopen("/etc/termcap", "r");
    int found = 0;
    if (!file)
        return -1;
    while (fgets(line, sizeof(line), file)) {
        char *p = line, *end;
        if (*p == '#' || isspace(*p))
            continue;
        while ((end = strpbrk(p, "|:")) != NULL) {
            if ((unsigned)(end - p) == strlen(name) && !strncmp(p, name, end - p)) {
                found = 1;
                break;
            }
            if (*end == ':')
                break;
            p = end + 1;
        }
        if (found)
            break;
    }
    fclose(file);
    if (found && buffer)
        strcpy(buffer, line);
    return found;
}
void *pututxline(const void *entry) {
    errno = EOPNOTSUPP;
    return NULL;
}

/* OPENSTEP's table(10) is indexed by PID, not by a dense process slot. */
typedef struct {
    int uid, pid, parent, group, tty, status, flags;
    char command[20];
} TigerNativeProcess;
extern int table(int, int, void *, int, unsigned);
static TigerNativeProcess *tigerProcesses;
static unsigned tigerProcessCount, tigerProcessCapacity;
static struct timeval tigerProcessTime;
static int tigerRefreshProcesses(void) {
    struct timeval now;
    long long elapsed;
    int pid;
    TigerNativeProcess process;
    gettimeofday(&now, NULL);
    elapsed = ((long long)now.tv_sec - tigerProcessTime.tv_sec) * 1000000 + now.tv_usec -
              tigerProcessTime.tv_usec;
    if (tigerProcessTime.tv_sec && elapsed >= 0 && elapsed < 1000000)
        return 0;
    tigerProcessCount = 0;
    for (pid = 1; pid < 32768; pid++) {
        if (table(10, pid, &process, 1, sizeof(process)) != 1 || process.status != 1)
            continue;
        if (tigerProcessCount == tigerProcessCapacity) {
            unsigned capacity = tigerProcessCapacity + 64;
            TigerNativeProcess *replacement = realloc(tigerProcesses, capacity * sizeof(process));
            if (!replacement) {
                tigerProcessTime.tv_sec = 0;
                errno = ENOMEM;
                return -1;
            }
            tigerProcesses = replacement;
            tigerProcessCapacity = capacity;
        }
        tigerProcesses[tigerProcessCount++] = process;
    }
    tigerProcessTime = now;
    return 0;
}
int sysctl(const int *mib, unsigned count, void *out, unsigned *length, const void *newValue,
           unsigned newLength) {
    int foreground = -1;
    unsigned i, needed = 0;
    unsigned char *entry = out;
    if (count != 4 || mib[0] != 1 || mib[1] != 14 || mib[2] != 4 || newValue || !length) {
        errno = EOPNOTSUPP;
        return -1;
    }
    [tigerProcessLock lock];
    /* One native enumeration per second, shared by all terminal windows.
     * Keep the size/data pair on the same cache generation. */
    if (!out && tigerRefreshProcesses() < 0) {
        [tigerProcessLock unlock];
        return -1;
    }
    for (i = 0; i < tigerProcessCount; i++)
        if (tigerProcesses[i].tty == mib[3])
            needed += 492;
    if (!out) {
        *length = needed;
        [tigerProcessLock unlock];
        return 0;
    }
    if (*length < needed) {
        *length = needed;
        [tigerProcessLock unlock];
        errno = ENOMEM;
        return -1;
    }
    for (i = 0; i < tigerPTYCount; i++)
        if (tigerPTYs[i].device == mib[3])
            ioctl(tigerPTYs[i].master, TIOCGPGRP, &foreground);
    for (i = 0; i < tigerProcessCount; i++) {
        TigerNativeProcess *process = &tigerProcesses[i];
        if (process->tty != mib[3])
            continue;
        memset(entry, 0, 492);
        *(int *)(entry + 0x18) = process->pid;
        strncpy((char *)entry + 0xa3, process->command, 16);
        *(int *)(entry + 0x1a0) = process->parent;
        *(int *)(entry + 0x1a4) = abs(process->group);
        *(int *)(entry + 0x1b0) = foreground;
        entry += 492;
    }
    *length = needed;
    [tigerProcessLock unlock];
    return 0;
}

void TigerInitializeCABI(void) {
    int c;
    if (!tigerProcessLock)
        tigerProcessLock = [[NSLock alloc] init];
    for (c = 0; c < 256; c++) {
        unsigned flags = 0;
        if (isalpha(c))
            flags |= 0x100;
        if (iscntrl(c))
            flags |= 0x200;
        if (isdigit(c))
            flags |= 0x400;
        if (isgraph(c))
            flags |= 0x800;
        if (islower(c))
            flags |= 0x1000;
        if (ispunct(c))
            flags |= 0x2000;
        if (isspace(c))
            flags |= 0x4000;
        if (isupper(c))
            flags |= 0x8000;
        if (isxdigit(c))
            flags |= 0x10000;
        if (c == ' ' || c == '\t')
            flags |= 0x20000;
        if (isprint(c))
            flags |= 0x40000;
        _DefaultRuneLocale.type[c] = flags;
        _DefaultRuneLocale.lower[c] = tolower(c);
        _DefaultRuneLocale.upper[c] = toupper(c);
    }
    for (c = 0; c < 3; c++)
        __sF[c].descriptor = c;
}
