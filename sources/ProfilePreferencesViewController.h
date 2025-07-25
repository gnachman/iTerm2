//
//  ProfilePreferencesViewController.h
//  iTerm
//
//  Created by George Nachman on 4/8/14.
//
//

#import "iTermPreferencesBaseViewController.h"
#import "ProfileModel.h"

@class iTermProfilePreferencesBaseViewController;
@protocol iTermSessionScope;
@class iTermVariableScope;
@class ProfileModel;

// Posted when the name field ends editing in the "get info" dialog. The object is the guid of the
// profile that may have changed.
extern NSString *const kProfileSessionNameDidEndEditing;

// Posted when a session hotkey is changed through Edit Session
extern NSString *const kProfileSessionHotkeyDidChange;

@protocol ProfilePreferencesViewControllerDelegate <NSObject>

- (ProfileModel *)profilePreferencesModel;

@end

@interface ProfilePreferencesViewController : iTermPreferencesBaseViewController

@property(nonatomic, weak) IBOutlet id<ProfilePreferencesViewControllerDelegate> delegate;
@property (nonatomic) BOOL tmuxSession;
@property (nonatomic, strong) iTermVariableScope<iTermSessionScope> *scope;

// Size of tab view.
@property(nonatomic, readonly) NSSize size;

- (void)layoutSubviewsForEditCurrentSessionMode;

- (Profile *)selectedProfile;

- (void)selectGuid:(NSString *)guid;

- (void)openToProfileWithGuid:(NSString *)guid;
- (void)selectDefaultProfile;

- (void)selectFirstProfileIfNecessary;

- (void)selectGeneralTab;

- (void)openToProfileWithGuid:(NSString *)guid
             selectGeneralTab:(BOOL)selectGeneralTab
                        scope:(iTermVariableScope<iTermSessionScope> *)scope;

- (void)openToProfileWithGuidAndEditHotKey:(NSString *)guid
                                     scope:(iTermVariableScope<iTermSessionScope> *)scope;

- (void)openToProfileWithGuid:(NSString *)guid
andEditComponentWithIdentifier:(NSString *)identifier
                        scope:(iTermVariableScope<iTermSessionScope> *)scope;

// Update views for changed backing state.
- (void)refresh;

- (void)resizeWindowForCurrentTabAnimated:(BOOL)animated;
- (void)invalidateSavedSize;

- (BOOL)hasViewController:(iTermProfilePreferencesBaseViewController *)viewController;
- (id<iTermSearchableViewController>)viewControllerWithOwnerIdentifier:(NSString *)ownerIdentifier;
- (void)didLayoutSubviewsForEditCurrentSessionMode;
- (void)switchProfilesIfNeededToRevealDocument:(iTermPreferencesSearchDocument *)document;

@end
