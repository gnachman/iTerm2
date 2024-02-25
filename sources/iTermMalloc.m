//
//  iTermMalloc.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/28/19.
//

#import "iTermMalloc.h"
#import "DebugLogging.h"
#include <malloc/malloc.h>

NS_ASSUME_NONNULL_BEGIN

static size_t iTermSafeSignedNonnegativeMultiply(NSInteger count, size_t unitSize);

void *iTermMalloc(NSInteger size) {
    ITAssertWithMessage(size >= 0, @"Malloc(%@)", @(size));
    errno = 0;
    // Don't allow to malloc(0) because that can return NULL and I want this function to be nonnull.
    void *result = malloc(MAX(1, size));
    ITAssertWithMessage(result != NULL, @"malloc(%@) returned NULL with errno=%@", @(size), @(errno));
    return result;
}

void *iTermCalloc(NSInteger count, size_t unitSize) {
    ITAssertWithMessage(unitSize >= 0 && count >= 0, @"Calloc(%@,%@)", @(count), @(unitSize));
    const size_t size = iTermSafeSignedNonnegativeMultiply(count, unitSize);
    if (size == 0) {
        return iTermMalloc(0);
    }
    return calloc(count, unitSize);
}

void *iTermUninitializedCalloc(NSInteger count, size_t unitSize) {
    ITAssertWithMessage(unitSize >= 0 && count >= 0, @"Calloc(%@,%@)", @(count), @(unitSize));
    const size_t size = iTermSafeSignedNonnegativeMultiply(count, unitSize);
    if (size == 0) {
        return iTermMalloc(0);
    }
    malloc_zone_t *default_zone = malloc_default_zone();
    return malloc_zone_malloc(default_zone, size);
}

static size_t iTermSafeSignedNonnegativeMultiply(NSInteger count, size_t unitSize) {
    // Adapts the bigint answer here for all nonnegative values:
    // https://stackoverflow.com/questions/1815367/catch-and-compute-overflow-during-multiplication-of-two-large-integers
    ITAssertWithMessage(count >= 0 && unitSize >= 0, @"iTermSafeMultiply(%@, %@)", @(count), @(unitSize));
    __uint128_t bigProduct = (__uint128_t)count * (__uint128_t)unitSize;
    const int safe_bits = sizeof(size_t) * 8 - 1;
    ITAssertWithMessage((bigProduct >> safe_bits) == 0, @"Nonnegative signed multiply overflow %@ * %@", @(count), @(unitSize));
    const size_t size = bigProduct;
    ITAssertWithMessage(size >= 0, @"iTermSafeMultiply(%@, %@) => %@", @(count), @(unitSize), @(size));
    return size;
}

void *iTermRealloc(void *p, NSInteger count, size_t unitSize)
{
    const size_t size = iTermSafeSignedNonnegativeMultiply(count, unitSize);
    void *replacement = realloc(p, MAX(1, size));
    ITAssertWithMessage(replacement != NULL, @"realloc of %@ bytes returned NULL with errno=%@", @(size), @(errno));
    return replacement;
}

void *iTermMemdup(const void *data, size_t count, size_t size) {
    void *dest = iTermUninitializedCalloc(count, size);
    const size_t numBytes = count * size;
    memcpy(dest, data, numBytes);
    return dest;
}

NS_ASSUME_NONNULL_END
