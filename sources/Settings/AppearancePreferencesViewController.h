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
// icon is the only way back to Settings while iTerm2 is excluded from the Dock. currentlyUIElement
// is the effective state, which matters when exclusion requires all windows to be hotkey windows.
+ (BOOL)menuBarItemIsForcedWhenExcludedFromDock:(BOOL)excludedFromDock
               onlyIfAllWindowsAreHotkeyWindows:(BOOL)onlyIfAllWindowsAreHotkeyWindows
                             currentlyUIElement:(BOOL)currentlyUIElement
                                  statusBarIcon:(BOOL)statusBarIcon;

@end
