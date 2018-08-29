//
//  iTermStatusBarSwiftyStringComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/29/18.
//

#import "iTermStatusBarSwiftyStringComponent.h"

#import "iTermStatusBarComponentKnob.h"
#import "iTermVariables.h"
#import "NSDictionary+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const iTermStatusBarSwiftyStringComponentExpressionKey = @"expression";

@implementation iTermStatusBarSwiftyStringComponent {
    iTermSwiftyString *_swiftyString;
    NSString *_value;
}

- (NSString *)statusBarComponentShortDescription {
    return @"Interpolated String";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Shows the evaluation of a string with inline expressions which may include session "
           @"variables or the output of registered scripting functions";
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    iTermStatusBarComponentKnob *expressionKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"String Value:"
                                                          type:iTermStatusBarComponentKnobTypeText
                                                   placeholder:@"String with \\(expressions)"
                                                  defaultValue:@""
                                                           key:iTermStatusBarSwiftyStringComponentExpressionKey];
    return [@[ expressionKnob ] arrayByAddingObjectsFromArray:[super statusBarComponentKnobs]];
}

+ (NSDictionary *)statusBarComponentDefaultKnobs {
    NSDictionary *fromSuper = [super statusBarComponentDefaultKnobs];
    return [fromSuper dictionaryByMergingDictionary:@{ iTermStatusBarSwiftyStringComponentExpressionKey: @"" }];
}

- (id)statusBarComponentExemplar {
    if (!_swiftyString.swiftyString.length) {
        return @"\\(expression)";
    } else {
        return _swiftyString.swiftyString;
    }
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

- (NSSet<NSString *> *)statusBarComponentVariableDependencies {
    return _swiftyString.dependencies;
}

- (void)statusBarComponentVariablesDidChange:(NSSet<NSString *> *)variables {
    [_swiftyString variablesDidChange:variables];
}

- (void)statusBarComponentSetVariableScope:(iTermVariableScope *)scope {
    [super statusBarComponentSetVariableScope:scope];
    [self updateWithKnobValues:self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues]];
}

- (void)setStringValue:(NSString *)value {
    _value = [value copy];
    [self updateTextFieldIfNeeded];
}

- (nullable NSArray<NSString *> *)stringVariants {
    return @[ _value ?: @"" ];
}

- (void)updateWithKnobValues:(NSDictionary<NSString *, id> *)knobValues {
    NSString *expression = knobValues[iTermStatusBarSwiftyStringComponentExpressionKey] ?: @"";
    __weak __typeof(self) weakSelf = self;
    if ([self.delegate statusBarComponentIsInSetupUI:self]) {
        _swiftyString = [[iTermSwiftyStringPlaceholder alloc] initWithString:expression];
        self.stringValue = expression;
    } else {
        _swiftyString = [[iTermSwiftyString alloc] initWithString:expression
                                                           source:^id _Nonnull(NSString * _Nonnull name) {
                                                               return [weakSelf.scope valueForVariableName:name] ?: @"";
                                                           }
                                                          mutates:[NSSet set]
                                                         observer:^(NSString * _Nonnull newValue) {
                                                             [weakSelf setStringValue:newValue];
                                                         }];
        self.stringValue = _swiftyString.evaluatedString;
    }
}

- (void)statusBarComponentSetKnobValues:(NSDictionary *)knobValues {
    [self updateWithKnobValues:knobValues];
    [super statusBarComponentSetKnobValues:knobValues];
}

@end

NS_ASSUME_NONNULL_END
