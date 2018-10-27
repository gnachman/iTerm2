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
    BOOL deemphasized;
    NSString *string = [self.class stringForOrdinal:_ordinal deempahsized:&deemphasized];
    if (!deemphasized) {
        _label.stringValue = string;
    } else {
        NSMutableParagraphStyle *paragraphStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
        paragraphStyle.alignment = NSTextAlignmentRight;
        NSDictionary *attributes = @{ NSFontAttributeName: _label.font,
                                      NSForegroundColorAttributeName: [NSColor lightGrayColor],
                                      NSParagraphStyleAttributeName: paragraphStyle };
        _label.attributedStringValue = [[[NSAttributedString alloc] initWithString:string
                                                                        attributes:attributes] autorelease];
    }
}

+ (NSString *)stringForOrdinal:(int)ordinal deempahsized:(out BOOL *)deemphasized {
    NSString *mods = [self.class modifiersString];
    if (ordinal == 0) {
        *deemphasized = NO;
        return @"";
    } else if (ordinal >= 10 || !mods) {
        *deemphasized = YES;
        return [@(ordinal) stringValue];
    } else {
        *deemphasized = NO;
        return [NSString stringWithFormat:@"%@%d", mods, ordinal];
    }
}

+ (NSString *)modifiersString {
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
    if (@available(macOS 10.14, *)) {
        if (_isMain) {
            _label.textColor = [_label.textColor colorWithAlphaComponent:0.5];
        } else {
            _label.textColor = [_label.textColor colorWithAlphaComponent:0.3];
        }
        return;
    }
    _label.textColor = _isMain ? [NSColor windowFrameTextColor] : [NSColor colorWithWhite:0.67 alpha:1];
}

- (void)modifiersDidChange:(NSNotification *)notification {
    [self updateLabel];
}

@end
