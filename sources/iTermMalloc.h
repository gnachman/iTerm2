//
//  iTermMalloc.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/28/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Allocate memory. `size` must not be negative. Will never return NULL. Dies if size is negative
// or malloc returns NULL. Use `free` to dispose of this pointer.
void *iTermMalloc(NSInteger size);
void *iTermCalloc(NSInteger count, size_t unitSize);

// Use this sparingly.
void *iTermUninitializedCalloc(NSInteger count, size_t unitSize);

// Like realloc, but will never return NULL. Dies if the size is negative or realloc() returns NULL.
// Stubbornly refuses to allow signed integers to overflow. Use `free` to dispose of this pointer.
void *iTermRealloc(void *p, NSInteger count, size_t size);

// Prefer this. It zeros out newly allocated memory.
void *iTermZeroingRealloc(void *p, NSInteger formerCount, NSInteger count, size_t size);

// Copy a chunk of data into a newly malloced region.
void *iTermMemdup(const void *data, size_t count, size_t size);

// Safely divide a double by a double and convert to NSInteger.
// Sets *ok to NO if the division would result in NaN, infinity,
// or overflow when converting to NSInteger. Otherwise sets *ok to YES.
// If ok is NULL, it will be ignored.
NSInteger iTermSafeDivisionToInteger(double dividend, double divisor, BOOL *ok);

NS_ASSUME_NONNULL_END
