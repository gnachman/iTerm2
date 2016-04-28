#import <Cocoa/Cocoa.h>

extern NSString *const kCustomColorPresetsKey;
extern NSString *const kRebuildColorPresetsMenuNotification;

@class Profile;
@class ProfileModel;

typedef NSDictionary<NSString *, NSNumber *> iTermColorDictionary;
typedef NSDictionary<NSString *, iTermColorDictionary *> iTermColorPreset;

// This is a model for the color presets that are globally loaded into user defaults. It also
// provides convenience methods for accessing and modifying profiles, exporting profiles, getting a
// color from a preset, and getting the collection of color keys used in a preset.
@interface iTermColorPresets : NSObject

// Loaded presets
+ (NSDictionary<NSString *, iTermColorPreset *> *)customColorPresets;

// Factory-supplied presets
+ (NSDictionary<NSString *, iTermColorPreset *> *)builtInColorPresets;

// Keys in a preset dictionary
+ (NSArray<NSString *> *)colorKeys;

// Loook up a loaded preset by name
+ (iTermColorPreset *)presetWithName:(NSString *)presetName;

// Load a preset
+ (BOOL)importColorPresetFromFile:(NSString *)filename;

// Remove a loaded preset
+ (void)deletePresetWithName:(NSString *)name;

// Add a loaded preset to a profile
+ (BOOL)loadColorPresetWithName:(NSString *)presetName
                      inProfile:(Profile *)profile
                          model:(ProfileModel *)model;

// Extract a preset from a profile
+ (iTermColorDictionary *)colorInPresetDictionary:(iTermColorPreset *)settings
                                         withName:(NSString *)colorName;

// Save a preset to disk
+ (BOOL)writePresets:(iTermColorPreset *)presets toFile:(NSString *)filename;

@end
