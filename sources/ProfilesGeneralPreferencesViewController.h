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

// This should be called only for "edit info" dialogs when the name field resigns first responder.
- (void)profilesGeneralPreferencesNameDidEndEditing;

- (void)profilesGeneralPreferencesNameDidChange;

@end

@interface ProfilesGeneralPreferencesViewController : iTermProfilePreferencesBaseViewController

@property(nonatomic, assign) IBOutlet id<ProfilesGeneralPreferencesViewControllerDelegate> profileDelegate;
@property(nonatomic, readonly) NSTextField *profileNameField;
@property(nonatomic, readonly) NSTextField *profileNameFieldForEditCurrentSession;
@property(nonatomic, readonly) NSString *selectedGuid;

- (void)layoutSubviewsForEditCurrentSessionMode;
- (void)updateShortcutTitles;
- (void)windowWillClose;

@end
