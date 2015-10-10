#import <Cocoa/Cocoa.h>

// Represents a search result when searching the screen and scrollback history
// contents.
@interface SearchResult : NSObject
{
@public
    // TODO(georgen): Use properties.
    int startX, endX;
    long long absStartY, absEndY;
}

+ (instancetype)searchResultFromX:(int)x y:(long long)y toX:(int)endX y:(long long)endY;
- (BOOL)isEqualToSearchResult:(SearchResult *)other;

@end


