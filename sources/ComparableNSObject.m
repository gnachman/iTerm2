//
//  ComparableNSObject.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/24/24.
//

#import "ComparableNSObject.h"

@implementation ComparableNSObject

- (NSComparisonResult)compare:(id)other {
    [self doesNotRecognizeSelector:_cmd];
    return NSOrderedSame;
}

@end
