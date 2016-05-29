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
#import "iTermProfilePreferences.h"
#import "NSColor+iTerm.h"
#import "NSTextField+iTerm.h"
#import "PreferencePanel.h"

#import <ColorPicker/ColorPicker.h>

static NSString * const kColorGalleryURL = @"https://www.iterm2.com/colorgallery";

@implementation ProfilesColorsPreferencesViewController {
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
    IBOutlet CPKColorWell *_boldColor;
    IBOutlet CPKColorWell *_linkColor;
    IBOutlet CPKColorWell *_selectionColor;
    IBOutlet CPKColorWell *_selectedTextColor;
    IBOutlet CPKColorWell *_cursorColor;
    IBOutlet CPKColorWell *_cursorTextColor;
    IBOutlet CPKColorWell *_tabColor;
    IBOutlet CPKColorWell *_badgeColor;

    IBOutlet NSTextField *_cursorColorLabel;
    IBOutlet NSTextField *_cursorTextColorLabel;

    IBOutlet NSButton *_useTabColor;
    IBOutlet NSButton *_useSmartCursorColor;

    IBOutlet NSSlider *_minimumContrast;
    IBOutlet NSSlider *_cursorBoost;

    IBOutlet NSMenu *_presetsMenu;

    IBOutlet NSButton *_useGuide;
    IBOutlet CPKColorWell *_guideColor;

    IBOutlet NSPopUpButton *_presetsPopupButton;
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
        CPKColorWell *colorWell = colorWellDictionary[key];
        [self defineControl:colorWell key:key type:kPreferenceInfoTypeColorWell];
        colorWell.action = @selector(settingChanged:);
        colorWell.target = self;
        colorWell.continuous = YES;
        colorWell.willClosePopover = ^() {
            // NSSearchField remembers who was first responder before it gained
            // first responder status. That is the popover at this time. When
            // the app becomes inactive, the search field makes the previous
            // first responder the new first responder. The search field is not
            // smart and doesn't realize the popover has been deallocated. So
            // this changes its conception of who was the previous first
            // responder and prevents the crash.
            [self.view.window makeFirstResponder:nil];
        };
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
}

- (void)addPresetItemWithTitle:(NSString *)title action:(SEL)action {
    NSMenuItem *item = [_presetsMenu addItemWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
}

- (void)addColorPresetsInDict:(iTermColorPresetDictionary *)presetsDict toMenu:(NSMenu *)theMenu {
    for (NSString* key in  [[presetsDict allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        NSMenuItem* presetItem = [[NSMenuItem alloc] initWithTitle:key
                                                            action:@selector(loadColorPreset:)
                                                     keyEquivalent:@""];
        presetItem.target = self;
        [theMenu addItem:presetItem];
        [presetItem release];
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
            [iTermColorPresets importColorPresetFromFile:filename];
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
    iTermColorPresetDictionary *customPresets = [iTermColorPresets customColorPresets];
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

    NSPopUpButton *popUpButton = [[[NSPopUpButton alloc] init] autorelease];
    for (NSString *key in [[customPresets allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        [popUpButton addItemWithTitle:key];
    }
    [popUpButton sizeToFit];
    [alert setAccessoryView:popUpButton];
    NSInteger button = [alert runModal];
    if (button == NSAlertDefaultReturn) {
        [iTermColorPresets deletePresetWithName:[[popUpButton selectedItem] title]];
    }
}

- (void)exportColorPresetToFile:(NSString*)filename {
    NSMutableDictionary* theDict = [NSMutableDictionary dictionaryWithCapacity:24];
    NSDictionary *colorWellDictionary = [self colorWellDictionary];
    for (NSString *key in colorWellDictionary) {
        theDict[key] = [[colorWellDictionary[key] color] dictionaryValue];
    }
    if (![theDict iterm_writePresetToFileWithName:filename]) {
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
    [model addColorPresetNamed:presetName toProfile:profile];
}

- (void)loadColorPreset:(id)sender {
    [self loadColorPresetWithName:[sender title]];
}

- (void)visitGallery:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kColorGalleryURL]];
}

- (BOOL)currentColorsEqualPreset:(NSDictionary *)preset {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    for (NSString *colorName in [ProfileModel colorKeys]) {
        iTermColorDictionary *presetColorDict = [preset iterm_presetColorWithName:colorName];
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
            if (!found && [self currentColorsEqualPreset:[iTermColorPresets presetWithName:name]]) {
                item.state = NSOnState;
                found = YES;
            } else {
                item.state = NSOffState;
            }
        }
    }
}

@end
