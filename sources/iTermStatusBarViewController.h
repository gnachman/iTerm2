//
//  iTermStatusBarViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/28/18.
//

#import <Cocoa/Cocoa.h>
#import "iTermActivityInfo.h"
#import "iTermStatusBarContainerView.h"
#import "iTermFindViewController.h"
#import "iTermStatusBarComponent.h"
#import "iTermStatusBarLayoutAlgorithm.h"
#import "iTerm2SharedARC-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@protocol ProcessInfoProvider;
@class iTermAction;
@class iTermStatusBarLayout;
@class iTermStatusBarViewController;
@class iTermVariableScope;

@protocol iTermStatusBarViewControllerDelegate<NSObject>
- (NSColor *)statusBarDefaultTextColor;
- (nullable NSColor *)statusBarSeparatorColor;
- (NSColor *)statusBarBackgroundColor;
- (NSColor *)statusBarTerminalBackgroundColor;
- (NSFont *)statusBarTerminalFont;
- (void)statusBarWriteString:(NSString *)string;
- (void)statusBarDidUpdate;
- (void)statusBarSetLayout:(iTermStatusBarLayout *)layout;
- (void)statusBarOpenPreferencesToComponent:(nullable id<iTermStatusBarComponent>)component;
- (void)statusBarDisable;
- (void)statusBarPerformAction:(iTermAction *)action;
- (void)statusBarEditActions;
- (void)statusBarEditSnippets;
- (void)statusBarResignFirstResponder;
- (void)statusBarReportScriptingError:(NSError *)error
                        forInvocation:(NSString *)invocation
                               origin:(NSString *)origin;
- (id<iTermTriggersDataSource>)statusBarTriggersDataSource;

// Takes into account theme, dark/light mode (if relevant), and advanced config background color.
- (BOOL)statusBarHasDarkBackground;
- (BOOL)statusBarCanDragWindow;
- (BOOL)statusBarRevealComposer;
- (iTermActivityInfo)statusBarActivityInfo;
- (void)statusBarSetFilter:(NSString * _Nullable)query;
- (id<ProcessInfoProvider>)statusBarProcessInfoProvider;

@end

@protocol iTermStatusBarContainer<NSObject>
@property (nullable, nonatomic, strong) iTermStatusBarViewController *statusBarViewController;
@end

@interface iTermStatusBarViewController : NSViewController

@property (nonatomic, readonly) iTermStatusBarLayout *layout;
@property (nonatomic, readonly) iTermVariableScope *scope;
@property (nonatomic, readonly) NSViewController<iTermFindViewController> *searchViewController;
@property (nonatomic, readonly) NSViewController<iTermFilterViewController> *filterViewController;

@property (nullable, nonatomic, strong) id<iTermStatusBarComponent> temporaryLeftComponent;
@property (nullable, nonatomic, strong) id<iTermStatusBarComponent> temporaryRightComponent;
@property (nonatomic, weak) id<iTermStatusBarViewControllerDelegate> delegate;
@property (nonatomic) BOOL mustShowSearchComponent;
@property (nonatomic, readonly) NSArray<id<iTermStatusBarComponent>> *visibleComponents;

- (instancetype)initWithLayout:(iTermStatusBarLayout *)layout
                         scope:(iTermVariableScope *)scope NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

- (void)updateColors;
- (nullable id<iTermStatusBarComponent>)componentWithIdentifier:(NSString *)identifier;
- (nullable __kindof id<iTermStatusBarComponent>)visibleComponentWithIdentifier:(NSString *)identifier;

@end

NS_ASSUME_NONNULL_END
