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

@interface iTermStatusBarContainerView : NSView

@property (nonatomic, readonly) id<iTermStatusBarComponent> component;
@property (nonatomic) CGFloat desiredWidth;
@property (nonatomic) CGFloat desiredOrigin;
@property (nonatomic) CGFloat leftMargin;
@property (nonatomic) CGFloat rightMargin;
@property (nonatomic) BOOL componentHidden;

@property (nonatomic, readonly) NSColor *backgroundColor;
@property (nonatomic) CGFloat leftSeparatorOffset;
@property (nonatomic) CGFloat rightSeparatorOffset;
@property (nonatomic, strong, readonly) NSImageView *iconImageView;

- (nullable instancetype)initWithComponent:(id<iTermStatusBarComponent>)component NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithFrame:(NSRect)frame NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)decoder NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (void)layoutSubviews;

@end

NS_ASSUME_NONNULL_END
