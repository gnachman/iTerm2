//
//  ProfilesColorsPreferencesViewController.h
//  iTerm
//
//  Created by George Nachman on 4/14/14.
//
//

#import "iTermProfilePreferencesBaseViewController.h"

extern NSString *const iTermColorPreferencesDidDisappear;
extern NSString *const iTermColorPreferencesDidAppear;

@interface ProfilesColorsPreferencesViewController : iTermProfilePreferencesBaseViewController
+ (NSString *)nameOfPresetUsedByProfile:(Profile *)profile;
@end
