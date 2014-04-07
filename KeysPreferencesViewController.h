//
//  KeysPreferencesViewController.h
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "iTermPreferencesBaseViewController.h"
#import "ProfileModel.h"

@interface KeysPreferencesViewController : iTermPreferencesBaseViewController

@property(nonatomic, readonly) NSTextField *hotkeyField;
@property(nonatomic, readonly) Profile *hotkeyProfile;

- (void)hotkeyKeyDown:(NSEvent*)event;
- (void)populateHotKeyProfilesMenu;

@end
