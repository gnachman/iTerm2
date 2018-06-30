//
//  iTermStatusBarSwiftyStringComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/29/18.
//

#import "iTermStatusBarSwiftyStringComponent.h"

#import "iTermStatusBarComponentKnob.h"
#import "iTermVariables.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const iTermStatusBarSwiftyStringComponentExpressionKey = @"expression";

@implementation iTermStatusBarSwiftyStringComponent {
    iTermSwiftyString *_swiftyString;
}

+ (id)statusBarComponentExemplar {
    return @"\\(user.gitBranch)";
}

+ (NSString *)statusBarComponentShortDescription {
    return @"Interpolated String";
}

+ (NSString *)statusBarComponentDetailedDescription {
    return @"Shows the evaluation of a string with inline expressions which may include session "
           @"variables or the output of registered scripting functions";
}

+ (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    iTermStatusBarComponentKnob *expressionKnob =
        [[iTermStatusBarComponentKnobText alloc] initWithLabelText:@"Expression"
                                                              type:iTermStatusBarComponentKnobTypeText
                                                       placeholder:@"String with \\(expressions)"
                                                      defaultValue:nil
                                                               key:iTermStatusBarSwiftyStringComponentExpressionKey];
    iTermStatusBarComponentKnobMinimumWidth *widthKnob =
        [[iTermStatusBarComponentKnobMinimumWidth alloc] initWithLabelText:nil
                                                                      type:iTermStatusBarComponentKnobTypeDouble placeholder:nil
                                                              defaultValue:@200
                                                                       key:iTermStatusBarComponentKnobMinimumWidthKey];
    return @[ expressionKnob, widthKnob ];
}

- (nullable NSString *)stringValue {
    return _swiftyString.evaluatedString;
}

- (NSSet<NSString *> *)statusBarComponentVariableDependencies {
    return _swiftyString.dependencies;
}

- (void)statusBarComponentVariablesDidChange:(NSSet<NSString *> *)variables {
    [_swiftyString variablesDidChange:variables];
}

- (void)statusBarComponentSetVariableScope:(iTermVariableScope *)scope {
    [super statusBarComponentSetVariableScope:scope];
    NSDictionary<NSString *, id> *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    NSString *expression = knobValues[iTermStatusBarSwiftyStringComponentExpressionKey] ?: @"";
    __weak __typeof(self) weakSelf = self;
    _swiftyString = [[iTermSwiftyString alloc] initWithString:expression
                                                       source:^id _Nonnull(NSString * _Nonnull name) {
                                                           return [weakSelf.scope valueForVariableName:name] ?: @"";
                                                       }
                                                      mutates:[NSSet set]
                                                     observer:^(NSString * _Nonnull newValue) {
                                                         weakSelf.textField.stringValue = newValue;
                                                     }];
}

@end

NS_ASSUME_NONNULL_END
