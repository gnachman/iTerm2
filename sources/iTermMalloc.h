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

NS_ASSUME_NONNULL_END
