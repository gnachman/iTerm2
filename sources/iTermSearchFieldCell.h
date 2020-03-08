//
//  iTermSearchFieldCell.h
//  iTerm2SharedARC
//
//  Created by GEORGE NACHMAN on 7/4/18.
//

#import <Cocoa/Cocoa.h>

typedef struct {
    NSInteger currentIndex;
    NSInteger numberOfResults;
} iTermSearchFieldCounts;

@class iTermSearchFieldCell;

@protocol iTermSearchFieldControl<NSObject>
- (BOOL)searchFieldControlHasCounts:(iTermSearchFieldCell *)cell;
- (iTermSearchFieldCounts)searchFieldControlGetCounts:(iTermSearchFieldCell *)cell;
@end

@interface iTermSearchFieldCell : NSSearchFieldCell
@property(nonatomic, assign) CGFloat fraction;
@property(nonatomic, readonly) BOOL needsAnimation;
@property(nonatomic, assign) CGFloat alphaMultiplier;

- (void)willAnimate;

@end

@interface iTermMinimalSearchFieldCell : iTermSearchFieldCell
@end

@interface iTermMiniSearchFieldCell : iTermSearchFieldCell
@end

