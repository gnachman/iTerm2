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
    if (@available(macOS 10.16, *)) {
        NSRect frame = _label.frame;
        frame.origin.y += 4;
        frame.size.width -=6;
        _label.frame = frame;
        _label.font = [NSFont titleBarFontOfSize:[NSFont systemFontSize]];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)setOrdinal:(int)ordinal {
    _ordinal = ordinal;
    [self updateLabel];
}

- (void)viewDidLayout {
    if (@available(macOS 10.16, *)) {
        // Big sur likes to change the height of this accessory view when the tab bar
        // is added or removed from being an accessory view. Luckily there's enough
        // wiggle room to keep it aligned.
        const CGFloat containerHeight = self.view.frame.size.height;
        NSRect frame = _label.frame;
        frame.origin.y = containerHeight - 21;
        _label.frame = frame;
    }
}
- (void)updateLabel {
    [self view];  // Ensure the label exists.
    BOOL deemphasized;
    NSString *string = [self.class stringForOrdinal:_ordinal deemphasized:&deemphasized];
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

+ (NSString *)stringForOrdinal:(int)ordinal deemphasized:(out BOOL *)deemphasized {
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

        case kPreferencesModifierTagEitherCommand:
            return [NSString stringForModifiersWithMask:NSEventModifierFlagCommand];

        case kPreferencesModifierTagEitherOption:
            return [NSString stringForModifiersWithMask:NSEventModifierFlagOption];

        case kPreferencesModifierTagCommandAndOption:
            return [NSString stringForModifiersWithMask:(NSEventModifierFlagCommand | NSEventModifierFlagOption)];

        case kPreferencesModifierTagControl:
            return [NSString stringForModifiersWithMask:NSEventModifierFlagControl];
    }

    return @"";
}

- (void)setIsMain:(BOOL)value {
    _isMain = value;
    [self updateTextColor];
}

- (void)updateTextColor {
    NSString *closest = [_label.effectiveAppearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameDarkAqua, NSAppearanceNameAqua]];
    _label.textColor = [NSColor windowFrameTextColor];
    if ([closest isEqualToString:NSAppearanceNameDarkAqua]) {
        self.view.alphaValue = 0.5;
    } else {
        self.view.alphaValue = 1.0;
    }
}

- (void)modifiersDidChange:(NSNotification *)notification {
    [self updateLabel];
}

@end
