//
//  AtomicHelpers.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/28/24.
//

#import "AtomicHelpers.h"

#include <stdatomic.h>
#include <stdlib.h>

typedef struct iTermAtomicInt64 {
    atomic_llong value;
} iTermAtomicInt64;

iTermAtomicInt64 *iTermAtomicInt64Create(void) {
    iTermAtomicInt64 *ai = malloc(sizeof(iTermAtomicInt64));
    if (ai != NULL) {
        atomic_init(&ai->value, 0);
    }
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
