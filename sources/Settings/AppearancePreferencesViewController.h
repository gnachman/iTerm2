//
//  AppearancePreferencesViewController.h
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import "iTermPreferencesBaseViewController.h"

// Posted when the user changes the process type to/from LSUIElement.
extern NSString *const iTermProcessTypeDidChangeNotification;

@interface AppearancePreferencesViewController : iTermPreferencesBaseViewController

// Whether “Show menu bar icon” is forced on (shown checked and disabled) for these settings: the
// icon is the only way back to Settings while iTerm2 is always excluded from the Dock.
+ (BOOL)menuBarItemIsForcedWhenExcludedFromDock:(BOOL)excludedFromDock
               onlyIfAllWindowsAreHotkeyWindows:(BOOL)onlyIfAllWindowsAreHotkeyWindows
                                  statusBarIcon:(BOOL)statusBarIcon;

@end
