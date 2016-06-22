//
//  KeysPreferencesViewController.h
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "iTermPreferencesBaseViewController.h"
#import "iTermShortcutInputView.h"
#import "ProfileModel.h"

@interface KeysPreferencesViewController : iTermPreferencesBaseViewController <
    iTermShortcutInputViewDelegate>

@property(nonatomic, readonly) NSTextField *hotkeyField;

@end
