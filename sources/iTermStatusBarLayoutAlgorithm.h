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

typedef NS_ENUM(NSUInteger, iTermStatusBarLayoutAlgorithmSetting) {
    iTermStatusBarLayoutAlgorithmSettingStable = 0,
    iTermStatusBarLayoutAlgorithmSettingTightlyPacked
};

@interface iTermStatusBarLayoutAlgorithm : NSObject
@property (nonatomic, strong, readonly) iTermStatusBarContainerView *mandatoryView;

+ (instancetype)layoutAlgorithmWithContainerViews:(NSArray<iTermStatusBarContainerView *> *)containerViews
                                    mandatoryView:(iTermStatusBarContainerView *)mandatoryView
                                   statusBarWidth:(CGFloat)statusBarWidth
                                          setting:(iTermStatusBarLayoutAlgorithmSetting)setting;

// This is for subclasses, not clients.
- (instancetype)initWithContainerViews:(NSArray<iTermStatusBarContainerView *> *)containerViews
                         mandatoryView:(nonnull iTermStatusBarContainerView *)mandatoryView
                        statusBarWidth:(CGFloat)statusBarWidth NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSArray<iTermStatusBarContainerView *> *)visibleContainerViews;

@end

NS_ASSUME_NONNULL_END
