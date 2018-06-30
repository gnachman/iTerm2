//
//  iTermStatusBarComponent.h
//  iTerm2
//
//  Created by George Nachman on 6/29/18.
//

#import <Cocoa/Cocoa.h>

#import "iTermStatusBarComponentKnob.h"

typedef NS_ENUM(NSUInteger, iTermStatusBarComponentJustification) {
    iTermStatusBarComponentJustificationLeft,
    iTermStatusBarComponentJustificationCenter,
    iTermStatusBarComponentJustificationRight
};

static double iTermStatusBarComponentPriorityLow = 0.25;
static double iTermStatusBarComponentPriorityMedium = 0.5;
static double iTermStatusBarComponentPriorityHigh = 0.75;
static double iTermStatusBarComponentPriorityMaximum = 1;

typedef NSString *iTermStatusBarComponentConfigurationKey NS_EXTENSIBLE_STRING_ENUM;
extern iTermStatusBarComponentConfigurationKey iTermStatusBarComponentConfigurationKeyPriority;  // NSNumber
extern iTermStatusBarComponentConfigurationKey iTermStatusBarComponentConfigurationKeyJustification;  // NSNumber with iTermStatusBarComponentJustification
extern iTermStatusBarComponentConfigurationKey iTermStatusBarComponentConfigurationKeyMinimumWidth;  // NSNumber
extern iTermStatusBarComponentConfigurationKey iTermStatusBarComponentConfigurationKeyKnobValues;  // NSDictionary

@class iTermVariableScope;

@protocol iTermStatusBarComponent<NSSecureCoding, NSObject>

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration;

+ (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs;

// NSString or NSAttributedString
+ (id)statusBarComponentExemplar;
+ (NSString *)statusBarComponentShortDescription;
+ (NSString *)statusBarComponentDetailedDescription;

// Returns a newly created view showing this component's content.
- (NSView *)statusBarComponentCreateView;

// Returns the minimum width in points of this component.
- (CGFloat)statusBarComponentMinimumWidth;

// If this returns YES the component's width may exceed its minimum width.
- (BOOL)statusBarComponentCanStretch;

// Comparison
- (BOOL)isEqualToComponent:(id<iTermStatusBarComponent>)component;

// Decides which components are removed first when space lacks.
- (double)statusBarComponentPriority;

// Where to arrange this component left-to-right.
- (iTermStatusBarComponentJustification)statusBarComponentJustification;

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

@end
