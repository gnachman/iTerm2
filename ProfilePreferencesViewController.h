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

// TODO: Nuke all of these.
- (ProfileModel *)profilePreferencesModel;
- (void)underlyingBookmarkDidChange;
- (void)profilePreferencesModelDidAwakeFromNib;

@end

@interface ProfilePreferencesViewController : iTermPreferencesBaseViewController

@property(nonatomic, assign) IBOutlet id<ProfilePreferencesViewControllerDelegate> delegate;
@property(nonatomic, readonly) NSTabView *tabView;  // TODO: nuke this

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

// TODO: Nuke these methods
- (void)updateProfileInModel:(Profile *)modifiedProfile;
- (void)updateSubviewsForProfile:(Profile *)profile;
- (void)reloadData;
- (void)copyOwnedValuesToDict:(NSMutableDictionary *)dict;

@end
