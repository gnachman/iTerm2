#import "SearchResult.h"

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
@end
