//
//  Interval+Additions.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/21/24.
//

#import <Foundation/Foundation.h>
#import "IntervalTree.h"
#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface Interval(Additions)

+ (instancetype)intervalForGridAbsCoordRange:(VT100GridAbsCoordRange)absRange
                                       width:(int)width;

- (VT100GridAbsCoordRange)absCoordRangeForWidth:(int)width;

@end

NS_ASSUME_NONNULL_END
