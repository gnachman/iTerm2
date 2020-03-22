//
//  iTermPresetKeyMappings.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/21/20.
//

#import "iTermPresetKeyMappings.h"

#import "ITAddressBookMgr.h"
#import "iTermKeyMappings.h"
#import "iTermKeystroke.h"
#import "iTermTuple.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "ProfileModel.h"

static NSString *const kFactoryDefaultsGlobalPreset = @"Factory Defaults";

@implementation iTermPresetKeyMappings

+ (NSDictionary *)readPresetKeyMappingsFromPlist:(NSString *)thePlist {
    NSString *plistFile = [[NSBundle bundleForClass:[self class]] pathForResource:thePlist
                                                                           ofType:@"plist"];
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:plistFile];
    return dict;
}

+ (NSDictionary *)builtInPresetKeyMappings {
    return [self readPresetKeyMappingsFromPlist:@"PresetKeyMappings"];
}

+ (NSArray<iTermTuple<iTermKeystroke *, iTermKeyBindingAction *> *> *)keystrokeTuplesInAllPresets {
    NSMutableArray<iTermTuple<iTermKeystroke *, iTermKeyBindingAction *> *> *result = [NSMutableArray array];

    NSDictionary *builtins = [self builtInPresetKeyMappings];
    for (NSString *name in builtins) {
        NSDictionary<id, NSDictionary *> *dict = builtins[name];
        [dict enumerateKeysAndObjectsUsingBlock:^(id _Nonnull serializedKeystroke,
                                                  NSDictionary * _Nonnull mapping,
                                                  BOOL * _Nonnull stop) {
            iTermKeystroke *keystroke = [[iTermKeystroke alloc] initWithSerialized:serializedKeystroke];
            if (!keystroke) {
                return;
            }
            iTermKeyBindingAction *action = [iTermKeyBindingAction withDictionary:mapping];
            if (!action) {
                return;
            }
            [result addObject:[iTermTuple tupleWithObject:keystroke andObject:action]];
        }];
    }
    return result;
}

+ (NSArray *)globalPresetNames {
    return @[ kFactoryDefaultsGlobalPreset ];
}

+ (NSArray<NSString *> *)presetKeyMappingsNames {
    NSDictionary *presetsDict = [self builtInPresetKeyMappings];
    return [presetsDict allKeys];
}

+ (Profile *)profileByLoadingPresetNamed:(NSString *)presetName
                             intoProfile:(Profile *)sourceProfile
                          byReplacingAll:(BOOL)replaceAll {
    NSDictionary *presetsDict = [self builtInPresetKeyMappings];
    NSDictionary *preset = presetsDict[presetName];
    if (replaceAll) {
        return [sourceProfile dictionaryBySettingObject:preset forKey:KEY_KEYBOARD_MAP];
    }
    NSDictionary *sourceMap = sourceProfile[KEY_KEYBOARD_MAP] ?: @{};
    NSDictionary *updated = [sourceMap it_dictionaryByMergingSerializedKeystrokeKeyedDictionary:preset];
    return [sourceProfile dictionaryBySettingObject:updated forKey:KEY_KEYBOARD_MAP];
}

+ (NSSet<iTermKeystroke *> *)keystrokesInKeyMappingPresetWithName:(NSString *)presetName {
    NSDictionary *presetsDict = [self builtInPresetKeyMappings];
    NSDictionary *preset = presetsDict[presetName];
    NSArray *keys = preset.allKeys;
    NSArray *keystrokes = [keys mapWithBlock:^id(id anObject) {
        return [[iTermKeystroke alloc] initWithSerialized:anObject];
    }];
    return [NSSet setWithArray:keystrokes];
}

+ (void)setGlobalKeyMappingsToPreset:(NSString *)presetName byReplacingAll:(BOOL)replaceAll {
    assert([presetName isEqualToString:kFactoryDefaultsGlobalPreset]);
    if (![iTermKeyMappings haveLoadedKeyMappings]) {
        [iTermKeyMappings loadGlobalKeyMap];
        return;
    }
    if (!replaceAll) {
        NSDictionary *globalKeyMap = [iTermKeyMappings globalKeyMap];
        globalKeyMap = [globalKeyMap it_dictionaryByMergingSerializedKeystrokeKeyedDictionary:self.defaultGlobalKeyMap];
        [iTermKeyMappings setGlobalKeyMap:globalKeyMap];
        return;
    }

    [iTermKeyMappings setGlobalKeyMap:[self defaultGlobalKeyMap]];
}

+ (NSDictionary *)defaultGlobalKeyMap {
    NSString *plistFile = [[NSBundle bundleForClass:[self class]] pathForResource:@"DefaultGlobalKeyMap" ofType:@"plist"];
    return [NSDictionary dictionaryWithContentsOfFile:plistFile];
}

+ (NSSet<iTermKeystroke *> *)keystrokesInGlobalPreset:(NSString *)presetName {
    return [NSSet setWithArray:[self.defaultGlobalKeyMap.allKeys mapWithBlock:^id(id anObject) {
        return [[iTermKeystroke alloc] initWithSerialized:anObject];
    }]];
}

@end
