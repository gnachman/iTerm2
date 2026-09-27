//
//  ProfilesTerminalPreferencesViewController.h
//  iTerm
//
//  Created by George Nachman on 4/17/14.
//
//

#import "iTermProfilePreferencesBaseViewController.h"

@interface ProfilesTerminalPreferencesViewController : iTermProfilePreferencesBaseViewController

- (void)layoutSubviewsForEditCurrentSessionMode;

// Rebuilds the locale name field's attributed string. Its colors are baked into
// an attributed string that NSTextField does not re-resolve on its own when the
// effective appearance changes, so this must be called when the pane becomes
// visible again (in case the appearance changed while it was hidden).
- (void)updateLocaleDescription;

@end
