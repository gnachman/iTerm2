//
//  AtomicHelpers.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/28/24.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// This exists because Swift Atomics do not.
typedef struct iTermAtomicInt64 iTermAtomicInt64;

iTermAtomicInt64 *iTermAtomicInt64Create(void);
void iTermAtomicInt64Free(iTermAtomicInt64 *i);

// Perform bitwise OR operation atomically
long long iTermAtomicInt64BitwiseOr(iTermAtomicInt64 *i, long long value);

// Assign zero and return the new value.
long long iTermAtomicInt64GetAndReset(iTermAtomicInt64 *i);

// Add value and return the new value.
long long iTermAtomicInt64Add(iTermAtomicInt64 *i, long long value);

// Returns the current value
long long iTermAtomicInt64Get(iTermAtomicInt64 *i);

// Assigns value.
void iTermAtomicInt64Set(iTermAtomicInt64 *i, long long value);

// If the value is expected, assigns desired and returns YES. Otherwise returns NO.
BOOL iTermAtomicInt64CompareAndSwap(iTermAtomicInt64 *i, long long expected, long long desired);

typedef struct iTermAtomicUInt64 iTermAtomicUInt64;

iTermAtomicUInt64 *iTermAtomicUInt64Create(void);
void iTermAtomicUInt64Free(iTermAtomicUInt64 *i);

// Add value and return the new value.
unsigned long long iTermAtomicUInt64Add(iTermAtomicUInt64 *i, unsigned long long value);

// Subtract value and return the value from before, so a caller can tell whether it underflowed.
unsigned long long iTermAtomicUInt64Subtract(iTermAtomicUInt64 *i, unsigned long long value);

// Returns the current value.
unsigned long long iTermAtomicUInt64Get(iTermAtomicUInt64 *i);

NS_ASSUME_NONNULL_END
