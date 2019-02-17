//
//  ProfilesGeneralPreferencesViewController.h
//  iTerm
//
//  Created by George Nachman on 4/11/14.
//
//

#import "iTermProfilePreferencesBaseViewController.h"

@class iTermVariableScope;

@protocol ProfilesGeneralPreferencesViewControllerDelegate <NSObject>

- (void)profilesGeneralPreferencesNameWillChange;

// This should be called only for "edit info" dialogs when the name field resigns first responder.
- (void)profilesGeneralPreferencesNameDidEndEditing;

- (void)profilesGeneralPreferencesNameDidChange;

- (void)profilesGeneralPreferencesSessionHotkeyDidChange;

- (iTermVariableScope *)profilesGeneralPreferencesScope;
@end

@interface ProfilesGeneralPreferencesViewController : iTermProfilePreferencesBaseViewController

@property(nonatomic, weak) IBOutlet id<ProfilesGeneralPreferencesViewControllerDelegate> profileDelegate;
@property(nonatomic, readonly) NSTextField *profileNameField;
@property(nonatomic, readonly) NSTextField *profileNameFieldForEditCurrentSession;
@property(nonatomic, readonly) NSString *selectedGuid;

- (void)layoutSubviewsForEditCurrentSessionMode;
- (void)updateShortcutTitles;
- (void)windowWillClose;

@end
