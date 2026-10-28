//
//  AtomicHelpers.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/28/24.
//

#import "AtomicHelpers.h"

#import "iTermMalloc.h"
#include <stdatomic.h>
#include <stdlib.h>

typedef struct iTermAtomicInt64 {
    atomic_llong value;
} iTermAtomicInt64;

iTermAtomicInt64 *iTermAtomicInt64Create(void) {
    iTermAtomicInt64 *ai = iTermMalloc(sizeof(iTermAtomicInt64));
    atomic_init(&ai->value, 0);
    return ai;
}

void iTermAtomicInt64Free(iTermAtomicInt64 *i) {
    if (i != NULL) {
        free(i);
    }
}

long long iTermAtomicInt64BitwiseOr(iTermAtomicInt64 *i, long long value) {
    return atomic_fetch_or(&i->value, value);
}

// Get the current value and reset it atomically
long long iTermAtomicInt64GetAndReset(iTermAtomicInt64 *i) {
    return atomic_exchange(&i->value, 0);
}

long long iTermAtomicInt64Add(iTermAtomicInt64 *i, long long value) {
    return atomic_fetch_add(&i->value, value) + value;
}

long long iTermAtomicInt64Get(iTermAtomicInt64 *i) {
    return atomic_load(&i->value);
}

void iTermAtomicInt64Set(iTermAtomicInt64 *i, long long value) {
    atomic_store(&i->value, value);
}

BOOL iTermAtomicInt64CompareAndSwap(iTermAtomicInt64 *i, long long expected, long long desired) {
    return atomic_compare_exchange_strong(&i->value, &expected, desired);
}

typedef struct iTermAtomicUInt64 {
    atomic_ullong value;
} iTermAtomicUInt64;

iTermAtomicUInt64 *iTermAtomicUInt64Create(void) {
    iTermAtomicUInt64 *ai = iTermMalloc(sizeof(iTermAtomicUInt64));
    atomic_init(&ai->value, 0);
    return ai;
}

void iTermAtomicUInt64Free(iTermAtomicUInt64 *i) {
    if (i != NULL) {
        free(i);
    }
}

unsigned long long iTermAtomicUInt64Add(iTermAtomicUInt64 *i, unsigned long long value) {
    return atomic_fetch_add(&i->value, value) + value;
}

unsigned long long iTermAtomicUInt64Subtract(iTermAtomicUInt64 *i, unsigned long long value) {
    return atomic_fetch_sub(&i->value, value);
}

unsigned long long iTermAtomicUInt64Get(iTermAtomicUInt64 *i) {
    return atomic_load(&i->value);
}
