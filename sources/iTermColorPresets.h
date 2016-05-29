#import <Cocoa/Cocoa.h>

#import "ProfileModel.h"

extern NSString *const kCustomColorPresetsKey;
extern NSString *const kRebuildColorPresetsMenuNotification;

@class Profile;
@class ProfileModel;

typedef NSDictionary<NSString *, NSNumber *> iTermColorDictionary;
typedef NSDictionary<NSString *, iTermColorDictionary *> iTermColorPreset;
typedef NSDictionary<NSString *, iTermColorPreset *> iTermColorPresetDictionary;

// This is a model for the color presets that are globally loaded into user defaults. It also
// provides convenience methods for accessing and modifying profiles, exporting profiles, getting a
// color from a preset, and getting the collection of color keys used in a preset.
@interface iTermColorPresets : NSObject

// Loaded presets
+ (iTermColorPresetDictionary *)customColorPresets;

// Factory-supplied presets
+ (iTermColorPresetDictionary *)builtInColorPresets;

// Loook up a loaded preset by name
+ (iTermColorPreset *)presetWithName:(NSString *)presetName;

// Load a preset
+ (BOOL)importColorPresetFromFile:(NSString *)filename;

// Remove a loaded preset
+ (void)deletePresetWithName:(NSString *)name;

@end

@interface NSDictionary(iTermColorPreset)

// Extract a preset from a profile
- (iTermColorDictionary *)iterm_presetColorWithName:(NSString *)colorName;

// Save a preset to disk
- (BOOL)iterm_writePresetToFileWithName:(NSString *)filename;

@end

@interface ProfileModel(iTermColorPresets)

// Keys in a preset dictionary
+ (NSArray<NSString *> *)colorKeys;

// Add a loaded preset to a profile
- (BOOL)addColorPresetNamed:(NSString *)presetName toProfile:(Profile *)profile;

@end
