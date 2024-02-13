#import "iTermColorPresets.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermProfilePreferences.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSStringITerm.h"

NSString *const kCustomColorPresetsKey = @"Custom Color Presets";
NSString *const kRebuildColorPresetsMenuNotification = @"kRebuildColorPresetsMenuNotification";

@implementation iTermColorPresets

+ (iTermColorPresetDictionary *)customColorPresets {
    return [[NSUserDefaults standardUserDefaults] objectForKey:kCustomColorPresetsKey];
}

+ (iTermColorPresetDictionary *)builtInColorPresets {
  NSString *plistFile = [[NSBundle bundleForClass:[self class]] pathForResource:@"ColorPresets"
                                                                         ofType:@"plist"];
  return [NSDictionary dictionaryWithContentsOfFile:plistFile];
}

+ (iTermColorPresetDictionary *)allColorPresets {
    return [[self builtInColorPresets] dictionaryByMergingDictionary:[self customColorPresets]];
}

+ (BOOL)importColorPresetFromFile:(NSString *)filename {
    DLog(@"Colors VC importing presets from %@", filename);
    NSDictionary *aDict = [NSDictionary dictionaryWithContentsOfFile:filename];
    if (!aDict) {
        DLog(@"Failed to parse dictionary");
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Import Failed.";
        alert.informativeText = @"The selected file could not be read or did not contain a valid color scheme.";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return NO;
    } else {
        DLog(@"Parsed dictionary ok");
        NSString *dup = [self nameOfPresetsEqualTo:aDict];
        if (dup) {
            DLog(@"Is a duplicate preset");
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Add duplicate color preset?";
            alert.informativeText = [NSString stringWithFormat:@"The color preset “%@” is the same as the preset you're trying to add. Really add it?", dup];
            [alert addButtonWithTitle:@"Cancel"];
            [alert addButtonWithTitle:@"Add it anyway"];
            if ([alert runModal] == NSAlertFirstButtonReturn) {
                DLog(@"User declined to install dup");
                return NO;
            }
        }

        [self addColorPreset:[self presetNameFromFilename:filename]
                  withColors:aDict];
        return YES;
    }
}

+ (void)deletePresetWithName:(NSString *)name {
    NSDictionary* customPresets = [iTermColorPresets customColorPresets];
    NSMutableDictionary* newCustom = [NSMutableDictionary dictionaryWithDictionary:customPresets];
    [newCustom removeObjectForKey:name];
    [[NSUserDefaults standardUserDefaults] setObject:newCustom
                                              forKey:kCustomColorPresetsKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:kRebuildColorPresetsMenuNotification
                                                        object:nil];
}

// Checks built-ins for the name and, failing that, looks in custom presets.
+ (iTermColorPreset *)presetWithName:(NSString *)presetName {
  NSDictionary *presetsDict = [self builtInColorPresets];
  NSDictionary *settings = [presetsDict objectForKey:presetName];
  if (!settings) {
    presetsDict = [self customColorPresets];
    settings = [presetsDict objectForKey:presetName];
  }
  return settings;
}

#pragma mark - Private

+ (NSString *)presetNameFromFilename:(NSString*)filename {
    return [[filename stringByDeletingPathExtension] lastPathComponent];
}

+ (NSString *)nameOfPresetsEqualTo:(NSDictionary *)dict {
    NSDictionary *presets = [[NSUserDefaults standardUserDefaults] objectForKey:kCustomColorPresetsKey];
    for (NSString *name in presets) {
        if ([presets[name] isEqualTo:dict]) {
            return name;
        }
    }
    return nil;
}

