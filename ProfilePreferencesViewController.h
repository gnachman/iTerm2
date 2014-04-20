//
//  ProfilePreferencesViewController.h
//  iTerm
//
//  Created by George Nachman on 4/8/14.
//
//

#import "iTermPreferencesBaseViewController.h"
#import "ProfileModel.h"

@class ProfileModel;

@protocol ProfilePreferencesViewControllerDelegate <NSObject>

- (ProfileModel *)profilePreferencesModel;

@end

@interface ProfilePreferencesViewController : iTermPreferencesBaseViewController

@property(nonatomic, assign) IBOutlet id<ProfilePreferencesViewControllerDelegate> delegate;

- (void)layoutSubviewsForEditCurrentSessionMode;

- (Profile *)selectedProfile;

- (void)selectGuid:(NSString *)guid;

- (void)selectFirstProfileIfNecessary;

- (void)changeFont:(id)fontManager;
- (void)selectGeneralTab;

// Size of tab view.
- (NSSize)size;

- (void)openToProfileWithGuid:(NSString *)guid;

- (BOOL)importColorPresetFromFile:(NSString*)filename;

// Update views for changed backing state.
- (void)refresh;

@end
