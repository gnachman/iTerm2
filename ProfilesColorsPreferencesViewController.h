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

// This shouldn't remain public for long
- (void)exportColorPresetToFile:(NSString*)filename;
- (void)loadColorPresetWithName:(NSString *)presetName;

@end
