//
//  iTermSearchFieldCell.h
//  iTerm2SharedARC
//
//  Created by GEORGE NACHMAN on 7/4/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    NSInteger currentIndex;
    NSInteger numberOfResults;
} iTermSearchFieldCounts;

@class iTermSearchFieldCell;

@protocol iTermSearchFieldControl<NSObject>
- (BOOL)searchFieldControlHasCounts:(iTermSearchFieldCell * _Nullable)cell;
- (iTermSearchFieldCounts)searchFieldControlGetCounts:(iTermSearchFieldCell * _Nullable)cell;
@end

@interface iTermSearchFieldCell : NSSearchFieldCell
@property(nonatomic, assign) CGFloat fraction;
@property(nonatomic, readonly) BOOL needsAnimation;
@property(nonatomic, assign) CGFloat alphaMultiplier;

- (void)willAnimate;

@end

@interface iTermMinimalSearchFieldCell : iTermSearchFieldCell
@end

@interface iTermMinimalFilterFieldCell : iTermSearchFieldCell
@end

@interface iTermMiniSearchFieldCell : iTermSearchFieldCell
@property(nonatomic, strong, nullable) NSColor *loupeColor;
@end

NS_ASSUME_NONNULL_END
