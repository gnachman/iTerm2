//
//  ProfilesColorsPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/14/14.
//
//

#import "ProfilesColorsPreferencesViewController.h"
#import "ITAddressBookMgr.h"
#import "iTermProfilePreferences.h"
#import "NSColor+iTerm.h"
#import "NSTextField+iTerm.h"
#import "PreferencePanel.h"

NSString *const kCustomColorPresetsKey = @"Custom Color Presets";
static NSString *const kRebuildColorPresetsMenuNotification = @"kRebuildColorPresetsMenuNotification";
static NSString * const kColorGalleryURL = @"https://www.iterm2.com/colorgallery";

@implementation ProfilesColorsPreferencesViewController {
    IBOutlet NSColorWell *_ansi0Color;
    IBOutlet NSColorWell *_ansi1Color;
    IBOutlet NSColorWell *_ansi2Color;
    IBOutlet NSColorWell *_ansi3Color;
    IBOutlet NSColorWell *_ansi4Color;
    IBOutlet NSColorWell *_ansi5Color;
    IBOutlet NSColorWell *_ansi6Color;
    IBOutlet NSColorWell *_ansi7Color;
    IBOutlet NSColorWell *_ansi8Color;
    IBOutlet NSColorWell *_ansi9Color;
    IBOutlet NSColorWell *_ansi10Color;
    IBOutlet NSColorWell *_ansi11Color;
    IBOutlet NSColorWell *_ansi12Color;
    IBOutlet NSColorWell *_ansi13Color;
    IBOutlet NSColorWell *_ansi14Color;
    IBOutlet NSColorWell *_ansi15Color;
    IBOutlet NSColorWell *_foregroundColor;
    IBOutlet NSColorWell *_backgroundColor;
    IBOutlet NSColorWell *_boldColor;
    IBOutlet NSColorWell *_linkColor;
    IBOutlet NSColorWell *_selectionColor;
    IBOutlet NSColorWell *_selectedTextColor;
    IBOutlet NSColorWell *_cursorColor;
    IBOutlet NSColorWell *_cursorTextColor;
    IBOutlet NSColorWell *_tabColor;
    IBOutlet NSColorWell *_badgeColor;

    IBOutlet NSTextField *_cursorColorLabel;
    IBOutlet NSTextField *_cursorTextColorLabel;

    IBOutlet NSButton *_useTabColor;
    IBOutlet NSButton *_useSmartCursorColor;

    IBOutlet NSSlider *_minimumContrast;
    IBOutlet NSSlider *_cursorBoost;

    IBOutlet NSMenu *_presetsMenu;

    IBOutlet NSButton *_useGuide;
    IBOutlet NSColorWell *_guideColor;

    IBOutlet NSPopUpButton *_presetsPopupButton;
}

+ (NSDictionary *)builtInColorPresets {
    NSString *plistFile = [[NSBundle bundleForClass:[self class]] pathForResource:@"ColorPresets"
                                                                           ofType:@"plist"];
    return [NSDictionary dictionaryWithContentsOfFile:plistFile];
}

+ (NSDictionary *)customColorPresets {
    return [[NSUserDefaults standardUserDefaults] objectForKey:kCustomColorPresetsKey];
}

// Checks built-ins for the name and, failing that, looks in custom presets.
+ (NSDictionary *)presetWithName:(NSString *)presetName {
    NSDictionary *presetsDict = [self builtInColorPresets];
    NSDictionary *settings = [presetsDict objectForKey:presetName];
    if (!settings) {
        presetsDict = [self customColorPresets];
        settings = [presetsDict objectForKey:presetName];
    }
    return settings;
}

// This is an abuse of objectForKey:inProfile:, which expects the second arg to be a profile.
// The preset dictionary looks just enough like a profile for this to work.
+ (NSDictionary *)colorInPresetDictionary:(NSDictionary *)settings withName:(NSString *)colorName {
  // If the preset is missing an entry, the default color will be used for that entry.
  return [iTermProfilePreferences objectForKey:colorName
                                     inProfile:settings];
}

