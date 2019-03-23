//
//  iTermStatusBarActionComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/22/19.
//

#import "iTermStatusBarActionComponent.h"
#import "iTermActionsModel.h"
#import "NSDictionary+iTerm.h"

static NSString *const iTermStatusBarActionKey = @"action";

@implementation iTermStatusBarActionComponent {
    NSButton *_button;
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    iTermStatusBarComponentKnob *actionKnob =
    [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Action"
                                                      type:iTermStatusBarComponentKnobTypeAction
                                               placeholder:nil
                                              defaultValue:nil
                                                       key:iTermStatusBarActionKey];
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
    return @[ actionKnob, textColorKnob, backgroundColorKnob ];
}

- (NSDictionary *)actionDictionary {
    return self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues][iTermStatusBarActionKey];
}

- (iTermAction *)action {
    return [[iTermAction alloc] initWithDictionary:self.actionDictionary];
}

- (void)updateTitleInButton:(NSButton *)button {
    NSColor *textColor = self.textColor;
    if (textColor) {
        NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
        [style setAlignment:NSTextAlignmentCenter];
        NSDictionary *attributes = @{ NSForegroundColorAttributeName: textColor,
                                      NSParagraphStyleAttributeName: style };
        NSAttributedString *attrString = [[NSAttributedString alloc]initWithString:self.action.title
                                                                        attributes:attributes];
        [button setAttributedTitle:attrString];
    } else {
        button.title = self.action.title;
    }
}

- (NSButton *)newButton {
    NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
    button.controlSize = NSControlSizeRegular;

    [self updateTitleInButton:button];

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
    return [self.button fittingSize].width;
}

- (NSString *)statusBarComponentShortDescription {
    return @"Custom Action";
}

- (BOOL)statusBarComponentCanStretch {
    return NO;
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Adds a button that performs a user-configurable action, similar to a key binding.";
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    NSDictionary *dict = self.actionDictionary;
    if (dict.count) {
        return self.action.title;
    } else {
        return @"Custom Action";
    }
}

- (CGFloat)statusBarComponentVerticalOffset {
    return 0;
}

- (void)setDelegate:(id<iTermStatusBarComponentDelegate>)delegate {
    [super setDelegate:delegate];
    [self updateTitleInButton:self.button];
}

#pragma mark - iTermStatusBarComponent

- (NSView *)statusBarComponentView {
    NSButton *button = self.button;
    [self updateTitleInButton:button];
    return button;
}

#pragma mark - Actions

- (void)buttonPushed:(id)sender {
    if (self.actionDictionary) {
        [self.delegate statusBarComponentPerformAction:self.action];
    }
}

@end
