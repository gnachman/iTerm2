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

- (int)upperBound {
    return position + length;
}

- (id)mutableCopy {
    return [[MutableResultRange alloc]initWithPosition:position length:length];
}

@end

@implementation MutableResultRange

@dynamic position;
@dynamic length;

- (void)setPosition:(int)position {
    self->position = position;
}

- (void)setLength:(int)length {
    self->length = length;
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

@implementation LineBlockMultiLineSearchState

+ (instancetype)initialState {
    return [[self alloc] init];
}

+ (instancetype)stateWithResult:(MutableResultRange *)result {
    LineBlockMultiLineSearchState *state = [[self alloc] init];
    state.result = result;
    state.needsContinuation = NO;
    return state;
}

+ (instancetype)stateNeedingContinuationAtIndex:(NSInteger)index
                                  partialResult:(MutableResultRange *)partialResult {
    LineBlockMultiLineSearchState *state = [[self alloc] init];
    state.result = nil;
    state.needsContinuation = YES;
    state.queryLineIndex = index;
    state.partialResult = partialResult;
    return state;
}

- (NSString *)description {
    if (self.result) {
        return [NSString stringWithFormat:@"<%@: %p found=%@>", NSStringFromClass(self.class), self, self.result];
    } else if (self.needsContinuation) {
        return [NSString stringWithFormat:@"<%@: %p needsContinuation at index %@ partial=%@>",
                NSStringFromClass(self.class), self, @(self.queryLineIndex), self.partialResult];
    } else {
        return [NSString stringWithFormat:@"<%@: %p notFound>", NSStringFromClass(self.class), self];
    }
}

@end

