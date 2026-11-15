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

// The Quick Look “Never” checkbox: stores 0 (never close) or restores the default close delay.
- (IBAction)quickLookHoverNeverCloseChanged:(id)sender;

@end
