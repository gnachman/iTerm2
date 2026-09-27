//
//  iTermAdvancedSettingsController.h
//  iTerm
//
//  Created by George Nachman on 3/18/14.
//
//

#import <Cocoa/Cocoa.h>
#import "iTermSearchableViewController.h"

extern BOOL gIntrospecting;

@interface iTermAdvancedSettingsViewController : NSViewController <iTermSearchableViewController, NSTableViewDataSource, NSTableViewDelegate>

// Orders two advanced-settings dictionaries. Category groups are ordered by their localized
// display name (as provided by `localizedCategoryBlock`), then rows within a category are ordered
// by localized description. Ordering by the localized category keeps the on-screen group order
// alphabetical for the user rather than following the stable English keys. The block is injectable
// so the sort key can be exercised by tests independent of the runtime locale.
+ (NSComparisonResult)compareAdvancedSettingDict:(NSDictionary *)lhs
                                          toDict:(NSDictionary *)rhs
                          localizedCategoryBlock:(NSString *(^)(NSString *englishCategory))localizedCategoryBlock;

@end
