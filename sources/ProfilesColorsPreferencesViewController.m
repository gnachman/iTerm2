//
//  ProfilesColorsPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/14/14.
//
//

#import "ProfilesColorsPreferencesViewController.h"
#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermColorPresets.h"
#import "iTermPreferenceDidChangeNotification.h"
#import "iTermProfilePreferences.h"
#import "iTermSizeRememberingView.h"
#import "iTermTextPopoverViewController.h"
#import "iTermWarning.h"
#import "NSAppearance+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSTextField+iTerm.h"
#import "NSView+iTerm.h"
#import "PreferencePanel.h"

#import <ColorPicker/ColorPicker.h>

static NSString * const kColorGalleryURL = @"https://www.iterm2.com/colorgallery";

@interface ProfilesColorsPreferencesViewController()<iTermSizeRememberingViewDelegate, NSMenuDelegate>
@end

@implementation ProfilesColorsPreferencesViewController {
    IBOutlet NSPopUpButton *_mode;
    IBOutlet NSButton *_useSeparateColorsForLightAndDarkMode;
    IBOutlet NSTextField *_modeLabel;

    IBOutlet CPKColorWell *_ansi0Color;
    IBOutlet CPKColorWell *_ansi1Color;
    IBOutlet CPKColorWell *_ansi2Color;
    IBOutlet CPKColorWell *_ansi3Color;
    IBOutlet CPKColorWell *_ansi4Color;
    IBOutlet CPKColorWell *_ansi5Color;
    IBOutlet CPKColorWell *_ansi6Color;
    IBOutlet CPKColorWell *_ansi7Color;
    IBOutlet CPKColorWell *_ansi8Color;
    IBOutlet CPKColorWell *_ansi9Color;
    IBOutlet CPKColorWell *_ansi10Color;
    IBOutlet CPKColorWell *_ansi11Color;
    IBOutlet CPKColorWell *_ansi12Color;
    IBOutlet CPKColorWell *_ansi13Color;
    IBOutlet CPKColorWell *_ansi14Color;
    IBOutlet CPKColorWell *_ansi15Color;
    IBOutlet CPKColorWell *_foregroundColor;
    IBOutlet CPKColorWell *_backgroundColor;
    IBOutlet NSButton *_useBrightBold;  // Respect bold
    IBOutlet NSButton *_brightenBoldText;
    IBOutlet CPKColorWell *_boldColor;
    IBOutlet CPKColorWell *_linkColor;
    IBOutlet CPKColorWell *_matchColor;
    IBOutlet CPKColorWell *_selectionColor;
    IBOutlet CPKColorWell *_selectedTextColor;
    IBOutlet CPKColorWell *_cursorColor;
    IBOutlet CPKColorWell *_cursorTextColor;
    IBOutlet CPKColorWell *_tabColor;
    IBOutlet CPKColorWell *_underlineColor;
    IBOutlet CPKColorWell *_badgeColor;

    IBOutlet NSTextField *_ansi0ColorLabel;
    IBOutlet NSTextField *_ansi1ColorLabel;
    IBOutlet NSTextField *_ansi2ColorLabel;
    IBOutlet NSTextField *_ansi3ColorLabel;
    IBOutlet NSTextField *_ansi4ColorLabel;
    IBOutlet NSTextField *_ansi5ColorLabel;
    IBOutlet NSTextField *_ansi6ColorLabel;
    IBOutlet NSTextField *_ansi7ColorLabel;
    IBOutlet NSTextField *_foregroundColorLabel;
    IBOutlet NSTextField *_backgroundColorLabel;
    IBOutlet NSTextField *_linkColorLabel;
    IBOutlet NSTextField *_matchColorLabel;
    IBOutlet NSTextField *_selectionColorLabel;
    IBOutlet NSButton *_selectedTextColorEnabledButton;
    IBOutlet NSTextField *_badgeColorLabel;

    IBOutlet NSTextField *_cursorColorLabel;
    IBOutlet NSTextField *_cursorTextColorLabel;

    IBOutlet NSButton *_useTabColor;
    IBOutlet NSButton *_useUnderlineColor;
    IBOutlet NSButton *_useSmartCursorColor;

    IBOutlet NSSlider *_minimumContrast;
    IBOutlet NSTextField *_faintTextAlphaLabel;
    IBOutlet NSSlider *_faintTextAlpha;
    IBOutlet NSSlider *_cursorBoost;
    IBOutlet NSTextField *_minimumContrastLabel;
    IBOutlet NSTextField *_cursorBoostLabel;

    IBOutlet NSMenu *_presetsMenu;

    IBOutlet NSButton *_useGuide;
    IBOutlet CPKColorWell *_guideColor;

    IBOutlet NSPopUpButton *_presetsPopupButton;
    IBOutlet NSView *_bwWarning1;
    IBOutlet NSView *_bwWarning2;

    IBOutlet NSButton *_modeWarning;

    NSDictionary<NSString *, id> *_savedColors;
    NSTimer *_timer;
}

