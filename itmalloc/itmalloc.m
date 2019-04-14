//
//  itmalloc.m
//  itmalloc
//
//  Created by George Nachman on 4/14/19.
//

#import "itmalloc.h"
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <malloc/malloc.h>
#include <mach/mach_init.h>
#include <mach/vm_map.h>


#define DYLD_INTERPOSE(_replacment,_replacee) \
__attribute__((used)) static struct{ const void* replacment; const void* replacee; } _interpose_##_replacee \
__attribute__ ((section ("__DATA,__interpose"))) = { (const void*)(unsigned long)&_replacment, (const void*)(unsigned long)&_replacee };

//
//void* pMalloc(size_t size) //would be nice if I didn't have to rename my function..
//{
//    char *p = (char *)malloc(size);
//    for (int i = 0; i < size; i++) {
//        p[i] = 'G';
//    }
//    return p;
//}
//
//DYLD_INTERPOSE(pMalloc, malloc);

static const char *premagic = "abcdefgh";
static const char *postmagic = "zyxwvuts";
static const size_t prologueLength = 16;
static const size_t sizeOffset = 8;
static const size_t preMagicOffset = 0;
static const size_t epilogueLength = 8;
static const size_t totalOverhead = prologueLength + epilogueLength;

static void WriteMetadata(void *p, size_t size) {
    memmove(p + preMagicOffset, premagic, 8);
    memmove(p + sizeOffset, &size, sizeof(size));
    memmove(p + prologueLength + size, postmagic, 8);
}

static void CheckMemory(void *ptr) {
    void *realP = ptr - prologueLength;

    // Get size
    size_t size;
    memmove(&size, realP + sizeOffset, sizeof(size_t));

    // Check premagic
    if (memcmp(realP + preMagicOffset, premagic, 8)) {
        while (1);
    }

    // Check postmagic
    void *post = ptr + size;
    if (memcmp(post, postmagic, 8)) {
        while (1);
    }
}

void *ITMalloc(size_t size) {
    void *p = malloc(size + totalOverhead);
    if (p == 0) {
        return p;
    }
    WriteMetadata(p, size);
    CheckMemory(p + prologueLength);
    return p + prologueLength;
}
DYLD_INTERPOSE(ITMalloc, malloc);

void *ITCalloc(size_t count, size_t elementSize) {
    const size_t size = count * elementSize;
    void *p = calloc(1, size + totalOverhead);
    if (p == 0) {
        return p;
    }
    WriteMetadata(p, size);
    return p + prologueLength;
}
DYLD_INTERPOSE(ITCalloc, calloc);

void ITFree(void *ptr) {
    CheckMemory(ptr);

    void *realP = ptr - prologueLength;
    free(realP);
}
DYLD_INTERPOSE(ITFree, free);

void *ITRealloc(void *ptr, size_t size) {
    if (ptr != NULL) {
        CheckMemory(ptr);
    }

    void *realP = ptr - prologueLength;
    void *newp = realloc(realP, size + totalOverhead);
    if (newp == 0) {
        return newp;
    }
    WriteMetadata(newp, size);

    return newp + prologueLength;
}
DYLD_INTERPOSE(ITRealloc, realloc);

void *ITReallocf(void *ptr, size_t size) {
    CheckMemory(ptr);

    void *realP = ptr - prologueLength;
    void *newp = reallocf(realP, size + totalOverhead);
    if (newp == 0) {
        return newp;
    }
    WriteMetadata(newp, size);
    return newp + prologueLength;
}
DYLD_INTERPOSE(ITReallocf, reallocf);

// TODO: This might cause things to catch on fire. Maybe need an epilogue-only version for this? ugh
void *ITValloc(size_t size) {
    void *p = valloc(size + totalOverhead);
    if (p == 0) {
        return p;
    }
    WriteMetadata(p, size);
    return p + prologueLength;
}
DYLD_INTERPOSE(ITValloc, valloc);
