//
//  Interval+Additions.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/21/24.
//

#import "Interval+Additions.h"

@implementation Interval(Additions)

- (VT100GridAbsCoordRange)absCoordRangeForWidth:(int)width {
    VT100GridAbsCoordRange result;
    const int w = width + 1;
    result.start.y = self.location / w;
    result.start.x = self.location % w;
    result.end.y = self.limit / w;
    result.end.x = self.limit % w;

    if (result.start.y < 0) {
        result.start.y = 0;
        result.start.x = 0;
    }
    if (result.start.x == width) {
        result.start.y += 1;
        result.start.x = 0;
    }
    return result;
}

+ (instancetype)intervalForGridAbsCoordRange:(VT100GridAbsCoordRange)absRange
                                       width:(int)width {
    VT100GridAbsCoord absStart = absRange.start;
    VT100GridAbsCoord absEnd = absRange.end;
    long long si = absStart.y;
    si *= (width + 1);
    si += absStart.x;
    long long ei = absEnd.y;
    ei *= (width + 1);
    ei += absEnd.x;
    if (ei < si) {
        long long temp = ei;
        ei = si;
        si = temp;
    }
    return [Interval intervalWithLocation:si length:ei - si];
}

@end
