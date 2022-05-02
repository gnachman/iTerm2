//
//  LineBufferHelpers.m
//  iTerm
//
//  Created by George Nachman on 11/21/13.
//
//

#import "LineBufferHelpers.h"

@implementation ResultRange

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p [%@...%@]>", NSStringFromClass(self.class), self, @(position), @(position + length - 1)];
}

@end

@implementation XYRange

- (int)xStart {
    return xStart;
}

- (int)yStart {
    return yStart;

}
- (int)xEnd {
    return xEnd;

}
- (int)yEnd {
    return yEnd;
}

- (VT100GridCoordRange)coordRange {
    return VT100GridCoordRangeMake(xStart, yStart, xEnd, yEnd);
}

@end

