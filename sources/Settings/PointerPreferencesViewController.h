//
//  PointerPreferencesViewController.h
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "iTermPreferencesBaseViewController.h"

extern NSString *const kPointerPrefsChangedNotification;
extern NSString *const kPointerPrefsSemanticHistoryEnabledChangedNotification;

@interface PointerPreferencesViewController : iTermPreferencesBaseViewController

// Opens the Quick Look settings sheet.
- (IBAction)configureQuickLook:(id)sender;

@end
