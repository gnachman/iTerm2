#import "SearchResult.h"

@implementation SearchResult

+ (SearchResult *)searchResultFromX:(int)x y:(long long)y toX:(int)endX y:(long long)endY {
    SearchResult *result = [[[SearchResult alloc] init] autorelease];
    result->startX = x;
    result->endX = endX;
    result->absStartY = y;
    result->absEndY = endY;
    return result;
}

- (BOOL)isEqualToSearchResult:(SearchResult *)other {
    return startX == other->startX && endX == other->endX && absStartY == other->absStartY && absEndY == other->absEndY;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p %d,%lld to %d,%lld>",
            [self class], self, startX, absStartY, endX, absEndY];
}
@end
