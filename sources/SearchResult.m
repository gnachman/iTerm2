#import "SearchResult.h"
#import "VT100GridTypes.h"

@implementation SearchResult

+ (SearchResult *)searchResultFromX:(int)x y:(long long)y toX:(int)endX y:(long long)endY {
    SearchResult *result = [[[SearchResult alloc] init] autorelease];
    result.startX = x;
    result.endX = endX;
    result.absStartY = y;
    result.absEndY = endY;
    return result;
}

- (BOOL)isEqualToSearchResult:(SearchResult *)other {
    return (_startX == other.startX &&
            _endX == other.endX &&
            _absStartY == other.absStartY &&
            _absEndY == other.absEndY);
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p %d,%lld to %d,%lld>",
               [self class], self, _startX, _absStartY, _endX, _absEndY];
}

- (BOOL)isEqual:(id)object {
    if ([object isKindOfClass:[SearchResult class]]) {
        return [self isEqualToSearchResult:object];
    } else {
        return NO;
    }
}

- (NSUInteger)hash {
    return ((((((_startX * 33) ^ _endX) * 33) ^ _absStartY) * 33) ^ _absEndY);
}

- (NSComparisonResult)compare:(SearchResult *)other {
    if (!other) {
        return NSOrderedDescending;
    }
    return VT100GridAbsCoordOrder(VT100GridAbsCoordMake(_startX, _absStartY),
                                  VT100GridAbsCoordMake(other->_startX, other->_absStartY));
}

@end