+ (NSArray<NSString *> *)presetNames {
    NSArray<NSString *> *builtInNames = [[iTermColorPresets builtInColorPresets] allKeys];
    NSArray<NSString *> *customNames = [[iTermColorPresets customColorPresets] allKeys];
    return [builtInNames arrayByAddingObjectsFromArray:customNames];
}

+ (iTermColorPreset *)presetWithName:(NSString *)name {
    iTermColorPreset *dict = [[iTermColorPresets builtInColorPresets] objectForKey:name];
    if (dict) {
        return dict;
    }
    return [[iTermColorPresets customColorPresets] objectForKey:name];
}

+ (NSString *)nameOfPresetUsedByProfile:(Profile *)profile {
    for (NSString *presetName in [self presetNames]) {
        iTermColorPreset *preset = [self presetWithName:presetName];
        BOOL ok = YES;
        const BOOL presetUsesModes = iTermColorPresetHasModes(preset);
        const BOOL profileUsesModes = [iTermProfilePreferences boolForKey:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE
                                                                inProfile:profile];
        if (presetUsesModes != profileUsesModes) {
            continue;
        }
        for (NSString *colorName in [ProfileModel colorKeysWithModes:presetUsesModes]) {
            iTermColorDictionary *presetColorDict = [preset iterm_presetColorWithName:colorName];
            NSDictionary *profileColorDict = [iTermProfilePreferences objectForKey:colorName
                                                                         inProfile:profile];
            if (![presetColorDict isEqual:profileColorDict] && presetColorDict != profileColorDict) {
                ok = NO;
                break;
            }
        }
        if (ok) {
            return presetName;
        }
    }
    return nil;
}

