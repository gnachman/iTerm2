//
//  iTermStatusBarComponent.h
//  iTerm2
//
//  Created by George Nachman on 6/29/18.
//

#import <Cocoa/Cocoa.h>

#import "iTermActivityInfo.h"
#import "iTermFindViewController.h"
#import "iTermStatusBarComponentKnob.h"
#import "iTermStatusBarLayoutAlgorithm.h"

NS_ASSUME_NONNULL_BEGIN

@protocol ProcessInfoProvider;
@protocol iTermTriggersDataSource;

typedef NSString *iTermStatusBarComponentConfigurationKey NS_EXTENSIBLE_STRING_ENUM;
extern iTermStatusBarComponentConfigurationKey iTermStatusBarComponentConfigurationKeyKnobValues;  // NSDictionary
extern iTermStatusBarComponentConfigurationKey iTermStatusBarComponentConfigurationKeyLayoutAdvancedConfigurationDictionaryValue;  // NSDictionary

// Knob key
static NSString *const iTermStatusBarSharedBackgroundColorKey = @"shared background color";
static NSString *const iTermStatusBarSharedTextColorKey = @"shared text color";
static NSString *const iTermStatusBarSharedFontKey = @"shared font";

@class iTermAction;
@protocol iTermStatusBarComponent;
@class iTermVariableScope;

@protocol iTermStatusBarComponentDelegate<NSObject>
- (void)statusBarComponentKnobsDidChange:(id<iTermStatusBarComponent>)component
                             updatedKeys:(NSSet<NSString *> *)updatedKeys;
- (BOOL)statusBarComponentIsInSetupUI:(id<iTermStatusBarComponent>)component;
- (void)statusBarComponentPreferredSizeDidChange:(id<iTermStatusBarComponent>)component;
- (NSColor *)statusBarComponentDefaultTextColor;
- (BOOL)statusBarComponentIsVisible:(id<iTermStatusBarComponent>)component;
- (NSFont *)statusBarComponentTerminalFont:(id<iTermStatusBarComponent>)component;
- (BOOL)statusBarComponentTerminalBackgroundColorIsDark:(id<iTermStatusBarComponent>)component;
- (NSColor *)statusBarComponentEffectiveBackgroundColor:(id<iTermStatusBarComponent>)component;
- (void)statusBarComponent:(id<iTermStatusBarComponent>)component writeString:(NSString *)string;
- (void)statusBarComponentOpenStatusBarPreferences:(id<iTermStatusBarComponent>)component;
- (void)statusBarComponentPerformAction:(iTermAction *)action;
- (void)statusBarComponentEditActions:(id<iTermStatusBarComponent>)component;
- (void)statusBarComponentEditSnippets:(id<iTermStatusBarComponent>)component;
- (void)statusBarComponentResignFirstResponder:(id<iTermStatusBarComponent>)component;
- (void)statusBarComponent:(id<iTermStatusBarComponent>)component
      reportScriptingError:(NSError *)error
forInvocation:(NSString *)invocation
                    origin:(NSString *)origin;
- (void)statusBarComponentComposerRevealComposer:(id<iTermStatusBarComponent>)component;
- (iTermActivityInfo)statusBarComponentActivityInfo:(id<iTermStatusBarComponent>)component;
- (id<iTermTriggersDataSource>)statusBarComponentTriggersDataSource:(id<iTermStatusBarComponent>)component;
- (void)statusBarRemoveTemporaryComponent:(id<iTermStatusBarComponent>)component;
- (void)statusBarSetFilter:(NSString * _Nullable)query;
- (id<ProcessInfoProvider>)statusBarComponentProcessInfoProvider;
@end

@protocol iTermStatusBarComponentFactory<NSSecureCoding, NSCopying, NSObject>

- (id<iTermStatusBarComponent>)newComponentWithKnobs:(NSDictionary *)knobs
                                     layoutAlgorithm:(iTermStatusBarLayoutAlgorithmSetting)layoutAlgorithm
                                               scope:(nullable iTermVariableScope *)scope;
