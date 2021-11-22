//
//  ProfilesTextPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/15/14.
//
//

#import "ProfilesTextPreferencesViewController.h"

#import "DebugLogging.h"
#import "FutureMethods.h"
#import "ITAddressBookMgr.h"
#import "iTermFontPanel.h"
#import "iTermSizeRememberingView.h"
#import "iTermWarning.h"
#import "NSDictionary+iTerm.h"
#import "NSFont+iTerm.h"
#import "NSStringITerm.h"
#import "NSTextField+iTerm.h"
#import "PreferencePanel.h"
#import "PTYFontInfo.h"
#import <BetterFontPicker/BetterFontPicker-Swift.h>

@interface ProfilesTextPreferencesViewController ()<BFPCompositeViewDelegate, BFPSizePickerViewDelegate>
@property(nonatomic, strong) NSFont *normalFont;
@property(nonatomic, strong) NSFont *nonAsciiFont;
@end

@implementation ProfilesTextPreferencesViewController {
    // cursor type: underline/vertical bar/box
    // See ITermCursorType. One of: CURSOR_UNDERLINE, CURSOR_VERTICAL, CURSOR_BOX
    IBOutlet NSMatrix *_cursorType;
    IBOutlet NSTextField *_cursorTypeLabel;
    IBOutlet NSButton *_blinkingCursor;
    IBOutlet NSButton *_useBoldFont;
    IBOutlet NSButton *_blinkAllowed;
    IBOutlet NSButton *_shadow;
    IBOutlet NSButton *_useItalicFont;
    IBOutlet NSButton *_ambiguousIsDoubleWidth;
    IBOutlet NSPopUpButton *_normalization;
    IBOutlet NSTextField *_normalizationLabel;
    IBOutlet NSButton *_useNonAsciiFont;
    IBOutlet NSButton *_asciiAntiAliased;
    IBOutlet NSButton *_nonasciiAntiAliased;
    IBOutlet NSPopUpButton *_thinStrokes;
    IBOutlet NSTextField *_thinStrokesLabel;
    IBOutlet NSButton *_unicodeVersion9;
    IBOutlet NSButton *_asciiLigatures;
    IBOutlet NSButton *_nonAsciiLigatures;
    IBOutlet NSButton *_subpixelAA;
    IBOutlet NSButton *_powerline;
    IBOutlet BFPCompositeView *_asciiFontPicker;
    IBOutlet BFPCompositeView *_nonASCIIFontPicker;
    IBOutlet NSTextField *_ligatureWarning;
    BFPSizePickerView *_horizontalSpacingView;
    BFPSizePickerView *_verticalSpacingView;

    // Warning labels
    IBOutlet NSTextField *_normalFontWantsAntialiasing;
    IBOutlet NSTextField *_nonasciiFontWantsAntialiasing;

    // Hide this view to hide all non-ASCII font settings.
    IBOutlet NSView *_nonAsciiFontView;

    CGFloat _heightWithNonAsciiControls;
    CGFloat _heightWithoutNonAsciiControls;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)awakeFromNib {
    _heightWithNonAsciiControls = self.view.frame.size.height;
    _heightWithoutNonAsciiControls = _heightWithNonAsciiControls - _nonAsciiFontView.frame.size.height - _nonAsciiFontView.frame.origin.y;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProfiles)
                                                 name:kReloadAllProfiles
                                               object:nil];
    __weak __typeof(self) weakSelf = self;
    PreferenceInfo *info;
    info = [self defineControl:_cursorType
                    key:KEY_CURSOR_TYPE
            displayName:@"Cursor style"
                   type:kPreferenceInfoTypeMatrix
         settingChanged:^(id sender) { [self setInt:[[sender selectedCell] tag] forKey:KEY_CURSOR_TYPE]; }
                 update:^BOOL{
                     __strong __typeof(weakSelf) strongSelf = weakSelf;
                     if (!strongSelf) {
                         return NO;
                     }
                     [strongSelf->_cursorType selectCellWithTag:[self intForKey:KEY_CURSOR_TYPE]];
                     return YES;
                 }];
    info.observer = ^{
        [weakSelf updateShadowEnabled];
    };

    [self defineControl:_blinkingCursor
                    key:KEY_BLINKING_CURSOR
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_useBoldFont
                    key:KEY_USE_BOLD_FONT
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_thinStrokes
                    key:KEY_THIN_STROKES
            relatedView:_thinStrokesLabel
                   type:kPreferenceInfoTypePopup];

    [self defineControl:_blinkAllowed
                    key:KEY_BLINK_ALLOWED
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_shadow
                    key:KEY_CURSOR_SHADOW
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self updateShadowEnabled];

    [self defineControl:_useItalicFont
                    key:KEY_USE_ITALIC_FONT
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_asciiLigatures
                           key:KEY_ASCII_LIGATURES
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        [weakSelf updateLigatureWarning];
    };
    info = [self defineUnsearchableControl:_nonAsciiLigatures
                                       key:KEY_NON_ASCII_LIGATURES
                                      type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        [weakSelf updateLigatureWarning];
    };
    info = [self defineControl:_ambiguousIsDoubleWidth
                           key:KEY_AMBIGUOUS_DOUBLE_WIDTH
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.customSettingChangedHandler = ^(id sender) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        BOOL isOn = [sender state] == NSControlStateValueOn;
        if (isOn) {
            static NSString *const kWarnAboutAmbiguousWidth = @"NoSyncWarnAboutAmbiguousWidth";
            // This is a feature of dubious value inherited from iTerm 0.1. Some users who work in
            // mixed Asian/non-asian environments find it useful but almost nobody should turn it on
            // unless they really know what they're doing.
            iTermWarningSelection selection =
                [iTermWarning showWarningWithTitle:@"You probably don't want to turn this on. "
                                                   @"It will confuse interactive programs. "
                                                   @"You might want it if you work mostly with "
                                                   @"East Asian text combined with legacy or "
                                                   @"mathematical character sets. "
                                                   @"Are you sure you want this?"
                                           actions:@[ @"Enable", @"Cancel" ]
                                        identifier:kWarnAboutAmbiguousWidth
                                       silenceable:kiTermWarningTypePermanentlySilenceable
                                            window:weakSelf.view.window];
            if (selection == kiTermWarningSelection0) {
                [strongSelf setBool:YES forKey:KEY_AMBIGUOUS_DOUBLE_WIDTH];
            }
        } else {
            [strongSelf setBool:NO forKey:KEY_AMBIGUOUS_DOUBLE_WIDTH];
        }
    };

    [self defineControl:_normalization
                    key:KEY_UNICODE_NORMALIZATION
            relatedView:_normalizationLabel
                   type:kPreferenceInfoTypePopup];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(unicodeVersionDidChange)
                                                 name:iTermUnicodeVersionDidChangeNotification
                                               object:nil];
    [self defineControl:_unicodeVersion9
                    key:KEY_UNICODE_VERSION
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox
         settingChanged:^(id sender) {
             __strong __typeof(weakSelf) strongSelf = weakSelf;
             if (!strongSelf) {
                 return;
             }
             const NSInteger version = (strongSelf->_unicodeVersion9.state == NSControlStateValueOn) ? 9 : 8;
             [strongSelf setInteger:version forKey:KEY_UNICODE_VERSION];
         }
                 update:^BOOL{
                     __strong __typeof(weakSelf) strongSelf = weakSelf;
                     if (!strongSelf) {
                         return NO;
                     }
                     strongSelf->_unicodeVersion9.state = [strongSelf integerForKey:KEY_UNICODE_VERSION] == 9 ? NSControlStateValueOn : NSControlStateValueOff;
                     return YES;
                 }];

    if (@available(macOS 10.16, *)) {
        // 😢 See issue 9209
        _subpixelAA.hidden = YES;
    }

    _asciiFontPicker.delegate = self;
    _asciiFontPicker.mode = BFPCompositeViewModeFixedPitch;
    _nonASCIIFontPicker.delegate = self;
    _nonASCIIFontPicker.mode = BFPCompositeViewModeFixedPitch;
    _horizontalSpacingView = [_asciiFontPicker addHorizontalSpacingAccessoryWithInitialValue:[self doubleForKey:KEY_HORIZONTAL_SPACING] * 100];
    _horizontalSpacingView.delegate = self;
    [_horizontalSpacingView clampWithMin:50 max:200];
    _verticalSpacingView = [_asciiFontPicker addVerticalSpacingAccessoryWithInitialValue:[self doubleForKey:KEY_VERTICAL_SPACING] * 100];
    _verticalSpacingView.delegate = self;
    [_verticalSpacingView clampWithMin:50 max:200];
    [self defineControl:_asciiFontPicker.horizontalSpacing.textField
                    key:KEY_HORIZONTAL_SPACING
            relatedView:nil
            displayName:@"Horizontal spacing"
                   type:kPreferenceInfoTypeIntegerTextField
         settingChanged:^(id sender) { assert(false); }
                 update:^BOOL{
                     __strong __typeof(weakSelf) strongSelf = weakSelf;
                     if (!strongSelf) {
                         return NO;
                     }
                     strongSelf->_asciiFontPicker.horizontalSpacing.size = [self doubleForKey:KEY_HORIZONTAL_SPACING] * 100;
                     return YES;
                 }
             searchable:YES];

    [self defineControl:_asciiFontPicker.verticalSpacing.textField
                    key:KEY_VERTICAL_SPACING
            relatedView:nil
            displayName:@"Vertical spacing"
                   type:kPreferenceInfoTypeIntegerTextField
         settingChanged:^(id sender) { assert(false); }
                 update:^BOOL{
                     __strong __typeof(weakSelf) strongSelf = weakSelf;
                     if (!strongSelf) {
                         return NO;
                     }
                     strongSelf->_asciiFontPicker.verticalSpacing.size = [self doubleForKey:KEY_VERTICAL_SPACING] * 100;
                     return YES;
                 }
             searchable:YES];

    info = [self defineControl:_useNonAsciiFont
                           key:KEY_USE_NONASCII_FONT
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{ [weakSelf updateNonAsciiFontViewVisibility]; };

    info = [self defineControl:_asciiAntiAliased
                           key:KEY_ASCII_ANTI_ALIASED
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{ [weakSelf updateWarnings]; };

    info = [self defineUnsearchableControl:_nonasciiAntiAliased
                                       key:KEY_NONASCII_ANTI_ALIASED
                                      type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{ [weakSelf updateWarnings]; };

    [self defineControl:_powerline
                    key:KEY_POWERLINE
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self updateFontsDescriptionsIncludingSpacing:YES];
    [self updateNonAsciiFontViewVisibility];
    [self updateLigatureWarning];
}

- (void)updateLigatureWarning {
    _ligatureWarning.hidden = ![self shouldShowLigaturesWarning];
}

- (BOOL)shouldShowLigaturesWarning {
    if (self.normalFont.it_defaultLigatures) {
        return NO;
    }
    if (self.normalFont.it_ligatureLevel > 0 && [self boolForKey:KEY_ASCII_LIGATURES]) {
        return YES;
    }
    if (![self boolForKey:KEY_USE_NONASCII_FONT]) {
        return NO;
    }

    if (self.nonAsciiFont.it_defaultLigatures) {
        return NO;
    }
    if (self.nonAsciiFont.it_ligatureLevel > 0 && [self boolForKey:KEY_NON_ASCII_LIGATURES]) {
        return YES;
    }
    return NO;
}

- (void)unicodeVersionDidChange {
    [self infoForControl:_unicodeVersion9].onUpdate();
}

- (void)windowWillClose {
    [super windowWillClose];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reloadProfile {
    [super reloadProfile];
    [self updateFontsDescriptionsIncludingSpacing:YES];
    [self updateNonAsciiFontViewVisibility];
}

- (NSArray *)keysForBulkCopy {
    NSArray *keys = @[ KEY_NORMAL_FONT, KEY_NON_ASCII_FONT ];
    return [[super keysForBulkCopy] arrayByAddingObjectsFromArray:keys];
}

- (void)updateNonAsciiFontViewVisibility {
    _nonAsciiFontView.hidden = ![self boolForKey:KEY_USE_NONASCII_FONT];
    ((iTermSizeRememberingView *)self.view).originalSize = self.myPreferredContentSize;
    [self.delegate profilePreferencesContentViewSizeDidChange:(iTermSizeRememberingView *)self.view];
}

- (NSSize)myPreferredContentSize {
    if ([self boolForKey:KEY_USE_NONASCII_FONT]) {
        return NSMakeSize(((iTermSizeRememberingView *)self.view).originalSize.width, _heightWithNonAsciiControls);
    } else {
        return NSMakeSize(((iTermSizeRememberingView *)self.view).originalSize.width, _heightWithoutNonAsciiControls);
    }
}

- (void)updateFontsDescriptionsIncludingSpacing:(BOOL)includingSpacing {
    // Update the fonts.
    self.normalFont = [[self stringForKey:KEY_NORMAL_FONT] fontValue];
    self.nonAsciiFont = [[self stringForKey:KEY_NON_ASCII_FONT] fontValue];

    // Update the controls.
    const double horizontalSpacing = round([self doubleForKey:KEY_HORIZONTAL_SPACING] * 100);
    _asciiFontPicker.horizontalSpacing.size = horizontalSpacing;
    const double verticalSpacing = round([self doubleForKey:KEY_VERTICAL_SPACING] * 100);
    _asciiFontPicker.verticalSpacing.size = verticalSpacing;
    _asciiFontPicker.font = _normalFont;
    _nonASCIIFontPicker.font = _nonAsciiFont;

    if (self.normalFont.it_defaultLigatures) {
        _asciiLigatures.state = NSControlStateValueOn;
        _asciiLigatures.enabled = NO;
    } else if (self.normalFont.it_ligatureLevel == 0) {
        _asciiLigatures.state = NSControlStateValueOff;
        _asciiLigatures.enabled = NO;
    } else {
        _asciiLigatures.state = [self boolForKey:KEY_ASCII_LIGATURES] ? NSControlStateValueOn : NSControlStateValueOff;
        _asciiLigatures.enabled = YES;
    }
    if (self.nonAsciiFont.it_defaultLigatures) {
        _nonAsciiLigatures.state = NSControlStateValueOn;
        _nonAsciiLigatures.enabled = NO;
    } else if (self.nonAsciiFont.it_ligatureLevel == 0) {
        _nonAsciiLigatures.state = NSControlStateValueOff;
        _nonAsciiLigatures.enabled = NO;
    } else {
        _nonAsciiLigatures.state = [self boolForKey:KEY_NON_ASCII_LIGATURES] ? NSControlStateValueOn : NSControlStateValueOff;
        _nonAsciiLigatures.enabled = YES;
    }

    [self updateThinStrokesEnabled];
    [self updateWarnings];
}

- (BOOL)cursorTypeSupportsShadow {
    switch ((ITermCursorType)[self intForKey:KEY_CURSOR_TYPE]) {
        case CURSOR_UNDERLINE:
        case CURSOR_VERTICAL:
            return YES;
        case CURSOR_BOX:
        case CURSOR_DEFAULT:
            return NO;
    }
    return NO;
}

- (void)updateShadowEnabled {
    _shadow.enabled = [self cursorTypeSupportsShadow];
}

- (void)updateThinStrokesEnabled {
    if (iTermTextIsMonochrome()) {
        _subpixelAA.state = NSControlStateValueOff;
    } else {
        _subpixelAA.state = NSControlStateValueOn;
    }
    _subpixelAA.enabled = YES;
}

- (void)updateWarnings {
    [_normalFontWantsAntialiasing setHidden:!self.normalFont.futureShouldAntialias];
    [_nonasciiFontWantsAntialiasing setHidden:!self.nonAsciiFont.futureShouldAntialias];
}


#pragma mark - Actions

- (IBAction)didToggleSubpixelAntiAliasing:(id)sender {
    NSString *const key = @"CGFontRenderingFontSmoothingDisabled";
    if (_subpixelAA.state == NSControlStateValueOff) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    } else {
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:key];
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Subpixel Anti Aliasing";
    alert.informativeText = @"This change will affect all profiles. You must restart iTerm2 for this change to take effect.";
    [alert runModal];
    [self updateWarnings];
}

#pragma mark - Notifications

- (void)reloadProfiles {
    [self updateFontsDescriptionsIncludingSpacing:YES];
}

- (void)preferenceDidChangeFromOtherPanel:(NSNotification *)notification {
    NSString *key = notification.userInfo[kPreferenceDidChangeFromOtherPanelKeyUserInfoKey];
    if ([key isEqualToString:KEY_NORMAL_FONT]) {
        _asciiFontPicker.font = [self stringForKey:KEY_NORMAL_FONT].fontValue;
    } else if ([key isEqualToString:KEY_NON_ASCII_FONT]) {
        _nonASCIIFontPicker.font = [self stringForKey:KEY_NON_ASCII_FONT].fontValue;
    }
    [super preferenceDidChangeFromOtherPanel:notification];
}

#pragma mark - BFPCompositeViewDelegate

- (void)fontPickerCompositeView:(BFPCompositeView *)view didSelectFont:(NSFont *)font {
    NSString *key;
    if (view == _asciiFontPicker) {
        key = KEY_NORMAL_FONT;
    } else {
        assert(view == _nonASCIIFontPicker);
        key = KEY_NON_ASCII_FONT;
    }
    [self setString:view.font.stringValue
             forKey:key];
    [self updateFontsDescriptionsIncludingSpacing:YES];
    [self updateLigatureWarning];
}

#pragma mark - BFPSizePickerViewDelegate

- (void)sizePickerView:(BFPSizePickerView *)sizePickerView didChangeSizeTo:(double)size {
    [self saveChangesFromFontPicker];
}

- (void)saveDeferredUpdates {
    [self.view.window makeFirstResponder:nil];
    [self saveChangesFromFontPicker];
    [super saveDeferredUpdates];
}

- (void)saveChangesFromFontPicker {
    NSInteger (^clamp)(NSInteger value) = ^NSInteger(NSInteger value) {
        return MIN(MAX(value, 50), 200);
    };
    // I don't know why these would sometimes be null, but let's not crash if
    // that happens. It was one of the major crashes in 3.3.1.
    id normalFont = _asciiFontPicker.font.stringValue ?: [NSNull null];
    id nonAsciiFont = _nonASCIIFontPicker.font.stringValue ?: [NSNull null];
    DLog(@"Save changes from font picker. asciiFontPicker=%@ asciiFontPicker.font=%@ asciiFontPicker.font.stringValue=%@", _asciiFontPicker, _asciiFontPicker.font, _asciiFontPicker.font.stringValue);
    DLog(@"Save changes from font picker. nonASCIIFontPicker=%@ asciiFontPicker.font=%@ asciiFontPicker.font.stringValue=%@", _nonASCIIFontPicker, _nonASCIIFontPicker.font, _nonASCIIFontPicker.font.stringValue);
    NSDictionary *dictionaryWithNulls = @{ KEY_HORIZONTAL_SPACING: @(clamp(_asciiFontPicker.horizontalSpacing.size) / 100.0),
                                           KEY_VERTICAL_SPACING: @(clamp(_asciiFontPicker.verticalSpacing.size) / 100.0),
                                           KEY_NORMAL_FONT: normalFont,
                                           KEY_NON_ASCII_FONT: nonAsciiFont };
    NSDictionary *dict = [dictionaryWithNulls dictionaryByRemovingNullValues];
    [self setObjectsFromDictionary:dict];
}

@end
