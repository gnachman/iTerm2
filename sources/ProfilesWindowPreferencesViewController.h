//
//  ProfilesWindowPreferencesViewController.h
//  iTerm
//
//  Created by George Nachman on 4/16/14.
//
//

#import "iTermProfilePreferencesBaseViewController.h"

CGFloat iTermMaxBlurRadius(void);

@interface ProfilesWindowPreferencesViewController : iTermProfilePreferencesBaseViewController

- (void)layoutSubviewsForEditCurrentSessionMode;

@end
