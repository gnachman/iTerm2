#import <Cocoa/Cocoa.h>

// Represents a search result when searching the screen and scrollback history
// contents.
@interface SearchResult : NSObject

@property(nonatomic, assign) int startX;
@property(nonatomic, assign) int endX;
@property(nonatomic, assign) long long absStartY;
@property(nonatomic, assign) long long absEndY;

+ (instancetype)searchResultFromX:(int)x y:(long long)y toX:(int)endX y:(long long)endY;
- (BOOL)isEqualToSearchResult:(SearchResult *)other;

@end


