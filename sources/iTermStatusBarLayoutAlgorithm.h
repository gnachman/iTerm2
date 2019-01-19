//
//  iTermStatusBarLayoutAlgorithm.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/19/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat iTermStatusBarViewControllerMargin;

@class iTermStatusBarContainerView;

@interface iTermStatusBarLayoutAlgorithm : NSObject

- (instancetype)initWithContainerViews:(NSArray<iTermStatusBarContainerView *> *)containerViews
                        statusBarWidth:(CGFloat)statusBarWidth NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSArray<iTermStatusBarContainerView *> *)visibleContainerViews;

@end

NS_ASSUME_NONNULL_END
