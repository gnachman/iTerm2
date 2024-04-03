//
//  LineBufferHelpers.m
//  iTerm
//
//  Created by George Nachman on 11/21/13.
//
//

#import "LineBufferHelpers.h"
#import "NSObject+iTerm.h"

@implementation ResultRange

- (instancetype)initWithPosition:(int)position length:(int)length {
    self = [super init];
    if (self) {
        self->position = position;
        self->length = length;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p [%@...%@]>", NSStringFromClass(self.class), self, @(position), @(position + length - 1)];
}

- (BOOL)isEqual:(id)object {
    ResultRange *other = [ResultRange castFrom:object];
    if (!other) {
        return NO;
    }
    return position == other->position && length == other->length;
}

- (int)position {
    return position;
}

- (int)length {
    return length;
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

- (NSString *)description {
    return VT100GridCoordRangeDescription(self.coordRange);
}

@end

