/* Adapt DR2 Viewer's private file-attribute methods to native stat records. */
#import <Foundation/Foundation.h>
#import <objc/objc-class.h>
#include <sys/stat.h>
#include <string.h>
#include "common/dr2-abi.h"

@interface NSFileAttributes : NSDictionary
+ attributesWithStat:(struct stat *)value;
@end
static struct stat *nativeAttributes(id object) {
    Ivar field = class_getInstanceVariable([NSFileAttributes class], "statInfo");
    return (struct stat *)((char *)object + field->ivar_offset);
}
@implementation NSFileAttributes (DR2FileAttributes)
+ attributesWithDR2:(struct DR2Stat *)value {
    struct stat native;
    memset(&native, 0, sizeof(native));
    native.st_dev = value->dev;
    native.st_ino = value->ino;
    native.st_mode = value->mode;
    native.st_nlink = value->links;
    native.st_uid = value->uid;
    native.st_gid = value->gid;
    native.st_rdev = value->rdev;
    native.st_size = value->size;
    native.st_atime = value->accessTime;
    native.st_mtime = value->modifyTime;
    native.st_ctime = value->changeTime;
    native.st_blocks = value->blocks;
    native.st_blksize = value->blocksize;
    return [self attributesWithStat:&native];
}
- (unsigned)dr2_getStatDev { return (unsigned short)nativeAttributes(self)->st_dev; }
- (unsigned)dr2_getUID { return (unsigned short)nativeAttributes(self)->st_uid; }
- (unsigned)dr2_getGID { return (unsigned short)nativeAttributes(self)->st_gid; }
- (unsigned)dr2_getINode { return nativeAttributes(self)->st_ino; }
- (long)dr2_getLastChangeTime { return nativeAttributes(self)->st_ctime; }
- (long)dr2_mtime { return nativeAttributes(self)->st_mtime; }
- (NSDate *)dr2fileChangeDate {
    return [NSDate dateWithTimeIntervalSince1970:nativeAttributes(self)->st_ctime];
}
- (BOOL)dr2areEqualUID:(id)other {
    struct stat *left = nativeAttributes(self), *right = nativeAttributes(other);
    return left->st_dev == right->st_dev && left->st_ino == right->st_ino;
}
- (BOOL)dr2isSameDevice:(id)other {
    return nativeAttributes(self)->st_dev == nativeAttributes(other)->st_dev;
}
- (void)dr2buildDirFileUID:(unsigned *)value {
    value[0] = (unsigned short)nativeAttributes(self)->st_dev;
    value[1] = nativeAttributes(self)->st_ino;
}
@end

/* The executable's WSStatMethods category loads after the compatibility
 * library. Install these adapters once Viewer has finished loading. */
void DR2InitializeFileAttributes(void) {
    const char *names[] = {
        "_getStatDev", "_getUID", "_getGID", "_getINode", "_getLastChangeTime",
        "_mtime", "fileChangeDate", "areEqualUID:", "isSameDevice:", "buildDirFileUID:"
    };
    const char *adapters[] = {
        "dr2_getStatDev", "dr2_getUID", "dr2_getGID", "dr2_getINode",
        "dr2_getLastChangeTime", "dr2_mtime", "dr2fileChangeDate",
        "dr2areEqualUID:", "dr2isSameDevice:", "dr2buildDirFileUID:"
    };
    unsigned i;
    for (i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        Method original = class_getInstanceMethod([NSFileAttributes class], sel_registerName(names[i]));
        Method replacement = class_getInstanceMethod([NSFileAttributes class], sel_registerName(adapters[i]));
        if (original) original->method_imp = replacement->method_imp;
    }
}
