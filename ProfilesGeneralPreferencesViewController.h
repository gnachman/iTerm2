//
//  ProfilesGeneralPreferencesViewController.h
//  iTerm
//
//  Created by George Nachman on 4/11/14.
//
//

#import "iTermProfilePreferencesBaseViewController.h"

@protocol ProfilesGeneralPreferencesViewControllerDelegate <NSObject>

- (void)profilesGeneralPreferencesNameWillChange;

@end

@interface ProfilesGeneralPreferencesViewController : iTermProfilePreferencesBaseViewController

@property(nonatomic, assign) IBOutlet id<ProfilesGeneralPreferencesViewControllerDelegate> profileDelegate;
@property(nonatomic, readonly) NSTextField *profileNameField;
@property(nonatomic, readonly) NSTextField *profileNameFieldForEditCurrentSession;
@property(nonatomic, readonly) NSString *selectedGuid;

- (void)layoutSubviewsForEditCurrentSessionMode;
- (void)updateShortcutTitles;

@end
