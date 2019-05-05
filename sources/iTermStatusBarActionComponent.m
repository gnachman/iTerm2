//
//  iTermStatusBarActionComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/22/19.
//

#import "iTermStatusBarActionComponent.h"
#import "iTermActionsModel.h"
#import "iTermScriptHistory.h"
#import "iTermSwiftyString.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"

static NSString *const iTermStatusBarActionKey = @"action";

@implementation iTermStatusBarActionComponent {
    NSButton *_button;
    iTermSwiftyString *_swiftyString;
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
    return [@[ actionKnob, textColorKnob, backgroundColorKnob ] arrayByAddingObjectsFromArray:[self minMaxWidthKnobs]];
}

- (NSDictionary *)actionDictionary {
    return self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues][iTermStatusBarActionKey];
}

- (iTermAction *)action {
    return [[iTermAction alloc] initWithDictionary:self.actionDictionary];
}

- (void)statusBarDefaultTextColorDidChange {
    [self swiftyStringDidChangeTo:_button.title];
}

- (void)statusBarTerminalBackgroundColorDidChange {
    NSColor *color = self.backgroundColor;
    _button.bezelColor = color;
}

- (void)updateTitleInButton {
    if (_swiftyString) {
        _swiftyString.swiftyString = self.action.title;
        return;
    }
    __weak __typeof(self) weakSelf = self;
    NSString *expression = self.action.title.copy ?: @"";
    _swiftyString = [[iTermSwiftyString alloc] initWithString:expression
                                                        scope:self.scope
                                                     observer:^(NSString * _Nonnull newValue, NSError *error) {
                                                         if (error != nil) {
                                                             [[iTermScriptHistoryEntry globalEntry] addOutput:[NSString stringWithFormat:@"Error while evaluating %@ in status bar action button: %@", expression, error]];
                                                             return [NSString stringWithFormat:@"🐞 %@", error.localizedDescription];
                                                         }
                                                         [weakSelf swiftyStringDidChangeTo:newValue];
                                                         return newValue;
                                                     }];
}

- (void)swiftyStringDidChangeTo:(NSString *)title {
    NSColor *textColor = self.textColor;
    if (textColor) {
        NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
        [style setAlignment:NSTextAlignmentLeft];
        style.lineBreakMode = NSLineBreakByTruncatingTail;
        NSDictionary *attributes = @{ NSForegroundColorAttributeName: textColor,
                                      NSParagraphStyleAttributeName: style };
        NSAttributedString *attrString = [[NSAttributedString alloc] initWithString:title
                                                                        attributes:attributes];
        [_button setAttributedTitle:attrString];
    } else {
        _button.title = title;
    }
    [self.delegate statusBarComponentPreferredSizeDidChange:self];
}

- (NSButton *)newButton {
    NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
    button.controlSize = NSControlSizeRegular;

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
        [self updateTitleInButton];
    }
    return _button;
}

- (CGFloat)statusBarComponentPreferredWidth {
    return [self clampedWidth:_button.fittingSize.width];
}

- (CGFloat)defaultMinimumWidth {
    return 30;
}

- (CGFloat)statusBarComponentMinimumWidth {
    return [self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues][iTermStatusBarMinimumWidthKey] doubleValue];
}

- (void)statusBarComponentSizeView:(NSView *)view toFitWidth:(CGFloat)width {
    const CGFloat preferredWidth = self.button.fittingSize.width;
    if (preferredWidth <= width) {
        [self.button sizeToFit];
        return;
    }
    NSRect frame = self.button.frame;
    frame.size.width = width;
    self.button.frame = frame;
}
- (NSString *)statusBarComponentShortDescription {
    return @"Custom Action";
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
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
    [self updateTitleInButton];
}

- (NSImage *)statusBarComponentIcon {
    return [NSImage it_imageNamed:@"StatusBarIconAction" forClass:[self class]];
}

- (NSView *)statusBarComponentView {
    NSButton *button = self.button;
    [self updateTitleInButton];
    return button;
}

#pragma mark - Actions

- (void)buttonPushed:(id)sender {
    if (self.actionDictionary) {
        [self.delegate statusBarComponentPerformAction:self.action];
    }
}

@end
