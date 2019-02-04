//
//  ProfilesSessionViewController.h
//  iTerm
//
//  Created by George Nachman on 4/18/14.
//
//

#import "iTermProfilePreferencesBaseViewController.h"

@interface ProfilesSessionPreferencesViewController : iTermProfilePreferencesBaseViewController

- (void)layoutSubviewsForEditCurrentSessionMode;
- (void)configureStatusBarComponentWithIdentifier:(NSString *)identifier;

@end
