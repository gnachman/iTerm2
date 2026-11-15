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

// Parse and format the Quick Look seconds fields. Parsing uses locale’s decimal separator and also
// accepts a period; it returns nil for text that isn’t a number.
+ (NSNumber *)quickLookSecondsFromString:(NSString *)string locale:(NSLocale *)locale;
+ (NSString *)quickLookStringFromSeconds:(double)seconds locale:(NSLocale *)locale;

@end
