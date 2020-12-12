//
//  iTermStatusBarContainerView.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/28/18.
//

#import <Cocoa/Cocoa.h>

#import "iTermStatusBarLayout.h"

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat iTermStatusBarViewControllerIconWidth;

const CGFloat iTermGetStatusBarHeight(void);

@class iTermStatusBarContainerView;

@protocol iTermStatusBarContainerViewDelegate<NSObject>
- (void)statusBarContainerView:(iTermStatusBarContainerView *)sender configureComponent:(id<iTermStatusBarComponent>)component;
- (void)statusBarContainerView:(iTermStatusBarContainerView *)sender hideComponent:(id<iTermStatusBarComponent>)component;
- (void)statusBarContainerViewConfigureStatusBar:(iTermStatusBarContainerView *)sender;
- (void)statusBarContainerViewDisableStatusBar:(iTermStatusBarContainerView *)sender;
- (BOOL)statusBarContainerViewCanDragWindow:(iTermStatusBarContainerView *)sender;
@end

@interface iTermStatusBarContainerView : NSView

@property (nonatomic, weak) id<iTermStatusBarContainerViewDelegate> delegate;
@property (nonatomic, readonly) id<iTermStatusBarComponent> component;
@property (nonatomic) CGFloat desiredWidth;
@property (nonatomic) CGFloat desiredOrigin;
@property (nonatomic) CGFloat leftMargin;
@property (nonatomic) CGFloat rightMargin;
@property (nonatomic, readonly) CGFloat minimumWidthIncludingIcon;

@property (nonatomic, readonly) NSColor *backgroundColor;
@property (nonatomic) CGFloat leftSeparatorOffset;
@property (nonatomic) CGFloat rightSeparatorOffset;
@property (nullable, nonatomic, strong, readonly) NSImageView *iconImageView;
@property (nonatomic) NSInteger unreadCount;

- (nullable instancetype)initWithComponent:(id<iTermStatusBarComponent>)component NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithFrame:(NSRect)frame NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)decoder NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (void)layoutSubviews;

@end

NS_ASSUME_NONNULL_END