- (void)awakeFromNib {
    ((iTermSizeRememberingView *)self.view).delegate = self;

    // Updates fields when a preset is loaded.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProfile)
                                                 name:kReloadAllProfiles
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(rebuildColorPresetsMenu)
                                                 name:kRebuildColorPresetsMenuNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(popupButtonWillPopUp:)
                                                 name:NSPopUpButtonWillPopUpNotification
                                               object:_presetsPopupButton];

    __weak __typeof(self) weakSelf = self;
    [iTermPreferenceDidChangeNotification subscribe:self block:^(iTermPreferenceDidChangeNotification * _Nonnull notification) {
        if ([notification.key isEqualToString:kPreferenceKeyTabStyle]) {
            // If the tab style changes the warning button may need to (dis)appear.
            [weakSelf reloadProfile];
        }
    }];
    // Add presets to preset color selection.
    [self rebuildColorPresetsMenu];

    NSDictionary *colorWellDictionary = [self colorWellDictionary];
    NSDictionary *relatedViews = [self colorWellRelatedViews];
    for (NSString *key in colorWellDictionary) {
        CPKColorWell *colorWell = colorWellDictionary[key];
        colorWell.colorSpace = [NSColorSpace it_defaultColorSpace];
        NSTextField *relatedView = relatedViews[key];
        [self defineControl:colorWell
                        key:key
                relatedView:nil
                displayName:[NSString stringWithFormat:@"%@ color", relatedView.stringValue]
                       type:kPreferenceInfoTypeColorWell
             settingChanged:nil
                     update:nil
                 searchable:relatedView != nil];
        colorWell.action = @selector(settingChanged:);
        colorWell.target = self;
        colorWell.continuous = YES;
        __weak NSView *weakColorWell = colorWell;
        colorWell.willClosePopover = ^() {
            // NSSearchField remembers who was first responder before it gained
            // first responder status. That is the popover at this time. When
            // the app becomes inactive, the search field makes the previous
            // first responder the new first responder. The search field is not
            // smart and doesn't realize the popover has been deallocated. So
            // this changes its conception of who was the previous first
            // responder and prevents the crash.
            [weakColorWell.window makeFirstResponder:nil];
        };
    }

    PreferenceInfo *info;

    // The separate colors stuff should be done first because -amendedKey:, which is called when
    // defining controls, expects it to be correct.
    const BOOL dark = [NSApp effectiveAppearance].it_isDark;
    [_mode selectItemWithTag:dark ? 1 : 0];
    info = [self defineControl:_useSeparateColorsForLightAndDarkMode
                           key:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.customSettingChangedHandler = ^(id sender) {
        const BOOL useModes = [sender state] == NSControlStateValueOn;
        [weakSelf useSeparateColorsDidChange:useModes];
        // This has to be done after copying colors or else default colors might be used.
        [weakSelf setBool:useModes forKey:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE];
    };


    info = [self defineControl:_useTabColor
                           key:KEY_USE_TAB_COLOR
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^() { [weakSelf updateColorControlsEnabled]; };

    info = [self defineControl:_selectedTextColorEnabledButton
                           key:KEY_USE_SELECTED_TEXT_COLOR
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^() { [weakSelf updateColorControlsEnabled]; };

    info = [self defineControl:_useUnderlineColor
                           key:KEY_USE_UNDERLINE_COLOR
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^() { [weakSelf updateColorControlsEnabled]; };

    info = [self defineControl:_useSmartCursorColor
                           key:KEY_SMART_CURSOR_COLOR
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^() { [weakSelf updateColorControlsEnabled]; };

    info = [self defineControl:_minimumContrast
                           key:KEY_MINIMUM_CONTRAST
                   relatedView:_minimumContrastLabel
                          type:kPreferenceInfoTypeSlider];
    info.observer = ^() { [weakSelf maybeWarnAboutExcessiveContrast]; };

    [self defineControl:_faintTextAlpha
                    key:KEY_FAINT_TEXT_ALPHA
            relatedView:_faintTextAlphaLabel
                   type:kPreferenceInfoTypeSlider];

    [self defineControl:_cursorBoost
                    key:KEY_CURSOR_BOOST
            relatedView:_cursorBoostLabel
                   type:kPreferenceInfoTypeSlider];

    [self defineControl:_useGuide
                    key:KEY_USE_CURSOR_GUIDE
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_useBrightBold
                           key:KEY_USE_BOLD_COLOR
                   displayName:@"Custom color for bold text"
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{ [weakSelf updateColorControlsEnabled]; };

    info = [self defineControl:_brightenBoldText
                           key:KEY_BRIGHTEN_BOLD_TEXT
                   displayName:@"Brighten bold text"
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{ [weakSelf updateColorControlsEnabled]; };

    [self addViewToSearchIndex:_presetsPopupButton
                   displayName:@"Color presets"
                       phrases:@[]
                           key:nil];

    [self maybeWarnAboutExcessiveContrast];
    [self updateColorControlsEnabled];
}

- (void)reloadProfile {
    [super reloadProfile];
    [self updateModeEnabled:[self boolForKey:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE]];
}

- (void)useSeparateColorsDidChange:(BOOL)useModes {
    [self updateModeEnabled:useModes];
    if (useModes) {
        [self copySharedColorsToModalColorsIfNeeded:YES];
    } else {
        [self copyCurrentModeColorsToShared];
    }
}

- (void)updateModeEnabled:(BOOL)useModes {
    if (!useModes) {
        _mode.enabled = NO;
        _modeLabel.labelEnabled = NO;
        _modeWarning.hidden = YES;
        DLog(@"Do not copy");
        return;
    }
    _mode.enabled = YES;
    _modeLabel.labelEnabled = YES;

    switch ((iTermPreferencesTabStyle)[iTermPreferences intForKey:kPreferenceKeyTabStyle]) {
        case TAB_STYLE_COMPACT:
        case TAB_STYLE_MINIMAL:
        case TAB_STYLE_AUTOMATIC:
            _modeWarning.hidden = YES;
            break;

        case TAB_STYLE_LIGHT:
        case TAB_STYLE_DARK:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            _modeWarning.hidden = NO;
            break;
    }

}

- (void)copySharedColorsToModalColorsIfNeeded:(BOOL)useModes {
    [self updateModeEnabled:useModes];
    if (!useModes) {
        DLog(@"Do not copy");
        return;
    }
    // Copy the shared colors to the per-mode colors in user defaults if they do not already exist.
    DLog(@"-- begin copying colors --");
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    for (NSString *baseKey in [self keysForBulkCopy]) {
        if ([baseKey isEqualToString:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE]) {
            DLog(@"Ignore %@", baseKey);
            continue;
        }
        for (NSString *suffix in @[ COLORS_LIGHT_MODE_SUFFIX, COLORS_DARK_MODE_SUFFIX ]) {
            NSString *key = [baseKey stringByAppendingString:suffix];
            id newValue = [super objectForKey:baseKey];
            if (!newValue) {
                DLog(@"Have no value for %@", baseKey);
                continue;
            }
            if (profile[key] != nil) {
                DLog(@"Already have a non-default value key %@", key);
                continue;
            }
            DLog(@"Set %@ = %@ [baseKey=%@]", key, newValue, baseKey);
            [super setObject:newValue forKey:key];
        }
    }
    DLog(@"-- finished copying colors --");
}

- (void)copyCurrentModeColorsToShared {
    DLog(@"-- begin copying colors to shared --");
    NSString *suffix = _mode.selectedTag == 1 ? COLORS_DARK_MODE_SUFFIX : COLORS_LIGHT_MODE_SUFFIX;
    for (NSString *baseKey in [self keysForBulkCopy]) {
        NSString *key = [baseKey stringByAppendingString:suffix];
        id newValue = [super objectForKey:key];
        if (!newValue) {
            DLog(@"Have no value for %@", key);
            continue;
        }
        DLog(@"Set %@ = %@ [source key=%@]", baseKey, newValue, key);
        [super setObject:newValue forKey:baseKey];
    }
    DLog(@"-- finished copying colors to shared --");
}

- (void)maybeWarnAboutExcessiveContrast {
    const BOOL hidden = ([self floatForKey:KEY_MINIMUM_CONTRAST] < 0.97);
    _bwWarning1.hidden = hidden;
    _bwWarning2.hidden = hidden;
}

- (void)updateColorControlsEnabled {
    _tabColor.enabled = [self boolForKey:KEY_USE_TAB_COLOR];
    _selectedTextColor.enabled = [self boolForKey:KEY_USE_SELECTED_TEXT_COLOR];
    _underlineColor.enabled = [self boolForKey:KEY_USE_UNDERLINE_COLOR];

    const BOOL smartCursorColorSelected = [self boolForKey:KEY_SMART_CURSOR_COLOR];
    const BOOL shouldEnableSmartCursorColor = ([self intForKey:KEY_CURSOR_TYPE] == CURSOR_BOX);
    const BOOL shouldEnableCursorColor = !(smartCursorColorSelected && shouldEnableSmartCursorColor);

    _cursorColor.enabled = shouldEnableCursorColor;
    _cursorTextColor.enabled = shouldEnableCursorColor;
    _boldColor.enabled = [self boolForKey:KEY_USE_BOLD_COLOR];
    _cursorColorLabel.labelEnabled = shouldEnableCursorColor;
    _cursorTextColorLabel.labelEnabled = shouldEnableCursorColor;
}

- (NSDictionary *)colorWellDictionary {
    return @{ KEY_ANSI_0_COLOR: _ansi0Color,
              KEY_ANSI_1_COLOR: _ansi1Color,
              KEY_ANSI_2_COLOR: _ansi2Color,
              KEY_ANSI_3_COLOR: _ansi3Color,
              KEY_ANSI_4_COLOR: _ansi4Color,
              KEY_ANSI_5_COLOR: _ansi5Color,
              KEY_ANSI_6_COLOR: _ansi6Color,
              KEY_ANSI_7_COLOR: _ansi7Color,
              KEY_ANSI_8_COLOR: _ansi8Color,
              KEY_ANSI_9_COLOR: _ansi9Color,
              KEY_ANSI_10_COLOR: _ansi10Color,
              KEY_ANSI_11_COLOR: _ansi11Color,
              KEY_ANSI_12_COLOR: _ansi12Color,
              KEY_ANSI_13_COLOR: _ansi13Color,
              KEY_ANSI_14_COLOR: _ansi14Color,
              KEY_ANSI_15_COLOR: _ansi15Color,
              KEY_FOREGROUND_COLOR: _foregroundColor,
              KEY_BACKGROUND_COLOR: _backgroundColor,
              KEY_BOLD_COLOR: _boldColor,
              KEY_LINK_COLOR: _linkColor,
              KEY_MATCH_COLOR: _matchColor,
              KEY_SELECTION_COLOR: _selectionColor,
              KEY_SELECTED_TEXT_COLOR: _selectedTextColor,
              KEY_CURSOR_COLOR: _cursorColor,
              KEY_CURSOR_TEXT_COLOR: _cursorTextColor,
              KEY_TAB_COLOR: _tabColor,
              KEY_UNDERLINE_COLOR: _underlineColor,
              KEY_CURSOR_GUIDE_COLOR: _guideColor,
              KEY_BADGE_COLOR: _badgeColor };
}

- (NSDictionary *)colorWellRelatedViews {
    return @{ KEY_ANSI_0_COLOR: _ansi0ColorLabel,
              KEY_ANSI_1_COLOR: _ansi1ColorLabel,
              KEY_ANSI_2_COLOR: _ansi2ColorLabel,
              KEY_ANSI_3_COLOR: _ansi3ColorLabel,
              KEY_ANSI_4_COLOR: _ansi4ColorLabel,
              KEY_ANSI_5_COLOR: _ansi5ColorLabel,
              KEY_ANSI_6_COLOR: _ansi6ColorLabel,
              KEY_ANSI_7_COLOR: _ansi7ColorLabel,
              KEY_FOREGROUND_COLOR: _foregroundColorLabel,
              KEY_BACKGROUND_COLOR: _backgroundColorLabel,
              KEY_SELECTION_COLOR: _selectionColorLabel,
              KEY_SELECTED_TEXT_COLOR: _selectedTextColorEnabledButton,
              KEY_CURSOR_COLOR: _cursorColorLabel,
              KEY_CURSOR_TEXT_COLOR: _cursorTextColorLabel,
              KEY_BADGE_COLOR: _badgeColorLabel };
}

#pragma mark - Color Presets

- (void)rebuildColorPresetsMenu {
    while ([_presetsMenu numberOfItems] > 1) {
        [_presetsMenu removeItemAtIndex:1];
    }

    iTermColorPresetDictionary *presetsDict = [iTermColorPresets builtInColorPresets];
    [self addColorPresetsInDict:presetsDict toMenu:_presetsMenu];

    iTermColorPresetDictionary *customPresets = [iTermColorPresets customColorPresets];
    if (customPresets && [customPresets count] > 0) {
        [_presetsMenu addItem:[NSMenuItem separatorItem]];
        [self addColorPresetsInDict:customPresets toMenu:_presetsMenu];
    }

    [_presetsMenu addItem:[NSMenuItem separatorItem]];

    [self addPresetItemWithTitle:@"Import..." action:@selector(importColorPreset:)];
    [self addPresetItemWithTitle:@"Export..." action:@selector(exportColorPreset:)];
    [self addPresetItemWithTitle:@"Delete Preset..." action:@selector(deleteColorPreset:)];
    [self addPresetItemWithTitle:@"Visit Online Gallery" action:@selector(visitGallery:)];
    _presetsMenu.delegate = self;
}

- (void)addPresetItemWithTitle:(NSString *)title action:(SEL)action {
    NSMenuItem *item = [_presetsMenu addItemWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
}

- (void)addColorPresetsInDict:(iTermColorPresetDictionary *)presetsDict toMenu:(NSMenu *)theMenu {
    ProfileModel *model = [self.delegate profilePreferencesCurrentModel];
    for (int i = 0; i < 2; i++) {
        NSInteger count = 0;
        for (NSString* key in  [[presetsDict allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            NSString *title = key;
            if ([model presetHasMultipleModes:key]) {
                if (i == 1) {
                    continue;
                }
                title = [@"☯ " stringByAppendingString:key];
            } else if (i == 0) {
                continue;
            }
            count += 1;
            NSMenuItem* presetItem = [[NSMenuItem alloc] initWithTitle:title
                                                                action:@selector(loadColorPreset:)
                                                         keyEquivalent:@""];
            presetItem.identifier = key;
            presetItem.target = self;
            [theMenu addItem:presetItem];
        }
        if (i == 0 && count > 0) {
            [theMenu addItem:[NSMenuItem separatorItem]];
        }
    }
}

- (void)importColorPreset:(id)sender {
    // Create the File Open Dialog class.
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];

    // Set options.
    [openPanel setCanChooseFiles:YES];
    [openPanel setCanChooseDirectories:NO];
    [openPanel setAllowsMultipleSelection:YES];
    [openPanel setAllowedFileTypes:[NSArray arrayWithObject:@"itermcolors"]];

    // Display the dialog.  If the OK button was pressed,
    // process the files.
    if ([openPanel runModal] == NSModalResponseOK) {
        // Get an array containing the full filenames of all
        // files and directories selected.
        for (NSURL *url in openPanel.URLs) {
            [iTermColorPresets importColorPresetFromFile:url.path];
        }
    }
}

- (void)exportColorPreset:(id)sender {
    // Create the File Open Dialog class.
    NSSavePanel *savePanel = [NSSavePanel savePanel];

    // Set options.
    [savePanel setAllowedFileTypes:[NSArray arrayWithObject:@"itermcolors"]];

    if ([savePanel runModal] == NSModalResponseOK) {
        [self exportColorPresetToFile:savePanel.URL.path];
    }
}

- (void)deleteColorPreset:(id)sender {
    iTermColorPresetDictionary *customPresets = [iTermColorPresets customColorPresets];
    if (!customPresets || [customPresets count] == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"No deletable color presets.";
        alert.informativeText = @"You cannot erase the built-in presets and no custom presets have been imported.";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Select a preset to delete:";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    NSPopUpButton *popUpButton = [[NSPopUpButton alloc] init];
    for (NSString *key in [[customPresets allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        [popUpButton addItemWithTitle:key];
        popUpButton.itemArray.lastObject.identifier = key;
    }
    [popUpButton sizeToFit];
    [alert setAccessoryView:popUpButton];
    NSInteger button = [alert runModal];
    if (button == NSAlertFirstButtonReturn) {
        [iTermColorPresets deletePresetWithName:[[popUpButton selectedItem] identifier]];
    }
}

- (void)exportColorPresetToFile:(NSString*)filename {
    NSMutableDictionary* theDict = [NSMutableDictionary dictionaryWithCapacity:24];
    NSDictionary *colorWellDictionary = [self colorWellDictionary];
    if ([self boolForKey:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE]) {
        for (NSString *baseKey in colorWellDictionary) {
            // For compatibility with older versions of iTerm2 - just use the current mode.
            // They'll ignore other keys.
            theDict[baseKey] = [[colorWellDictionary[baseKey] color] dictionaryValue];

            // New versions infer that only modes are to be used if one of the mode keys is present.
            NSString *key = [baseKey stringByAppendingString:COLORS_LIGHT_MODE_SUFFIX];
            theDict[key] = [super objectForKey:key];

            key = [baseKey stringByAppendingString:COLORS_DARK_MODE_SUFFIX];
            theDict[key] = [super objectForKey:key];
        }
    } else {
        for (NSString *key in colorWellDictionary) {
            theDict[key] = [[colorWellDictionary[key] color] dictionaryValue];
        }
    }
    if (![theDict iterm_writePresetToFileWithName:filename]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Save Failed.";
        alert.informativeText = [NSString stringWithFormat:@"Could not save to %@", filename];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    }
}

- (BOOL)shouldUpdateBothModesWhenLoadingPreset:(NSString *)presetName {
    ProfileModel *model = [self.delegate profilePreferencesCurrentModel];
    const BOOL presetHasModes = [model presetHasMultipleModes:presetName];
    const BOOL modes = [self boolForKey:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE];
    const BOOL currentModeIsDark = _mode.selectedTag == 1;
    if (presetHasModes) {
        if (!modes) {
            return YES;
        }
        NSString *currentMode = currentModeIsDark ? @"Dark Mode" : @"Light Mode";
        const iTermWarningSelection selection =
        [iTermWarning showWarningWithTitle:@"This preset has colors for both light mode and dark mode."
                                   actions:@[ @"Update Both Modes",
                                              [NSString stringWithFormat:@"Update %@ Only", currentMode]]
                             actionMapping:nil
                                 accessory:nil
                                identifier:@"NoSyncUpdateWhichModes_PresetHasModes"
                               silenceable:kiTermWarningTypePersistent
                                   heading:@"Update Which Modes?"
                                    window:self.view.window];
        return (selection == 0);
    }
    if (!modes) {
        return NO;
    }
    NSString *currentMode = currentModeIsDark ? @"Dark Mode" : @"Light Mode";
    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:@"This preset does not have separate colors for light mode and dark mode."
                               actions:@[ @"Update Both Modes",
                                          [NSString stringWithFormat:@"Update %@ Only", currentMode]]
                         actionMapping:nil
                             accessory:nil
                            identifier:@"NoSyncUpdateWhichModes_PresetLacksModes"
                           silenceable:kiTermWarningTypePersistent
                               heading:@"Update Which Modes?"
                                window:self.view.window];
    return (selection == 0);
}

- (void)loadColorPresetWithName:(NSString *)presetName prompt:(BOOL)prompt {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [self.delegate profilePreferencesCurrentModel];
    const BOOL currentModeIsDark = _mode.selectedTag == 1;
    const BOOL both = prompt && [self shouldUpdateBothModesWhenLoadingPreset:presetName];

    if (both) {
        [model addColorPresetNamed:presetName
                         toProfile:profile
                              from:iTermColorPresetModeLight
                                to:iTermColorPresetModeLight];
        profile = [self.delegate profilePreferencesCurrentProfile];
        [model addColorPresetNamed:presetName
                         toProfile:profile
                              from:iTermColorPresetModeDark
                                to:iTermColorPresetModeDark];
        [self setBool:YES forKey:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE];
        return;
    }

    const BOOL modes = [self boolForKey:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE];
    if (modes) {
        [model addColorPresetNamed:presetName
                         toProfile:profile
                              from:currentModeIsDark ? iTermColorPresetModeDark : iTermColorPresetModeLight
                                to:currentModeIsDark ? iTermColorPresetModeDark : iTermColorPresetModeLight];
    } else {
        const BOOL dark = [NSApp effectiveAppearance].it_isDark;
        [model addColorPresetNamed:presetName
                         toProfile:profile
                              from:dark ? iTermColorPresetModeDark : iTermColorPresetModeLight
                                to:0];
    }
}

- (void)loadColorPreset:(id)sender {
    _savedColors = nil;
    [self loadColorPresetWithName:[sender identifier] prompt:YES];
}

- (void)visitGallery:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kColorGalleryURL]];
}

- (BOOL)currentColorsEqualPreset:(NSDictionary *)preset {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    const BOOL presetUsesModes = iTermColorPresetHasModes(preset);
    if (presetUsesModes != [self boolForKey:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE]) {
        return NO;
    }
    for (NSString *colorName in [ProfileModel colorKeysWithModes:presetUsesModes]) {
        iTermColorDictionary *presetColorDict = [preset iterm_presetColorWithName:colorName];
        NSDictionary *profileColorDict = [iTermProfilePreferences objectForKey:colorName
                                                                     inProfile:profile];
        if (![presetColorDict isEqual:profileColorDict] && presetColorDict != profileColorDict) {
            return NO;
        }
    }
    return YES;
}

- (NSDictionary *)currentColors {
    NSMutableDictionary<NSString *, id> *dict = [NSMutableDictionary dictionary];
    for (NSString *key in [ProfileModel colorKeysWithModes:[self boolForKey:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE]]) {
        dict[key] = [self objectForKey:key] ?: [NSNull null];
    }
    return dict;
}

- (void)restoreColors {
    [_savedColors enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        id value = [obj nilIfNull];
        if (![NSObject object:value isEqualToObject:[self objectForKey:key]]) {
            [self setObject:value forKey:key];
        }
    }];
}

// If the current color settings exactly match a preset, place a check mark next to it and uncheck
// all others. If multiple presets match, check the first matching one.
- (void)popupButtonWillPopUp:(id)sender {
    BOOL found = NO;
    iTermColorPresetDictionary *allPresets = [iTermColorPresets allColorPresets];

    _savedColors = [self currentColors];

    for (NSMenuItem *item in _presetsMenu.itemArray) {
        if (item.action == @selector(loadColorPreset:)) {
            NSString *name = item.identifier;
            if (!found && [self currentColorsEqualPreset:allPresets[name]]) {
                item.state = NSControlStateValueOn;
                found = YES;
            } else {
                item.state = NSControlStateValueOff;
            }
        }
    }
}

#pragma mark - NSMenuDelegate

- (void)menu:(NSMenu *)menu willHighlightItem:(nullable NSMenuItem *)item {
    if (item.action == @selector(loadColorPreset:)) {
        [self removeTimer];
        _timer = [NSTimer scheduledTimerWithTimeInterval:0.4 target:self selector:@selector(previewColors:) userInfo:item repeats:NO];
        [[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    } else {
        [self removeTimer];
        [self restoreColors];
    }
}

- (void)previewColors:(NSTimer *)timer {
    NSMenuItem *item = timer.userInfo;
    if (_timer) {
        [self loadColorPresetWithName:item.identifier prompt:NO];
    }
    [self removeTimer];
}
- (void)removeTimer {
    [_timer invalidate];
    _timer = nil;
}

- (void)menuDidClose:(NSMenu *)menu {
    [self removeTimer];
    [self restoreColors];
    _savedColors = nil;
}

#pragma mark - Actions

- (IBAction)modeDidChange:(id)sender {
    for (PreferenceInfo *info in [self.keyMap objectEnumerator]) {
        [self updateValueForInfo:info];
    }
}

- (IBAction)showModeWarning:(id)sender {
    [_modeWarning it_showWarning:@"Your current theme overrides the system light and dark mode setting, so color switching will not occur. You can change it in Settings > Appearance > General > Theme."];
}

#pragma mark - Overrides

- (NSString *)amendedKey:(NSString *)key {
    if ([key isEqualToString:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE]) {
        return key;
    }
    if (_useSeparateColorsForLightAndDarkMode.state == NSControlStateValueOff) {
        return key;
    }
    switch (_mode.selectedTag) {
        case 0:  // Light mode
            return [key stringByAppendingString:COLORS_LIGHT_MODE_SUFFIX];
        case 1:  // Dark mode
            return [key stringByAppendingString:COLORS_DARK_MODE_SUFFIX];
    }
    return key;
}

- (void)setObject:(NSObject *)object forKey:(NSString *)key {
    [super setObject:object forKey:[self amendedKey:key]];
}

- (void)setBool:(BOOL)value forKey:(NSString *)key {
    [super setBool:value forKey:[self amendedKey:key]];
}

- (BOOL)boolForKey:(NSString *)key {
    return [super boolForKey:[self amendedKey:key]];
}

- (void)setFloat:(double)value forKey:(NSString *)key {
    [super setFloat:value forKey:[self amendedKey:key]];
}

- (double)floatForKey:(NSString *)key {
    return [super floatForKey:[self amendedKey:key]];
}

- (NSObject *)objectForKey:(NSString *)key {
    return [super objectForKey:[self amendedKey:key]];
}

#pragma mark - iTermSizeRememberingViewDelegate

- (void)sizeRememberingView:(iTermSizeRememberingView *)sender effectiveAppearanceDidChange:(NSAppearance *)effectiveAppearance {
    const BOOL dark = [NSApp effectiveAppearance].it_isDark;
    [_mode selectItemWithTag:dark ? 1 : 0];
    [self modeDidChange:_mode];
}

@end
