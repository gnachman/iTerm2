//
//  OCHamcrest - HCMatcher.h
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCSelfDescribing.h"


/**
    A matcher over acceptable values.

    A matcher is able to describe itself to give feedback when it fails.

    HCMatcher implementations should @b not directly implement this protocol.
    Instead, @b extend the HCBaseMatcher class, which will ensure that the HCMatcher API can grow
    to support new features and remain compatible with all HCMatcher implementations.

    @ingroup core
 */
@protocol HCMatcher <HCSelfDescribing>

/**
    Evaluates the matcher for argument @a item.

    @param item  The object against which the matcher is evaluated.
    @return @c YES if @a item matches, otherwise @c NO.
 */
- (BOOL)matches:(id)item;

/**
    Evaluates the matcher for argument @a item.

    @param item                 The object against which the matcher is evaluated.
    @param mismatchDescription  The description to be built or appended to if @a item does not match.
    @return @c YES if @a item matches, otherwise @c NO.
 */
- (BOOL)matches:(id)item describingMismatchTo:(id<HCDescription>)mismatchDescription;

/**
    Generates a description of why the matcher has not accepted the item.

    The description will be part of a larger description of why a matching failed, so it should be
    concise.

    This method assumes that @c matches:item is false, but will not check this.

    @param item                 The item that the HCMatcher has rejected.
    @param mismatchDescription  The description to be built or appended to.
 */
- (void)describeMismatchOf:(id)item to:(id<HCDescription>)mismatchDescription;

@end
