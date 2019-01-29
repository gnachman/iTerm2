//
//  ProfilesTextPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/15/14.
//
//

#import "ProfilesTextPreferencesViewController.h"
#import "FutureMethods.h"
#import "ITAddressBookMgr.h"
#import "iTermFontPanel.h"
#import "iTermSizeRememberingView.h"
#import "iTermWarning.h"
#import "NSFont+iTerm.h"
#import "NSStringITerm.h"
#import "NSTextField+iTerm.h"
#import "PreferencePanel.h"
#import "PTYFontInfo.h"

// Tag on button to open font picker for non-ascii font.
static NSInteger kNonAsciiFontButtonTag = 1;

@interface ProfilesTextPreferencesViewController ()
@property(nonatomic, strong) NSFont *normalFont;
@property(nonatomic, strong) NSFont *nonAsciiFont;
@end

@implementation ProfilesTextPreferencesViewController {
    // cursor type: underline/vertical bar/box
    // See ITermCursorType. One of: CURSOR_UNDERLINE, CURSOR_VERTICAL, CURSOR_BOX
    IBOutlet NSMatrix *_cursorType;
    IBOutlet NSButton *_blinkingCursor;
    IBOutlet NSButton *_useBoldFont;
    IBOutlet NSButton *_blinkAllowed;
    IBOutlet NSButton *_useItalicFont;
    IBOutlet NSButton *_ambiguousIsDoubleWidth;
    IBOutlet NSPopUpButton *_normalization;
    IBOutlet NSSlider *_horizontalSpacing;
    IBOutlet NSSlider *_verticalSpacing;
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
    
    // Labels indicating current font. Not registered as controls.
    IBOutlet NSTextField *_normalFontDescription;
    IBOutlet NSTextField *_nonAsciiFontDescription;

    // Warning labels
    IBOutlet NSTextField *_normalFontWantsAntialiasing;
    IBOutlet NSTextField *_nonasciiFontWantsAntialiasing;

    // Hide this view to hide all non-ASCII font settings.
    IBOutlet NSView *_nonAsciiFontView;

    // If set, the font picker was last opened to change the non-ascii font.
    // Used to interpret messages from it.
    BOOL _fontPickerIsForNonAsciiFont;

    // This view is added to the font panel.
    IBOutlet NSView *_displayFontAccessoryView;
    IBOutlet NSTextField *_horizontalSpacingAccessoryTextField;
    IBOutlet NSTextField *_verticalSpacingAccessoryTextField;

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
    [self defineControl:_cursorType
                    key:KEY_CURSOR_TYPE
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

    [self defineControl:_blinkingCursor
                    key:KEY_BLINKING_CURSOR
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_useBoldFont
                    key:KEY_USE_BOLD_FONT
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_thinStrokes
                    key:KEY_THIN_STROKES
                   type:kPreferenceInfoTypePopup];

    [self defineControl:_blinkAllowed
                    key:KEY_BLINK_ALLOWED
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_useItalicFont
                    key:KEY_USE_ITALIC_FONT
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_asciiLigatures
                    key:KEY_ASCII_LIGATURES
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_nonAsciiLigatures
                    key:KEY_NON_ASCII_LIGATURES
                   type:kPreferenceInfoTypeCheckbox];

    PreferenceInfo *info = [self defineControl:_ambiguousIsDoubleWidth
                                           key:KEY_AMBIGUOUS_DOUBLE_WIDTH
                                          type:kPreferenceInfoTypeCheckbox];
    info.customSettingChangedHandler = ^(id sender) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        BOOL isOn = [sender state] == NSOnState;
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
                   type:kPreferenceInfoTypePopup];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(unicodeVersionDidChange)
                                                 name:iTermUnicodeVersionDidChangeNotification
                                               object:nil];
    [self defineControl:_unicodeVersion9
                    key:KEY_UNICODE_VERSION
                   type:kPreferenceInfoTypeCheckbox
         settingChanged:^(id sender) {
             __strong __typeof(weakSelf) strongSelf = weakSelf;
             if (!strongSelf) {
                 return;
             }
             const NSInteger version = (strongSelf->_unicodeVersion9.state == NSOnState) ? 9 : 8;
             [strongSelf setInteger:version forKey:KEY_UNICODE_VERSION];
         }
                 update:^BOOL{
                     __strong __typeof(weakSelf) strongSelf = weakSelf;
                     if (!strongSelf) {
                         return NO;
                     }
                     strongSelf->_unicodeVersion9.state = [strongSelf integerForKey:KEY_UNICODE_VERSION] == 9 ? NSOnState : NSOffState;
                     return YES;
                 }];


    info = [self defineControl:_horizontalSpacing
                           key:KEY_HORIZONTAL_SPACING
                          type:kPreferenceInfoTypeSlider];
    info.observer = ^{
        [weakSelf fontAccessorySliderDidChange];
    };

    info = [self defineControl:_verticalSpacing
                           key:KEY_VERTICAL_SPACING
                          type:kPreferenceInfoTypeSlider];
    info.observer = ^{
        [weakSelf fontAccessorySliderDidChange];
    };

    info = [self defineControl:_useNonAsciiFont
                           key:KEY_USE_NONASCII_FONT
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{ [weakSelf updateNonAsciiFontViewVisibility]; };

    info = [self defineControl:_asciiAntiAliased
                           key:KEY_ASCII_ANTI_ALIASED
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{ [weakSelf updateWarnings]; };

    info = [self defineControl:_nonasciiAntiAliased
                           key:KEY_NONASCII_ANTI_ALIASED
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{ [weakSelf updateWarnings]; };

    [self defineControl:_powerline
                    key:KEY_POWERLINE
                   type:kPreferenceInfoTypeCheckbox];

    [self updateFontsDescriptions];
    [self updateNonAsciiFontViewVisibility];
}

- (void)fontAccessorySliderDidChange {
    _horizontalSpacingAccessoryTextField.intValue = _horizontalSpacing.doubleValue * 100;
    _verticalSpacingAccessoryTextField.intValue = _verticalSpacing.doubleValue * 100;
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    NSTextField *control = [notification object];
    NSString *key = nil;
    NSSlider *slider;
    if (control == _horizontalSpacingAccessoryTextField) {
        key = KEY_HORIZONTAL_SPACING;
        slider = _horizontalSpacing;
    } else if (control == _verticalSpacingAccessoryTextField) {
        key = KEY_VERTICAL_SPACING;
        slider = _verticalSpacing;
    }
    if (key) {
        const int clamped = MIN(MAX(control.intValue, 50), 200);
        const double value = clamped / 100.0;
        [self setFloat:value forKey:key];
        slider.doubleValue = value;
        control.intValue = clamped;
    }
    [super controlTextDidEndEditing:notification];
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
    [self updateFontsDescriptions];
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
        return NSMakeSize(NSWidth(self.view.frame), _heightWithNonAsciiControls);
    } else {
        return NSMakeSize(NSWidth(self.view.frame), _heightWithoutNonAsciiControls);
    }
}

- (void)updateFontsDescriptions {
    // Update the fonts.
    self.normalFont = [[self stringForKey:KEY_NORMAL_FONT] fontValue];
    self.nonAsciiFont = [[self stringForKey:KEY_NON_ASCII_FONT] fontValue];

    // Update the descriptions.
    NSString *fontName;
    if (_normalFont != nil) {
        fontName = [NSString stringWithFormat: @"%gpt %@",
                    [_normalFont pointSize], [_normalFont displayName]];
    } else {
        fontName = @"Unknown Font";
    }
    [_normalFontDescription setStringValue:fontName];

    if (_nonAsciiFont != nil) {
        fontName = [NSString stringWithFormat: @"%gpt %@",
                    [_nonAsciiFont pointSize], [_nonAsciiFont displayName]];
    } else {
        fontName = @"Unknown Font";
    }
    [_nonAsciiFontDescription setStringValue:fontName];

    if (self.normalFont.it_defaultLigatures) {
        _asciiLigatures.state = NSOnState;
        _asciiLigatures.enabled = NO;
    } else if (self.normalFont.it_ligatureLevel == 0) {
        _asciiLigatures.state = NSOffState;
        _asciiLigatures.enabled = NO;
    } else {
        _asciiLigatures.state = [self boolForKey:KEY_ASCII_LIGATURES] ? NSOnState : NSOffState;
        _asciiLigatures.enabled = YES;
    }
    if (self.nonAsciiFont.it_defaultLigatures) {
        _nonAsciiLigatures.state = NSOnState;
        _nonAsciiLigatures.enabled = NO;
    } else if (self.nonAsciiFont.it_ligatureLevel == 0) {
        _nonAsciiLigatures.state = NSOffState;
        _nonAsciiLigatures.enabled = NO;
    } else {
        _nonAsciiLigatures.state = [self boolForKey:KEY_NON_ASCII_LIGATURES] ? NSOnState : NSOffState;
        _nonAsciiLigatures.enabled = YES;
    }

    [self updateThinStrokesEnabled];
    [self updateWarnings];
}

- (void)updateThinStrokesEnabled {
    if (@available(macOS 10.14, *)) {
        if (iTermTextIsMonochrome()) {
            _subpixelAA.state = NSOffState;
        } else {
            _subpixelAA.state = NSOnState;
        }
        _subpixelAA.enabled = YES;
    } else {
        _subpixelAA.hidden = YES;
    }
}

- (void)updateWarnings {
    [_normalFontWantsAntialiasing setHidden:!self.normalFont.futureShouldAntialias];
    [_nonasciiFontWantsAntialiasing setHidden:!self.nonAsciiFont.futureShouldAntialias];
}


#pragma mark - Actions

- (IBAction)openFontPicker:(id)sender {
    _fontPickerIsForNonAsciiFont = ([sender tag] == kNonAsciiFontButtonTag);
    [self showFontPanel];
}

- (IBAction)didToggleSubpixelAntiAliasing:(id)sender {
    NSString *const key = @"CGFontRenderingFontSmoothingDisabled";
    if (_subpixelAA.state == NSOffState) {
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

#pragma mark - NSFontPanel and NSFontManager

- (void)showFontPanel {
    // make sure we get the messages from the NSFontManager
    [[self.view window] makeFirstResponder:self];

    NSFontPanel* aFontPanel = [[NSFontManager sharedFontManager] fontPanel: YES];
    [aFontPanel setAccessoryView:_displayFontAccessoryView];
    NSFont *theFont = (_fontPickerIsForNonAsciiFont ? _nonAsciiFont : _normalFont);
    [[NSFontManager sharedFontManager] setSelectedFont:theFont isMultiple:NO];
    [[NSFontManager sharedFontManager] orderFrontFontPanel:self];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
- (NSFontPanelModeMask)validModesForFontPanel:(NSFontPanel *)fontPanel {
#pragma clang diagnostic pop
    return kValidModesForFontPanel;
}

// sent by NSFontManager up the responder chain
- (void)changeFont:(id)fontManager {
    if (_fontPickerIsForNonAsciiFont) {
        [self setString:[[fontManager convertFont:_nonAsciiFont] stringValue]
                 forKey:KEY_NON_ASCII_FONT];
    } else {
        [self setString:[[fontManager convertFont:_normalFont] stringValue]
                 forKey:KEY_NORMAL_FONT];
    }
    [self updateFontsDescriptions];
}

#pragma mark - Notifications

- (void)reloadProfiles {
    [self updateFontsDescriptions];
}

@end