+ (void)addColorPreset:(NSString *)presetName withColors:(NSDictionary *)theDict {
    DLog(@"Add color preset with name %@ and dictionary %@", presetName, theDict);
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

@end

@implementation NSDictionary(iTermColorPreset)

// This is an abuse of objectForKey:inProfile:, which expects the second arg to be a profile.
// The preset dictionary looks just enough like a profile for this to work.
- (iTermColorDictionary *)iterm_presetColorWithName:(NSString *)colorName {
  // If the preset is missing an entry, the default color will be used for that entry.
  return [iTermProfilePreferences objectForKey:colorName
                                     inProfile:self];
}


- (BOOL)iterm_writePresetToFileWithName:(NSString *)filename {
    return [self writeToFile:filename atomically:NO];
}

@end

@implementation ProfileModel(iTermColorPresets)

+ (NSArray<NSString *> *)colorKeysWithModes:(BOOL)modes {
    NSArray *keys = @[
        KEY_ANSI_0_COLOR,
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
        KEY_MATCH_COLOR,
        KEY_SELECTION_COLOR,
        KEY_SELECTED_TEXT_COLOR,
        KEY_CURSOR_COLOR,
        KEY_CURSOR_TEXT_COLOR,
        KEY_TAB_COLOR,
        KEY_UNDERLINE_COLOR,
        KEY_CURSOR_GUIDE_COLOR,
        KEY_BADGE_COLOR ];

    if (!modes) {
        return keys;
    }
    return [keys flatMapWithBlock:^NSArray *(NSString *key) {
        return @[ [key stringByAppendingString:COLORS_LIGHT_MODE_SUFFIX],
                  [key stringByAppendingString:COLORS_DARK_MODE_SUFFIX] ];
    }];
}

- (BOOL)presetHasMultipleModes:(NSString *)presetName {
    iTermColorPreset *settings = [iTermColorPresets presetWithName:presetName];
    if (!settings) {
        return NO;
    }
    return iTermColorPresetHasModes(settings);
}

- (BOOL)addColorPresetNamed:(NSString *)presetName toProfile:(Profile *)profile {
    const BOOL presetHasModes = [self presetHasMultipleModes:presetName];
    const iTermColorPresetMode modes = presetHasModes ? (iTermColorPresetModeLight | iTermColorPresetModeDark) : 0;
    return [self addColorPresetNamed:presetName toProfile:profile from:modes to:modes updateUseModes:YES];
}

- (BOOL)addColorPresetNamed:(NSString *)presetName
                  toProfile:(Profile *)profile
                       from:(iTermColorPresetMode)source
                         to:(iTermColorPresetMode)destination {
    return [self addColorPresetNamed:presetName toProfile:profile from:source to:destination updateUseModes:NO];
}

- (BOOL)addColorPresetNamed:(NSString *)presetName
                  toProfile:(Profile *)profile
                       from:(iTermColorPresetMode)source
                         to:(iTermColorPresetMode)destination
             updateUseModes:(BOOL)updateUseModes {
    NSString *guid = profile[KEY_GUID];
    assert(guid);

    iTermColorPreset *settings = [iTermColorPresets presetWithName:presetName];
    if (!settings) {
        return NO;
    }
    NSMutableDictionary* newDict = [NSMutableDictionary dictionaryWithDictionary:profile];

    const BOOL presetUsesModes = iTermColorPresetHasModes(settings);
    NSArray<NSString *> *suffixesToSet = @[];   // Suffixes we write to.
    NSArray<NSString *> *suffixesToSkip = @[];  // Suffixes on input that we ignore.
    if (!presetUsesModes) {
        if (source != 0) {
            return [self addColorPresetNamed:presetName toProfile:profile from:0 to:destination];
        }
        suffixesToSkip = @[ COLORS_LIGHT_MODE_SUFFIX, COLORS_DARK_MODE_SUFFIX ];
    } else {
        // Preset has light & dark mode
        if (source == 0) {
            suffixesToSkip = @[ COLORS_LIGHT_MODE_SUFFIX, COLORS_DARK_MODE_SUFFIX ];
        } else if (source == iTermColorPresetModeLight) {
            suffixesToSkip = @[ @"", COLORS_DARK_MODE_SUFFIX ];
        } else if (source == iTermColorPresetModeDark) {
            suffixesToSkip = @[ @"", COLORS_LIGHT_MODE_SUFFIX ];
        } else {
            suffixesToSkip = @[ @"" ];
        }
    }

    if (destination == 0) {
        suffixesToSet = @[ @"" ];
    }
    if (destination & iTermColorPresetModeLight) {
        suffixesToSet = [suffixesToSet arrayByAddingObject:COLORS_LIGHT_MODE_SUFFIX];
    }
    if (destination & iTermColorPresetModeDark) {
        suffixesToSet = [suffixesToSet arrayByAddingObject:COLORS_DARK_MODE_SUFFIX];
    }

    for (NSString *colorName in [ProfileModel colorKeysWithModes:presetUsesModes]) {
        // Check if this key in the preset should be skipped.
        NSString *colorNameSuffix = @"";
        NSString *baseColorName = colorName;
        for (NSString *candidate in @[ COLORS_LIGHT_MODE_SUFFIX, COLORS_DARK_MODE_SUFFIX ]) {
            if ([colorName hasSuffix:candidate]) {
                baseColorName = [colorName stringByDroppingLastCharacters:candidate.length];
                colorNameSuffix = candidate;
                break;
            }
        }
        if ([suffixesToSkip containsObject:colorNameSuffix]) {
            continue;
        }

        // Fan out the value to the profile.
        iTermColorDictionary *colorDict = [settings iterm_presetColorWithName:colorName];
        for (NSString *suffix in suffixesToSet) {
            NSString *key = [baseColorName stringByAppendingString:suffix];
            if (colorDict) {
                newDict[key] = colorDict;
            } else {
                [newDict removeObjectForKey:key];  // Can happen for tab color, match color, and underline color, which are optional
            }
        }
    }

    if (updateUseModes) {
        newDict[KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE] = (destination == 0) ? @NO : @YES;
    }

    [self setBookmark:newDict withGuid:guid];
    [self flush];

    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles object:nil];
    return YES;
}

@end

BOOL iTermColorPresetHasModes(iTermColorPreset *preset) {
    return preset[KEY_FOREGROUND_COLOR COLORS_LIGHT_MODE_SUFFIX] != nil;
}

NSColor *iTermColorPresetGet(iTermColorPreset *preset, NSString *baseKey, BOOL dark) {
    if (!iTermColorPresetHasModes(preset)) {
        return [preset[baseKey] colorValue];
    }
    NSString *key;
    if (dark) {
        key = [baseKey stringByAppendingString:COLORS_DARK_MODE_SUFFIX];
    } else {
        key = [baseKey stringByAppendingString:COLORS_LIGHT_MODE_SUFFIX];
    }
    return [preset[key] colorValue] ?: [preset[baseKey] colorValue];
}
