#import <Cocoa/Cocoa.h>
#import "VT100GridTypes.h"

// Represents a search result when searching the screen and scrollback history
// contents.
@interface SearchResult : NSObject

@property(nonatomic, assign) int startX;
@property(nonatomic, assign) int endX;  // inclusive
@property(nonatomic, assign) long long absStartY;
@property(nonatomic, assign) long long absEndY;

@property (nonatomic, readonly) VT100GridAbsCoordRange absCoordRange;

+ (instancetype)searchResultFromX:(int)x y:(long long)y toX:(int)endX y:(long long)endY;
- (BOOL)isEqualToSearchResult:(SearchResult *)other;
- (NSComparisonResult)compare:(SearchResult *)other;

@end


