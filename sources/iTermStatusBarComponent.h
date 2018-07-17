//
//  iTermStatusBarComponent.h
//  iTerm2
//
//  Created by George Nachman on 6/29/18.
//

#import <Cocoa/Cocoa.h>

#import "iTermFindViewController.h"
#import "iTermStatusBarComponentKnob.h"


typedef NSString *iTermStatusBarComponentConfigurationKey NS_EXTENSIBLE_STRING_ENUM;
extern iTermStatusBarComponentConfigurationKey iTermStatusBarComponentConfigurationKeyKnobValues;  // NSDictionary

// Knob key
static NSString *const iTermStatusBarSharedBackgroundColorKey = @"shared background color";

@protocol iTermStatusBarComponent;
@class iTermVariableScope;

@protocol iTermStatusBarComponentDelegate<NSObject>
- (void)statusBarComponentKnobsDidChange:(id<iTermStatusBarComponent>)component;
- (BOOL)statusBarComponentIsInSetupUI:(id<iTermStatusBarComponent>)component;
- (void)statusBarComponentPreferredSizeDidChange:(id<iTermStatusBarComponent>)component;
@end

@protocol iTermStatusBarComponentFactory<NSCoding, NSCopying, NSObject>

- (id<iTermStatusBarComponent>)newComponentWithKnobs:(NSDictionary *)knobs;
- (NSString *)componentDescription;
- (NSDictionary *)defaultKnobs;

@end

// The model for a object in a status bar.
@protocol iTermStatusBarComponent<NSSecureCoding, NSObject>

@property (nonatomic, readonly) NSDictionary<iTermStatusBarComponentConfigurationKey, id> *configuration;
@property (nonatomic, weak) id<iTermStatusBarComponentDelegate> delegate;
@property (nonatomic, readonly) id<iTermStatusBarComponentFactory> statusBarComponentFactory;

+ (NSDictionary *)statusBarComponentDefaultKnobs;

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration;

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs;

// NSString or NSAttributedString
- (NSString *)statusBarComponentShortDescription;
- (NSString *)statusBarComponentDetailedDescription;

// Value to show in setup UI
- (id)statusBarComponentExemplar;

// Returns a newly created view showing this component's content.
- (NSView *)statusBarComponentCreateView;

// Update the view's size.
- (void)statusBarComponentSizeView:(NSView *)view toFitWidth:(CGFloat)width;

// Returns the minimum width in points of this component.
- (CGFloat)statusBarComponentMinimumWidth;

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

// Decides which components are removed first when space lacks.
- (double)statusBarComponentPriority;

// Which variables (in the session context) this component's contents depend on.
- (NSSet<NSString *> *)statusBarComponentVariableDependencies;

// The time interval between updates. Use distantFuture if you don't need updates.
- (NSTimeInterval)statusBarComponentUpdateCadence;

// Should update the contents of the component.
- (void)statusBarComponentUpdate;

// Called when depended-upon variables changed.
- (void)statusBarComponentVariablesDidChange:(NSSet<NSString *> *)variables;

// Sets the scope for variable evaluations.
- (void)statusBarComponentSetVariableScope:(iTermVariableScope *)scope;

// Updates knob values
- (void)statusBarComponentSetKnobValues:(NSDictionary *)knobValues;

// If this component serves as a search view, returns the view controller. Otherwise, returns nil.
- (NSViewController<iTermFindViewController> *)statusBarComponentSearchViewController;

// Called when the view size changes.
- (void)statusBarComponentWidthDidChangeTo:(CGFloat)newWidth;

// Does the view have margins between it and adjacent views
- (BOOL)statusBarComponentHasMargins;

// Vertical offset for components that don't center propertly
- (CGFloat)statusBarComponentVerticalOffset;

@end
