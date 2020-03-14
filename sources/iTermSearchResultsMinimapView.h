//
//  iTermSearchResultsMinimapView.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/14/20.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermSearchResultsMinimapView;

NS_CLASS_AVAILABLE_MAC(10_14)
@protocol iTermSearchResultsMinimapViewDelegate<NSObject>
- (NSIndexSet *)searchResultsMinimapViewLocations:(iTermSearchResultsMinimapView *)view;
- (NSRange)searchResultsMinimapViewRangeOfVisibleLines:(iTermSearchResultsMinimapView *)view;
@end

NS_CLASS_AVAILABLE_MAC(10_14)
@interface iTermSearchResultsMinimapView : NSView
@property (nonatomic, weak) id<iTermSearchResultsMinimapViewDelegate> delegate;

- (void)invalidate;
@end

NS_ASSUME_NONNULL_END
