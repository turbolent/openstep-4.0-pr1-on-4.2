/* File metadata layout used by DR2 Intel binaries. */
#ifndef DR2_ABI_H
#define DR2_ABI_H

struct DR2Stat {
    unsigned dev, ino;
    unsigned short mode, links;
    unsigned uid, gid, rdev;
    long accessTime, accessNsec, modifyTime, modifyNsec, changeTime, changeNsec;
    long long size, blocks;
    unsigned blocksize, flags, generation;
    int spare;
    long long spare2[2];
};
#endif
