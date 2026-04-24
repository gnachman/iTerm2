//
//  iTermSquash.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/28/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Returns x modified so that the result is always between [-maxWiggle, upperBound+maxWiggle].
// x can be any finite value. It will be linear when x is in [0, upperBound].
CGFloat iTermSquash(CGFloat x, CGFloat upperBound, CGFloat maxWiggle);

NS_ASSUME_NONNULL_END
