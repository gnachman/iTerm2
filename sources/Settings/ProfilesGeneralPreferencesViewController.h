//
//  ProfilesGeneralPreferencesViewController.h
//  iTerm
//
//  Created by George Nachman on 4/11/14.
//
//

#import "iTermProfilePreferencesBaseViewController.h"

@protocol iTermSessionScope;
@class iTermVariableScope;

@protocol ProfilesGeneralPreferencesViewControllerDelegate <NSObject>

- (void)profilesGeneralPreferencesNameWillChange;

// This should be called only for "edit info" dialogs when the name field resigns first responder.
- (void)profilesGeneralPreferencesNameDidEndEditing;

- (void)profilesGeneralPreferencesNameDidChange;

- (void)profilesGeneralPreferencesSessionHotkeyDidChange;

- (iTermVariableScope<iTermSessionScope> *)profilesGeneralPreferencesScope;
@end

@interface ProfilesGeneralPreferencesViewController : iTermProfilePreferencesBaseViewController

@property(nonatomic, weak) IBOutlet id<ProfilesGeneralPreferencesViewControllerDelegate> profileDelegate;
@property(nonatomic, readonly) NSTextField *profileNameField;
@property(nonatomic, readonly) NSTextField *profileNameFieldForEditCurrentSession;
@property(nonatomic, readonly) NSString *selectedGuid;

- (void)layoutSubviewsForEditCurrentSessionMode;
- (void)updateShortcutTitles;
- (void)windowWillClose;

// Whether the "AI-generated name" title component should be offered in the popup.
// Exposed for testing.
+ (BOOL)shouldOfferAITitleComponentWithSettingEnabled:(BOOL)enabled
                                    profileComponents:(NSUInteger)components;

// The title components to use after the user edits the session name in Edit Session, so that
// the name shows in the title. Exposed for testing.
+ (NSUInteger)titleComponentsShowingSessionName:(NSUInteger)components;

@end
