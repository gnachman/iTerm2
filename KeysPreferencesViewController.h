//
//  KeysPreferencesViewController.h
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "iTermPreferencesBaseViewController.h"

@interface KeysPreferencesViewController : iTermPreferencesBaseViewController

@property(nonatomic, readonly) NSTextField *hotkeyField;

- (void)hotkeyKeyDown:(NSEvent*)event;

@end