- (NSString *)componentDescription;
- (NSDictionary *)defaultKnobs;

@end

// The model for a object in a status bar.
@protocol iTermStatusBarComponent<NSSecureCoding, NSObject>

@property (nonatomic, readonly) NSDictionary<iTermStatusBarComponentConfigurationKey, id> *configuration;
@property (nullable, nonatomic, weak) id<iTermStatusBarComponentDelegate> delegate;
@property (nonatomic, readonly) id<iTermStatusBarComponentFactory> statusBarComponentFactory;
@property (nonatomic, readonly) NSString *statusBarComponentIdentifier;

+ (NSDictionary *)statusBarComponentDefaultKnobs;

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration
                                scope:(iTermVariableScope *)scope;

- (nullable NSImage *)statusBarComponentIcon;

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs;

// NSString or NSAttributedString
- (NSString *)statusBarComponentShortDescription;
- (NSString *)statusBarComponentDetailedDescription;
- (BOOL)statusBarComponentIsInternal;

// Value to show in setup UI
- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor;

// Returns a newly created view showing this component's content.
- (NSView *)statusBarComponentView;

// Update the view's size.
- (void)statusBarComponentSizeView:(NSView *)view toFitWidth:(CGFloat)width;

// Returns the minimum width in points of this component.
- (CGFloat)statusBarComponentMinimumWidth;
// Returns the maximum width in points of this component. If this is smaller than the minimum
// width, the minimum width supersedes it.
- (CGFloat)statusBarComponentMaximumWidth;

// Returns the largest useful width of this component.
- (CGFloat)statusBarComponentPreferredWidth;

// If this returns YES the component's width may exceed its minimum width.
// The spring constant determines how multiple stretching components compete
// for space.
- (BOOL)statusBarComponentCanStretch;

// How hard it pushes against its neighbors. Only applies to components that
// can stretch.
- (CGFloat)statusBarComponentSpringConstant;

// Comparison
- (BOOL)isEqualToComponent:(id<iTermStatusBarComponent>)component;

- (BOOL)isEqualToComponentIgnoringConfiguration:(id<iTermStatusBarComponent>)component;

// Decides which components are removed first when space lacks.
- (double)statusBarComponentPriority;

// The time interval between updates. Use distantFuture if you don't need updates.
- (NSTimeInterval)statusBarComponentUpdateCadence;

// Should update the contents of the component.
- (void)statusBarComponentUpdate;

// Updates knob values
- (void)statusBarComponentSetKnobValues:(NSDictionary *)knobValues;
- (NSDictionary *)statusBarComponentKnobValues;

// If this component serves as a search view, returns the view controller. Otherwise, returns nil.
- (nullable NSViewController<iTermFindViewController> *)statusBarComponentSearchViewController;
- (nullable NSViewController<iTermFilterViewController> *)statusBarComponentFilterViewController;

// Called when the view size changes.
- (void)statusBarComponentWidthDidChangeTo:(CGFloat)newWidth;

// Does the view have margins between it and adjacent views
- (BOOL)statusBarComponentHasMargins;

// Vertical offset for components that don't center properly
- (CGFloat)statusBarComponentVerticalOffset;

// Update colors if needed
- (void)statusBarDefaultTextColorDidChange;
- (void)statusBarTerminalBackgroundColorDidChange;

- (nullable NSColor *)statusBarTextColor;
- (nullable NSColor *)statusBarBackgroundColor;

- (void)statusBarComponentOpenPopoverWithHTML:(NSString *)html ofSize:(NSSize)size;

- (void)statusBarComponentDidMoveToWindow;

- (BOOL)statusBarComponentHandlesClicks;
- (BOOL)statusBarComponentHandlesMouseDown;
- (void)statusBarComponentDidClickWithView:(NSView *)view;
- (void)statusBarComponentMouseDownWithView:(NSView *)view;
- (BOOL)statusBarComponentIsEmpty;

@optional
- (NSFont *)font;

@end
NS_ASSUME_NONNULL_END
