//
//  iTermProfilePreferencesBaseViewController.h
//  iTerm
//
//  Created by George Nachman on 4/10/14.
//
//

#import "iTermPreferencesBaseViewController.h"
#import "ProfileModel.h"

@class iTermSizeRememberingView;
@class iTermProfilePreferencesBaseViewController;

@protocol iTermProfilePreferencesBaseViewControllerDelegate <NSObject>

- (Profile *)profilePreferencesCurrentProfile;
- (ProfileModel *)profilePreferencesCurrentModel;
- (void)profilePreferencesContentViewSizeDidChange:(iTermSizeRememberingView *)view;
- (BOOL)editingTmuxSession;
- (void)profilePreferencesViewController:(iTermProfilePreferencesBaseViewController *)viewController
                    willSetObjectWithKey:(NSString *)key;
- (BOOL)profilePreferencesRevealViewController:(iTermProfilePreferencesBaseViewController *)viewController;
- (void)profilePreferencesSessionTypeDidChange;
@end

@interface iTermProfilePreferencesBaseViewController : iTermPreferencesBaseViewController

@property(nonatomic, weak) IBOutlet id<iTermProfilePreferencesBaseViewControllerDelegate> delegate;
@property(nonatomic, readonly) ProfileType profileType;

- (void)setObject:(NSObject *)value forKey:(NSString *)key withSideEffects:(BOOL)sideEffects;

// Update controls' values after the selected profile changes.
- (void)reloadProfile;

// Called just before selected profile changes.
- (void)willReloadProfile;
- (void)updateBrowserSpecific;

@end
