#import <Cocoa/Cocoa.h>
#import "VT100GridTypes.h"

@class iTermExternalSearchResult;

// Represents a search result when searching the screen and scrollback history
// contents.
@interface SearchResult : NSObject

@property(nonatomic, readonly) BOOL isExternal;

// These apply if it is external.
@property(nonatomic, readonly) long long externalAbsY;
@property(nonatomic, readonly) int externalNumLines;
@property(nonatomic, readonly) long long externalIndex;
@property(nonatomic, readonly) iTermExternalSearchResult *externalResult;

// These apply if it is not external.
@property(nonatomic, assign) int internalStartX;
@property(nonatomic, assign) int internalEndX;  // inclusive
@property(nonatomic, assign) long long internalAbsStartY;
@property(nonatomic, assign) long long internalAbsEndY;

// These work regardless of type
@property(nonatomic, readonly) long long safeAbsStartY;
@property(nonatomic, readonly) long long safeAbsEndY;

@property (nonatomic, readonly) VT100GridAbsCoordRange internalAbsCoordRange;

+ (instancetype)searchResultFromX:(int)x y:(long long)y toX:(int)endX y:(long long)endY;
+ (instancetype)searchResultFromExternal:(iTermExternalSearchResult *)externalResult
                                   index:(long long)index;
+ (instancetype)withCoordRange:(VT100GridCoordRange)coordRange
                      overflow:(long long)overflow;

- (BOOL)isEqualToSearchResult:(SearchResult *)other;
- (NSComparisonResult)compare:(SearchResult *)other;

@end


