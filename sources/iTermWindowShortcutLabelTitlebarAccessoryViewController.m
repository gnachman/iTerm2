//
//  iTermWindowShortcutLabelTitlebarAccessoryViewController.m
//  iTerm2
//
//  Created by George Nachman on 12/11/14.
//
//

#import "iTermWindowShortcutLabelTitlebarAccessoryViewController.h"
#import "iTermPreferences.h"
#import "NSStringITerm.h"
#import "PSMTabBarControl.h"

@implementation iTermWindowShortcutLabelTitlebarAccessoryViewController {
    IBOutlet NSTextField *_label;
}

- (void)awakeFromNib {
    self.layoutAttribute = NSLayoutAttributeRight;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(modifiersDidChange:)
                                                 name:kPSMModifierChangedNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)setOrdinal:(int)ordinal {
    _ordinal = ordinal;
    [self updateLabel];
}

- (void)updateLabel {
    [self view];  // Ensure the label exists.
    NSString *mods = [self modifiersString];
    if (_ordinal == 0 || !mods) {
        _label.stringValue = @"";
    } else if (_ordinal >= 10) {
        NSMutableParagraphStyle *paragraphStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
        paragraphStyle.alignment = NSTextAlignmentRight;
        NSDictionary *attributes = @{ NSFontAttributeName: _label.font,
                                      NSForegroundColorAttributeName: [NSColor lightGrayColor],
                                      NSParagraphStyleAttributeName: paragraphStyle };
        _label.attributedStringValue = [[[NSAttributedString alloc] initWithString:[@(_ordinal) stringValue]
                                                                        attributes:attributes] autorelease];
    } else {
        _label.stringValue = [NSString stringWithFormat:@"%@%d", mods, _ordinal];
    }
}

- (NSString *)modifiersString {
    switch ([iTermPreferences intForKey:kPreferenceKeySwitchWindowModifier]) {
        case kPreferenceModifierTagNone:
            return nil;
            break;

        case kPreferencesModifierTagEitherCommand:
            return [NSString stringForModifiersWithMask:NSEventModifierFlagCommand];
            break;

        case kPreferencesModifierTagEitherOption:
            return [NSString stringForModifiersWithMask:NSEventModifierFlagOption];
            break;

        case kPreferencesModifierTagCommandAndOption:
            return [NSString stringForModifiersWithMask:(NSEventModifierFlagCommand | NSEventModifierFlagOption)];
            break;
    }

    return @"";
}

- (void)setIsMain:(BOOL)value {
    _isMain = value;
    [self updateTextColor];
}

- (void)updateTextColor {
    _label.textColor = _isMain ? [NSColor windowFrameTextColor] : [NSColor colorWithWhite:0.67 alpha:1];
}

- (void)modifiersDidChange:(NSNotification *)notification {
    [self updateLabel];
}

@end