+ (BOOL)loadColorPresetWithName:(NSString *)presetName
                      inProfile:(Profile *)profile
                          model:(ProfileModel *)model {
    NSString *guid = profile[KEY_GUID];
    assert(guid);

    NSDictionary *settings = [self presetWithName:presetName];
    if (!settings) {
        return NO;
    }
    NSMutableDictionary* newDict = [NSMutableDictionary dictionaryWithDictionary:profile];

    for (NSString *colorName in [self colorKeys]) {
      NSDictionary *colorDict = [self colorInPresetDictionary:settings withName:colorName];
        if (colorDict) {
            newDict[colorName] = colorDict;
        } else {
            [newDict removeObjectForKey:colorName];  // Can happen for tab color, which is optional
        }
    }

    [model setBookmark:newDict withGuid:guid];
    [model flush];

    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles object:nil];
    return YES;
}

- (void)awakeFromNib {
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

    // Add presets to preset color selection.
    [self rebuildColorPresetsMenu];

    NSDictionary *colorWellDictionary = [self colorWellDictionary];
    for (NSString *key in colorWellDictionary) {
        [self defineControl:colorWellDictionary[key] key:key type:kPreferenceInfoTypeColorWell];
    }

    PreferenceInfo *info;

    info = [self defineControl:_useTabColor
                           key:KEY_USE_TAB_COLOR
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^() { [self updateColorControlsEnabled]; };

    info = [self defineControl:_useSmartCursorColor
                           key:KEY_SMART_CURSOR_COLOR
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^() { [self updateColorControlsEnabled]; };

    [self defineControl:_minimumContrast
                    key:KEY_MINIMUM_CONTRAST
                   type:kPreferenceInfoTypeSlider];

    [self defineControl:_cursorBoost
                    key:KEY_CURSOR_BOOST
                   type:kPreferenceInfoTypeSlider];

    [self defineControl:_useGuide
                    key:KEY_USE_CURSOR_GUIDE
                   type:kPreferenceInfoTypeCheckbox];

    [self updateColorControlsEnabled];
}

- (void)updateColorControlsEnabled {
    _tabColor.enabled = [self boolForKey:KEY_USE_TAB_COLOR];
    _cursorColor.enabled = ![self boolForKey:KEY_SMART_CURSOR_COLOR];
    _cursorTextColor.enabled = ![self boolForKey:KEY_SMART_CURSOR_COLOR];
    _cursorColorLabel.labelEnabled = ![self boolForKey:KEY_SMART_CURSOR_COLOR];
    _cursorTextColorLabel.labelEnabled = ![self boolForKey:KEY_SMART_CURSOR_COLOR];
}

+ (NSArray *)colorKeys {
    return @[ KEY_ANSI_0_COLOR,
              KEY_ANSI_1_COLOR,
              KEY_ANSI_2_COLOR,
              KEY_ANSI_3_COLOR,
              KEY_ANSI_4_COLOR,
              KEY_ANSI_5_COLOR,
              KEY_ANSI_6_COLOR,
              KEY_ANSI_7_COLOR,
              KEY_ANSI_8_COLOR,
              KEY_ANSI_9_COLOR,
              KEY_ANSI_10_COLOR,
              KEY_ANSI_11_COLOR,
              KEY_ANSI_12_COLOR,
              KEY_ANSI_13_COLOR,
              KEY_ANSI_14_COLOR,
              KEY_ANSI_15_COLOR,
              KEY_FOREGROUND_COLOR,
              KEY_BACKGROUND_COLOR,
              KEY_BOLD_COLOR,
              KEY_LINK_COLOR,
              KEY_SELECTION_COLOR,
              KEY_SELECTED_TEXT_COLOR,
              KEY_CURSOR_COLOR,
              KEY_CURSOR_TEXT_COLOR,
              KEY_TAB_COLOR,
              KEY_CURSOR_GUIDE_COLOR,
              KEY_BADGE_COLOR ];
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
              KEY_SELECTION_COLOR: _selectionColor,
              KEY_SELECTED_TEXT_COLOR: _selectedTextColor,
              KEY_CURSOR_COLOR: _cursorColor,
              KEY_CURSOR_TEXT_COLOR: _cursorTextColor,
              KEY_TAB_COLOR: _tabColor,
              KEY_CURSOR_GUIDE_COLOR: _guideColor,
              KEY_BADGE_COLOR: _badgeColor };
}

#pragma mark - Color Presets

- (void)rebuildColorPresetsMenu {
    while ([_presetsMenu numberOfItems] > 1) {
        [_presetsMenu removeItemAtIndex:1];
    }

    NSString* plistFile = [[NSBundle bundleForClass: [self class]] pathForResource:@"ColorPresets"
                                                                            ofType:@"plist"];
    NSDictionary* presetsDict = [NSDictionary dictionaryWithContentsOfFile:plistFile];
    [self addColorPresetsInDict:presetsDict toMenu:_presetsMenu];

    NSDictionary* customPresets = [[NSUserDefaults standardUserDefaults] objectForKey:kCustomColorPresetsKey];
    if (customPresets && [customPresets count] > 0) {
        [_presetsMenu addItem:[NSMenuItem separatorItem]];
        [self addColorPresetsInDict:customPresets toMenu:_presetsMenu];
    }

    [_presetsMenu addItem:[NSMenuItem separatorItem]];

    [self addPresetItemWithTitle:@"Import..." action:@selector(importColorPreset:)];
    [self addPresetItemWithTitle:@"Export..." action:@selector(exportColorPreset:)];
    [self addPresetItemWithTitle:@"Delete Preset..." action:@selector(deleteColorPreset:)];
    [self addPresetItemWithTitle:@"Visit Online Gallery" action:@selector(visitGallery:)];
}

- (void)addPresetItemWithTitle:(NSString *)title action:(SEL)action {
    NSMenuItem *item = [_presetsMenu addItemWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
}

- (void)addColorPresetsInDict:(NSDictionary*)presetsDict toMenu:(NSMenu*)theMenu {
    for (NSString* key in  [[presetsDict allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        NSMenuItem* presetItem = [[NSMenuItem alloc] initWithTitle:key
                                                            action:@selector(loadColorPreset:)
                                                     keyEquivalent:@""];
        presetItem.target = self;
        [theMenu addItem:presetItem];
        [presetItem release];
    }
}

- (NSString*)presetNameFromFilename:(NSString*)filename {
    return [[filename stringByDeletingPathExtension] lastPathComponent];
}

- (void)addColorPreset:(NSString*)presetName withColors:(NSDictionary*)theDict {
    NSDictionary *presets = [[NSUserDefaults standardUserDefaults] objectForKey:kCustomColorPresetsKey];
    NSMutableDictionary* customPresets = [NSMutableDictionary dictionaryWithDictionary:presets];
    if (!customPresets) {
        customPresets = [NSMutableDictionary dictionaryWithCapacity:1];
    }
    int i = 1;
    NSString* temp = presetName;
    while ([customPresets objectForKey:temp]) {
        ++i;
        temp = [NSString stringWithFormat:@"%@ (%d)", presetName, i];
    }
    [customPresets setObject:theDict forKey:temp];
    [[NSUserDefaults standardUserDefaults] setObject:customPresets forKey:kCustomColorPresetsKey];

    [[NSNotificationCenter defaultCenter] postNotificationName:kRebuildColorPresetsMenuNotification
                                                        object:nil];
}

- (NSString *)nameOfPresetsEqualTo:(NSDictionary *)dict {
    NSDictionary *presets = [[NSUserDefaults standardUserDefaults] objectForKey:kCustomColorPresetsKey];
    for (NSString *name in presets) {
        if ([presets[name] isEqualTo:dict]) {
            return name;
        }
    }
    return nil;
}

- (BOOL)importColorPresetFromFile:(NSString*)filename {
    NSDictionary* aDict = [NSDictionary dictionaryWithContentsOfFile:filename];
    if (!aDict) {
        NSRunAlertPanel(@"Import Failed.",
                        @"The selected file could not be read or did not contain a valid color scheme.",
                        @"OK",
                        nil,
                        nil);
        return NO;
    } else {
        NSString *dup = [self nameOfPresetsEqualTo:aDict];
        if (dup) {
            NSAlert *alert = [NSAlert alertWithMessageText:@"Add duplicate color preset?"
                                             defaultButton:@"Cancel"
                                           alternateButton:@"Add it anyway"
                                               otherButton:nil
                                 informativeTextWithFormat:@"The color preset “%@” is the same as the preset you're trying to add. Really add it?", dup];
            if ([alert runModal] == NSAlertDefaultReturn) {
                return NO;
            }
        }

        [self addColorPreset:[self presetNameFromFilename:filename]
                  withColors:aDict];
        return YES;
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
    if ([openPanel legacyRunModalForDirectory:nil file:nil] == NSOKButton) {
        // Get an array containing the full filenames of all
        // files and directories selected.
        for (NSString* filename in [openPanel legacyFilenames]) {
            [self importColorPresetFromFile:filename];
        }
    }
}

- (void)exportColorPreset:(id)sender {
    // Create the File Open Dialog class.
    NSSavePanel *savePanel = [NSSavePanel savePanel];

    // Set options.
    [savePanel setAllowedFileTypes:[NSArray arrayWithObject:@"itermcolors"]];

    if ([savePanel legacyRunModalForDirectory:nil file:nil] == NSOKButton) {
        [self exportColorPresetToFile:[savePanel legacyFilename]];
    }
}

- (void)deleteColorPreset:(id)sender {
    NSDictionary* customPresets =
        [[NSUserDefaults standardUserDefaults] objectForKey:kCustomColorPresetsKey];
    if (!customPresets || [customPresets count] == 0) {
        NSRunAlertPanel(@"No deletable color presets.",
                        @"You cannot erase the built-in presets and no custom presets have been imported.",
                        @"OK",
                        nil,
                        nil);
        return;
    }

    NSAlert *alert = [NSAlert alertWithMessageText:@"Select a preset to delete:"
                                     defaultButton:@"OK"
                                   alternateButton:@"Cancel"
                                       otherButton:nil
                         informativeTextWithFormat:@""];

    NSPopUpButton* pub = [[[NSPopUpButton alloc] init] autorelease];
    for (NSString* key in [[customPresets allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        [pub addItemWithTitle:key];
    }
    [pub sizeToFit];
    [alert setAccessoryView:pub];
    NSInteger button = [alert runModal];
    if (button == NSAlertDefaultReturn) {
        NSMutableDictionary* newCustom = [NSMutableDictionary dictionaryWithDictionary:customPresets];
        [newCustom removeObjectForKey:[[pub selectedItem] title]];
        [[NSUserDefaults standardUserDefaults] setObject:newCustom
                                                  forKey:kCustomColorPresetsKey];
        [[NSNotificationCenter defaultCenter] postNotificationName:kRebuildColorPresetsMenuNotification
                                                            object:nil];
    }
}

- (void)exportColorPresetToFile:(NSString*)filename {
    NSMutableDictionary* theDict = [NSMutableDictionary dictionaryWithCapacity:24];
    NSDictionary *colorWellDictionary = [self colorWellDictionary];
    for (NSString *key in colorWellDictionary) {
        theDict[key] = [[colorWellDictionary[key] color] dictionaryValue];
    }
    if (![theDict writeToFile:filename atomically:NO]) {
        NSRunAlertPanel(@"Save Failed.",
                        @"Could not save to %@",
                        @"OK",
                        nil,
                        nil,
                        filename);
    }
}

- (void)loadColorPresetWithName:(NSString *)presetName {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [self.delegate profilePreferencesCurrentModel];
    [[self class] loadColorPresetWithName:presetName inProfile:profile model:model];
}

- (void)loadColorPreset:(id)sender {
    [self loadColorPresetWithName:[sender title]];
}

- (void)visitGallery:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kColorGalleryURL]];
}

- (BOOL)currentColorsEqualPreset:(NSDictionary *)preset {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    for (NSString *colorName in [self.class colorKeys]) {
        NSDictionary *presetColorDict = [self.class colorInPresetDictionary:preset
                                                                   withName:colorName];
        NSDictionary *profileColorDict = [iTermProfilePreferences objectForKey:colorName
                                                                     inProfile:profile];
        if (![presetColorDict isEqual:profileColorDict] && presetColorDict != profileColorDict) {
            return NO;
        }
    }
    return YES;
}

// If the current color settings exactly match a preset, place a check mark next to it and uncheck
// all others. If multiple presets match, check the first matching one.
- (void)popupButtonWillPopUp:(id)sender {
    BOOL found = NO;
    for (NSMenuItem *item in _presetsMenu.itemArray) {
        if (item.action == @selector(loadColorPreset:)) {
            NSString *name = item.title;
            if (!found && [self currentColorsEqualPreset:[self.class presetWithName:name]]) {
                item.state = NSOnState;
                found = YES;
            } else {
                item.state = NSOffState;
            }
        }
    }
}

@end
