//
//  iTermMalloc.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/28/19.
//

#import "iTermMalloc.h"
#import "DebugLogging.h"

NS_ASSUME_NONNULL_BEGIN

void *iTermMalloc(NSInteger size)
{
    ITAssertWithMessage(size >= 0, @"Malloc(%@)", @(size));
    errno = 0;
    // Don't allow to malloc(0) because that can return NULL and I want this function to be nonnull.
    void *result = malloc(MAX(1, size));
    ITAssertWithMessage(result != NULL, @"malloc(%@) returned NULL with errno=%@", @(size), @(errno));
    return result;
}

NS_ASSUME_NONNULL_END
