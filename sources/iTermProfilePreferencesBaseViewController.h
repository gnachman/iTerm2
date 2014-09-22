//
//  iTermProfilePreferencesBaseViewController.h
//  iTerm
//
//  Created by George Nachman on 4/10/14.
//
//

#import "iTermPreferencesBaseViewController.h"
#import "ProfileModel.h"

@protocol iTermProfilePreferencesBaseViewControllerDelegate <NSObject>

- (Profile *)profilePreferencesCurrentProfile;
- (ProfileModel *)profilePreferencesCurrentModel;

@end

@interface iTermProfilePreferencesBaseViewController : iTermPreferencesBaseViewController

@property(nonatomic, assign) IBOutlet id<iTermProfilePreferencesBaseViewControllerDelegate> delegate;

// Update controls' values after the selected profile changes.
- (void)reloadProfile;

// Called just before selected profile changes.
- (void)willReloadProfile;

@end
