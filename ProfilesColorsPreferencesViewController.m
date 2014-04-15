//
//  ProfilesColorsPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/14/14.
//
//

#import "ProfilesColorsPreferencesViewController.h"
#import "ITAddressBookMgr.h"
#import "NSColor+iTerm.h"
#import "PreferencePanel.h"

NSString *const kCustomColorPresetsKey = @"Custom Color Presets";

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
    IBOutlet NSColorWell *_selectionColor;
    IBOutlet NSColorWell *_selectedTextColor;
    IBOutlet NSColorWell *_cursorColor;
    IBOutlet NSColorWell *_cursorTextColor;
    IBOutlet NSColorWell *_tabColor;

    IBOutlet NSButton *_useTabColor;
    IBOutlet NSButton *_useSmartCursorColor;
}

- (void)awakeFromNib {
    // Updates fields when a preset is loaded.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProfile)
                                                 name:kReloadAllProfiles
                                               object:nil];
    
    NSDictionary *colorWellDictionary = [self colorWellDictionary];
    for (NSString *key in colorWellDictionary) {
        [self defineControl:colorWellDictionary[key] key:key type:kPreferenceInfoTypeColorWell];
    }
    
    PreferenceInfo *info;
    
    info = [self defineControl:_useTabColor
                           key:KEY_USE_TAB_COLOR
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self updateColorControlsEnabled]; };

    info = [self defineControl:_useSmartCursorColor
                           key:KEY_SMART_CURSOR_COLOR
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self updateColorControlsEnabled]; };
    
    [self updateColorControlsEnabled];
}

- (void)updateColorControlsEnabled {
    _tabColor.enabled = [self boolForKey:KEY_USE_TAB_COLOR];
    _cursorColor.enabled = ![self boolForKey:KEY_SMART_CURSOR_COLOR];
    _cursorTextColor.enabled = ![self boolForKey:KEY_SMART_CURSOR_COLOR];
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
              KEY_SELECTION_COLOR: _selectionColor,
              KEY_SELECTED_TEXT_COLOR: _selectedTextColor,
              KEY_CURSOR_COLOR: _cursorColor,
              KEY_CURSOR_TEXT_COLOR: _cursorTextColor,
              KEY_TAB_COLOR: _tabColor };
}

#pragma mark - Color Presets

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
    NSString *guid = profile[KEY_GUID];
    assert(guid);
    
    NSString *plistFile = [[NSBundle bundleForClass:[self class]] pathForResource:@"ColorPresets"
                                                                           ofType:@"plist"];
    NSDictionary* presetsDict = [NSDictionary dictionaryWithContentsOfFile:plistFile];
    NSDictionary* settings = [presetsDict objectForKey:presetName];
    if (!settings) {
        presetsDict = [[NSUserDefaults standardUserDefaults] objectForKey:kCustomColorPresetsKey];
        settings = [presetsDict objectForKey:presetName];
    }
    NSMutableDictionary* newDict = [NSMutableDictionary dictionaryWithDictionary:profile];
    
    for (id colorName in settings) {
        NSDictionary* preset = [settings objectForKey:colorName];
        NSColor* color = [ITAddressBookMgr decodeColor:preset];
        NSAssert([newDict objectForKey:colorName], @"Missing color in existing dict");
        [newDict setObject:[ITAddressBookMgr encodeColor:color] forKey:colorName];
    }
    
    ProfileModel *model = [self.delegate profilePreferencesCurrentModel];
    [model setBookmark:newDict withGuid:guid];
    [model flush];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles object:nil];
}

@end
