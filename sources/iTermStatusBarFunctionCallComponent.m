//
//  iTermStatusBarFunctionCallComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/9/18.
//

#import "iTermStatusBarFunctionCallComponent.h"

#import "iTermScriptFunctionCall.h"
#import "iTermStatusBarSetupKnobsViewController.h"
#import "iTermVariableScope.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const iTermStatusBarFunctionInvocationKey = @"function invocation";
static NSString *const iTermStatusBarLabelKey = @"label";
static NSString *const iTermStatusBarTimeoutKey = @"timeout";

@implementation iTermStatusBarFunctionCallComponent {
    NSButton *_button;
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    iTermStatusBarComponentKnob *labelKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Label:"
                                                          type:iTermStatusBarComponentKnobTypeText
                                                   placeholder:@"Button Label"
                                                  defaultValue:nil
                                                           key:iTermStatusBarLabelKey];
    iTermStatusBarComponentKnob *invocationKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Function call:"
                                                          type:iTermStatusBarComponentKnobTypeInvocation
                                                   placeholder:@"foo(bar: \"baz\")"
                                                  defaultValue:nil
                                                           key:iTermStatusBarFunctionInvocationKey];
    iTermStatusBarComponentKnob *timeoutKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Timeout (seconds):"
                                                          type:iTermStatusBarComponentKnobTypeDouble
                                                   placeholder:nil
                                                  defaultValue:self.class.statusBarComponentDefaultKnobs[iTermStatusBarTimeoutKey]
                                                           key:iTermStatusBarTimeoutKey];
    iTermStatusBarComponentKnob *backgroundColorKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Background Color:"
                                                          type:iTermStatusBarComponentKnobTypeColor
                                                   placeholder:nil
                                                  defaultValue:nil
                                                           key:iTermStatusBarSharedBackgroundColorKey];
    iTermStatusBarComponentKnob *textColorKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Text Color:"
                                                          type:iTermStatusBarComponentKnobTypeColor
                                                   placeholder:nil
                                                  defaultValue:nil
                                                           key:iTermStatusBarSharedTextColorKey];

    return [@[ labelKnob, invocationKnob, timeoutKnob, backgroundColorKnob, textColorKnob ] arrayByAddingObjectsFromArray:[super statusBarComponentKnobs]];
}

+ (NSDictionary *)statusBarComponentDefaultKnobs {
    NSDictionary *fromSuper = [super statusBarComponentDefaultKnobs];
    return [fromSuper dictionaryByMergingDictionary:@{ iTermStatusBarTimeoutKey: @5 }];
}

- (NSAttributedString *)attributedString {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    [style setAlignment:NSTextAlignmentLeft];
    style.lineBreakMode = NSLineBreakByTruncatingTail;

    NSDictionary *attributes = @{ NSForegroundColorAttributeName: self.textColor ?: [NSNull null],
                                  NSParagraphStyleAttributeName: style };
    return [[NSAttributedString alloc] initWithString:self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues][iTermStatusBarLabelKey]
                                           attributes:[attributes dictionaryByRemovingNullValues]];
}

- (NSButton *)newButton {
    NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
    button.controlSize = NSControlSizeRegular;
    button.attributedTitle = self.attributedString;
    NSColor *color = self.backgroundColor;
    button.bezelColor = color;
    button.bordered = NO;
    [button setButtonType:NSButtonTypeMomentaryLight];
    button.bezelStyle = NSBezelStyleRounded;
    button.target = self;
    button.action = @selector(buttonPushed:);
    [button sizeToFit];
    return button;
}

- (NSColor *)backgroundColor {
    NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    return [knobValues[iTermStatusBarSharedBackgroundColorKey] colorValue] ?: [super statusBarBackgroundColor];
}

- (NSColor *)textColor {
    NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    return [knobValues[iTermStatusBarSharedTextColorKey] colorValue] ?: ([self defaultTextColor] ?: [self.delegate statusBarComponentDefaultTextColor]);
}

- (NSColor *)statusBarTextColor {
    return [self textColor];
}

- (NSColor *)statusBarBackgroundColor {
    return [self backgroundColor];
}

- (void)statusBarDefaultTextColorDidChange {
    _button.attributedTitle = self.attributedString;
}

- (void)statusBarTerminalBackgroundColorDidChange {
    NSColor *color = self.backgroundColor;
    _button.bezelColor = color;
}

- (NSButton *)button {
    if (!_button) {
        _button = [self newButton];
    }
    return _button;
}

- (CGFloat)statusBarComponentPreferredWidth {
    return _button.frame.size.width;
}

- (void)statusBarComponentSizeView:(NSView *)view toFitWidth:(CGFloat)width {
    [_button sizeToFit];
}

- (CGFloat)statusBarComponentMinimumWidth {
    return self.button.frame.size.width;
}

- (NSString *)statusBarComponentShortDescription {
    return @"Call Script Function";
}

- (BOOL)statusBarComponentCanStretch {
    return NO;
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Adds a button that invokes a script function with a user-provided invocation.";
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    NSString *label = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues][iTermStatusBarLabelKey];
    if (label.length) {
        return label;
    }
    return @"foo(bar: \"baz\")";
}

- (CGFloat)statusBarComponentVerticalOffset {
    return -1.5;
}

#pragma mark - iTermStatusBarComponent

- (NSView *)statusBarComponentView {
    return self.button;
}

#pragma mark - Actions

- (void)buttonPushed:(id)sender {
    NSString *invocation = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues][iTermStatusBarFunctionInvocationKey];
    double timeout = [self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues][iTermStatusBarTimeoutKey] doubleValue];
    __weak __typeof(self) weakSelf = self;
    [iTermScriptFunctionCall callFunction:invocation
                                  timeout:timeout
                                    scope:weakSelf.scope
                               retainSelf:YES
                               completion:^(id value, NSError *error, NSSet<NSString *> *dependencies) {}];
}

@end

NS_ASSUME_NONNULL_END
