//
//  iTermPresetKeyMappings.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/21/20.
//

#import <Foundation/Foundation.h>

#import "iTermTuple.h"
#import "ProfileModel.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermKeyBindingAction;
@class iTermKeystroke;

@interface iTermPresetKeyMappings : NSObject

// load an xml plist with the given filename, and return it in dictionary
// format.
+ (NSDictionary *)readPresetKeyMappingsFromPlist:(NSString *)thePlist;

+ (NSDictionary *)builtInPresetKeyMappings;

+ (NSArray<iTermTuple<iTermKeystroke *, iTermKeyBindingAction *> *> *)keystrokeTuplesInAllPresets;

+ (NSArray *)globalPresetNames;

// Return an array containing the names of all the presets available in
// the PresetKeyMapping.plist file
+ (NSArray *)presetKeyMappingsNames;

// Load a set of preset keymappings from PresetKeyMappings.plist into the
// specified bookmarks, removing all of its previous mappings.
+ (Profile *)profileByLoadingPresetNamed:(NSString *)presetName
                             intoProfile:(Profile *)sourceProfile
                          byReplacingAll:(BOOL)replaceAll;
+ (NSSet<iTermKeystroke *> *)keystrokesInKeyMappingPresetWithName:(NSString *)presetName;

// Load a set of preset keymappings from GlobalKeyMap.plist into the global
// keymappings, removing all previous mappings.
+ (void)setGlobalKeyMappingsToPreset:(NSString *)presetName byReplacingAll:(BOOL)replaceAll;

+ (NSSet<iTermKeystroke *> *)keystrokesInGlobalPreset:(NSString *)presetName;

+ (NSDictionary *)defaultGlobalKeyMap;

@end

NS_ASSUME_NONNULL_END
