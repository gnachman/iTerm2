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

- (BOOL)importColorPresetFromFile:(NSString*)filename;

@end
