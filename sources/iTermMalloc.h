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

// Copy a chunk of data into a newly malloced region.
void *iTermMemdup(const void *data, size_t count, size_t size);

NS_ASSUME_NONNULL_END
