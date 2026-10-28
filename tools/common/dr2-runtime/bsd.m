/* Bridge framework-wide BSD layouts to native OPENSTEP services. */
#import <Foundation/Foundation.h>
#include <pwd.h>
#include <grp.h>
#include <sys/param.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/dir.h>
#include <unistd.h>
#include <errno.h>
#include <limits.h>
#include <string.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <signal.h>
#include "../dr2-abi.h"
#include "runtime-path.h"

struct DR2Passwd {
    char *name, *password;
    int uid, gid;
    long change;
    char *accessClass, *gecos, *directory, *shell;
    long expire;
};
static struct DR2Passwd *convertUser(struct passwd *user) {
    static struct DR2Passwd result;
    if (!user)
        return NULL;
    memset(&result, 0, sizeof(result));
    result.name = user->pw_name;
    result.password = user->pw_passwd;
    result.uid = user->pw_uid;
    result.gid = user->pw_gid;
    result.accessClass = "";
    result.gecos = user->pw_gecos;
    result.directory = user->pw_dir;
    result.shell = user->pw_shell;
    return &result;
}
struct DR2Passwd *DR2getpwuid(unsigned uid) {
    return convertUser(getpwuid(uid));
}
struct DR2Passwd *DR2getpwnam(const char *name) {
    return convertUser(getpwnam(name));
}
struct DR2Passwd *DR2getpwent(void) {
    return convertUser(getpwent());
}

struct DR2Group {
    char *name, *password;
    int gid;
    char **members;
};
enum {
    DR2DirectoryHeaderSize = 8,
    DR2DirectoryTypeOffset = 6,
    DR2DirectoryLengthOffset = 7
};
static struct DR2Group *convertGroup(struct group *group) {
    static struct DR2Group result;
    if (!group)
        return NULL;
    result.name = group->gr_name;
    result.password = group->gr_passwd;
    result.gid = group->gr_gid;
    result.members = group->gr_mem;
    return &result;
}
struct DR2Group *DR2getgrgid(unsigned gid) {
    return convertGroup(getgrgid(gid));
}
struct DR2Group *DR2getgrnam(const char *name) {
    return convertGroup(getgrnam(name));
}
struct DR2Group *DR2getgrent(void) {
    return convertGroup(getgrent());
}

DIR *__opendir2(const char *path, int flags) {
    return opendir(path);
}

int DR2getdirentries(int fd, char *buffer, unsigned size, long *base) {
    int result = getdirentries(fd, buffer, size, base), offset = 0;
    while (offset < result) {
        struct direct *entry = (struct direct *)(buffer + offset);
        unsigned length = entry->d_namlen, record = entry->d_reclen;
        if (record < DR2DirectoryHeaderSize || offset + record > result) {
            errno = EIO;
            return -1;
        }
        buffer[offset + DR2DirectoryTypeOffset] = 0;
        buffer[offset + DR2DirectoryLengthOffset] = length;
        offset += record;
    }
    return result;
}
long long DR2lseek(int fd, long long offset, int whence) {
    if (offset < LONG_MIN || offset > LONG_MAX) {
        errno = ERANGE;
        return -1;
    }
    return lseek(fd, (long)offset, whence);
}
int DR2truncate(const char *path, long long size) {
    if (size < 0 || size > LONG_MAX) {
        errno = ERANGE;
        return -1;
    }
    return truncate(path, (long)size);
}
int DR2ftruncate(int fd, long long size) {
    if (size < 0 || size > LONG_MAX) {
        errno = ERANGE;
        return -1;
    }
    return ftruncate(fd, (long)size);
}
struct DR2Limit {
    unsigned long long current, maximum;
};
static const unsigned long long DR2UnlimitedResource = 0x7fffffffffffffffULL;
int DR2getrlimit(int resource, struct DR2Limit *out) {
    struct rlimit native;
    int result = getrlimit(resource, &native);
    if (!result) {
        out->current = native.rlim_cur == RLIM_INFINITY ? DR2UnlimitedResource : native.rlim_cur;
        out->maximum = native.rlim_max == RLIM_INFINITY ? DR2UnlimitedResource : native.rlim_max;
    }
    return result;
}
int DR2setrlimit(int resource, const struct DR2Limit *in) {
    struct rlimit native;
    native.rlim_cur = in->current >= RLIM_INFINITY ? RLIM_INFINITY : in->current;
    native.rlim_max = in->maximum >= RLIM_INFINITY ? RLIM_INFINITY : in->maximum;
    return setrlimit(resource, &native);
}
#undef ___toupper
int ___toupper(int c) {
    return c >= 'a' && c <= 'z' ? c - 'a' + 'A' : c;
}

