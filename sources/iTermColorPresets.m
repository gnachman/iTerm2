#import "iTermColorPresets.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermProfilePreferences.h"

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

+ (BOOL)importColorPresetFromFile:(NSString *)filename {
    DLog(@"Colors VC importing presets from %@", filename);
    NSDictionary *aDict = [NSDictionary dictionaryWithContentsOfFile:filename];
    if (!aDict) {
        DLog(@"Failed to parse dictionary");
        NSRunAlertPanel(@"Import Failed.",
                        @"The selected file could not be read or did not contain a valid color scheme.",
                        @"OK",
                        nil,
                        nil);
        return NO;
    } else {
        DLog(@"Parsed dictionary ok");
        NSString *dup = [self nameOfPresetsEqualTo:aDict];
        if (dup) {
            DLog(@"Is a duplicate preset");
            NSAlert *alert = [NSAlert alertWithMessageText:@"Add duplicate color preset?"
                                             defaultButton:@"Cancel"
                                           alternateButton:@"Add it anyway"
                                               otherButton:nil
                                 informativeTextWithFormat:@"The color preset “%@” is the same as the preset you're trying to add. Really add it?", dup];
            if ([alert runModal] == NSAlertDefaultReturn) {
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

- (BOOL)addColorPresetNamed:(NSString *)presetName toProfile:(Profile *)profile {
    NSString *guid = profile[KEY_GUID];
    assert(guid);

    iTermColorPreset *settings = [iTermColorPresets presetWithName:presetName];
    if (!settings) {
        return NO;
    }
    NSMutableDictionary* newDict = [NSMutableDictionary dictionaryWithDictionary:profile];

    for (NSString *colorName in [ProfileModel colorKeys]) {
        iTermColorDictionary *colorDict = [settings iterm_presetColorWithName:colorName];
        if (colorDict) {
            newDict[colorName] = colorDict;
        } else {
            [newDict removeObjectForKey:colorName];  // Can happen for tab color, which is optional
        }
    }

    [self setBookmark:newDict withGuid:guid];
    [self flush];

    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles object:nil];
    return YES;
}

@end
