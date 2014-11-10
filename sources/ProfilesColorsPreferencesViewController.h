//
//  ProfilesColorsPreferencesViewController.h
//  iTerm
//
//  Created by George Nachman on 4/14/14.
//
//

#import "iTermProfilePreferencesBaseViewController.h"

extern NSString *const kCustomColorPresetsKey;

@interface ProfilesColorsPreferencesViewController : iTermProfilePreferencesBaseViewController

// Returns the dictionary of built-in color presets.
+ (NSDictionary *)builtInColorPresets;

// Returns the dictionary of user-loaded color presets.
+ (NSDictionary *)customColorPresets;

// Load a named color preset into a given profile and model.
+ (BOOL)loadColorPresetWithName:(NSString *)presetName
                      inProfile:(Profile *)profile
                          model:(ProfileModel *)model;

- (BOOL)importColorPresetFromFile:(NSString*)filename;

@end
