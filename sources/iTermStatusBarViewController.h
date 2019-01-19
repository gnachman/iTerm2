//
//  iTermStatusBarViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/28/18.
//

#import <Cocoa/Cocoa.h>
#import "iTermFindViewController.h"
#import "iTermStatusBarComponent.h"
#import "iTermStatusBarLayoutAlgorithm.h"

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat iTermStatusBarHeight;

@class iTermStatusBarLayout;
@class iTermStatusBarViewController;
@class iTermVariableScope;

@protocol iTermStatusBarViewControllerDelegate<NSObject>
- (NSColor *)statusBarDefaultTextColor;
- (NSColor *)statusBarSeparatorColor;
- (NSColor *)statusBarBackgroundColor;
- (NSColor *)statusBarTerminalBackgroundColor;
- (NSFont *)statusBarTerminalFont;
- (void)statusBarWriteString:(NSString *)string;
- (void)statusBarDidUpdate;
@end

@protocol iTermStatusBarContainer<NSObject>
@property (nullable, nonatomic, strong) iTermStatusBarViewController *statusBarViewController;
@end

@interface iTermStatusBarViewController : NSViewController

@property (nonatomic, readonly) iTermStatusBarLayout *layout;
@property (nonatomic, readonly) iTermVariableScope *scope;
@property (nonatomic, readonly) NSViewController<iTermFindViewController> *searchViewController;
@property (nullable, nonatomic, strong) id<iTermStatusBarComponent> temporaryLeftComponent;
@property (nullable, nonatomic, strong) id<iTermStatusBarComponent> temporaryRightComponent;
@property (nonatomic, weak) id<iTermStatusBarViewControllerDelegate> delegate;

- (instancetype)initWithLayout:(iTermStatusBarLayout *)layout
                         scope:(iTermVariableScope *)scope NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

- (void)updateColors;
- (nullable id<iTermStatusBarComponent>)componentWithIdentifier:(NSString *)identifier;

@end

NS_ASSUME_NONNULL_END