enum {
    DR2ApplicationDirectory = 1,
    DR2DemoDirectory,
    DR2DeveloperApplicationDirectory,
    DR2AdminDirectory,
    DR2LibraryDirectory,
    DR2DeveloperDirectory,
    DR2UserDirectory,
    DR2DocumentationDirectory,
    DR2AllApplications = 100,
    DR2AllLibraries,
    SearchDirectoryShift = 16,
    SearchDomainShift = 8,
    SearchCursorMask = 255,
    SearchDomainMask = 15,
    SearchDomainCount = 4,
    ApplicationDirectoryCount = 4,
    LibraryDirectoryCount = 2,
    LibraryDomainCount = SearchDomainCount + 1
};
unsigned NSStartSearchPathEnumeration(unsigned directory, unsigned domains) {
    return (directory << SearchDirectoryShift) |
           ((domains & SearchDomainMask) << SearchDomainShift) | 1;
}
unsigned NSGetNextSearchPathEnumeration(unsigned state, char *path) {
    unsigned directory = state >> SearchDirectoryShift;
    unsigned domains = (state >> SearchDomainShift) & SearchDomainMask;
    unsigned cursor = (state & SearchCursorMask) - 1;
    const char *libraries[] = {"~/Library", "/LocalLibrary", "/Network/Library",
                               DR2_RUNTIME_PATH "/Library", "/NextLibrary"};
    const char *applications[] = {"~/Apps", "/LocalApps", "/Network/Apps", "/NextApps"};
    const char *demos[] = {"~/Demos", "/LocalApps/Demos", "/Network/Demos", "/NextDeveloper/Demos"};
    const char *developerApps[] = {"~/Developer/Apps", "/LocalDeveloper/Apps",
                                   "/Network/Developer/Apps", "/NextDeveloper/Apps"};
    const char *admin[] = {"~/Admin", "/LocalAdmin", "/Network/Admin", "/NextAdmin"};
    const char *developer[] = {"~/Developer", "/LocalDeveloper", "/Network/Developer",
                               DR2_RUNTIME_PATH "/Developer", "/NextDeveloper"};
    const char *value;
    unsigned count = directory == DR2AllApplications ? ApplicationDirectoryCount
                     : directory == DR2AllLibraries  ? LibraryDirectoryCount
                                                     : 1;
    unsigned domainCount = directory == DR2LibraryDirectory || directory == DR2AllLibraries ||
                                   directory == DR2DocumentationDirectory ||
                                   directory == DR2DeveloperDirectory
                               ? LibraryDomainCount
                               : SearchDomainCount;
    while (cursor < domainCount * count) {
        unsigned domain = cursor / count, type = directory;
        if (directory == DR2AllApplications)
            type = DR2ApplicationDirectory + cursor % count;
        else if (directory == DR2AllLibraries)
            type = DR2LibraryDirectory + cursor % count;
        cursor++;
        if (!(domains & (1 << (domain < SearchDomainCount ? domain : SearchDomainCount - 1))))
            continue;
        value = NULL;
        switch (type) {
        case DR2ApplicationDirectory:
            value = applications[domain];
            break;
        case DR2DemoDirectory:
            value = demos[domain];
            break;
        case DR2DeveloperApplicationDirectory:
            value = developerApps[domain];
            break;
        case DR2AdminDirectory:
            value = admin[domain];
            break;
        case DR2LibraryDirectory:
            value = libraries[domain];
            break;
        case DR2DeveloperDirectory:
            value = developer[domain];
            break;
        case DR2UserDirectory:
            value = domain == SearchDomainCount - 1 ? "/" : NULL;
            break;
        case DR2DocumentationDirectory:
            strcpy(path, libraries[domain]);
            strcat(path, "/Documentation");
            return (state & ~SearchCursorMask) | (cursor + 1);
        }
        if (value) {
            strcpy(path, value);
            return (state & ~SearchCursorMask) | (cursor + 1);
        }
    }
    return 0;
}

int setsid(void) {
    int pid = getpid(), fd;
    if (getpgrp(0) == pid) {
        errno = EPERM;
        return -1;
    }
    if (setpgrp(0, pid) < 0)
        return -1;
    fd = open("/dev/tty", O_RDWR);
    if (fd >= 0) {
        ioctl(fd, TIOCNOTTY, 0);
        close(fd);
    }
    return pid;
}
int sigsuspend(const unsigned *mask) {
    return sigpause(*mask);
}
