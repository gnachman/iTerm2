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

    // Clamp negative coordinates to valid values.
    if (result.start.y < 0) {
        result.start.y = 0;
        result.start.x = 0;
    }
    if (result.start.x < 0) {
        result.start.x = 0;
    }
    if (result.end.y < 0) {
        result.end.y = 0;
        result.end.x = 0;
    }
    if (result.end.x < 0) {
        result.end.x = 0;
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

    // Clamp negative coordinates to 0 to avoid creating intervals with negative bounds.
    if (absStart.x < 0) {
        absStart.x = 0;
    }
    if (absStart.y < 0) {
        absStart.y = 0;
        absStart.x = 0;
    }
    if (absEnd.x < 0) {
        absEnd.x = 0;
    }
    if (absEnd.y < 0) {
        absEnd.y = 0;
        absEnd.x = 0;
    }

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
