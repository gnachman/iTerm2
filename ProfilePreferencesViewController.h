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
- (void)updateBookmarkFields:(Profile *)profile;
- (void)profileWithGuidWasSelected:(NSString *)guid;
- (void)bookmarkSettingChanged:(id)sender;
- (void)removeKeyMappingsReferringToBookmarkGuid:(NSString*)badRef;
- (void)profilePreferencesModelDidAwakeFromNib;

@end

@interface ProfilePreferencesViewController : iTermPreferencesBaseViewController

@property(nonatomic, assign) IBOutlet id<ProfilePreferencesViewControllerDelegate> delegate;
@property(nonatomic, readonly) NSTabView *tabView;  // TODO: nuke this

- (void)layoutSubviewsForSingleBookmarkMode;

- (Profile *)selectedProfile;

- (void)selectGuid:(NSString *)guid;

- (void)selectFirstProfileIfNecessary;

// Size of tab view.
- (NSSize)size;

- (void)openToProfileWithGuid:(NSString *)guid;

// TODO: Nuke these methods
- (void)updateProfileInModel:(Profile *)modifiedProfile;
- (void)updateSubviewsForProfile:(Profile *)profile;
- (void)reloadData;
- (void)copyOwnedValuesToDict:(NSMutableDictionary *)dict;
- (void)exportColorPresetToFile:(NSString*)filename;
- (void)loadColorPresetWithName:(NSString *)presetName;

@end
