#import "ProfileModel.h"

#import "iTermProfileHotKey.h"
#import "iTermAppHotKey.h"

#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

@class Profile;
@class PseudoTerminal;

@interface iTermHotKeyController : NSObject

// Returns the designated hotkey window or nil if there is none.
@property(nonatomic, readonly) NSArray<PseudoTerminal *> *hotKeyWindows;
@property(nonatomic, readonly) NSArray<Profile *> *hotKeyWindowProfiles;

// Indicates if pressing some hotkey opens a dedicated window.
@property(nonatomic, readonly) BOOL anyHotkeyBoundToProfile;
@property(nonatomic, readonly) PseudoTerminal *topMostVisibleHotKeyWindowController;

+ (instancetype)sharedInstance;
- (instancetype)init NS_UNAVAILABLE;

// Reveal the hotkey window, creating it if needed.
- (void)showWindowForProfileHotKey:(iTermProfileHotKey *)profileHotKey;

// Create the hotkey window if it doesn't already exist. It will be hidden but ordered in.
// You should not normally use this unless you know what you're doing.
- (PseudoTerminal *)createHotKeyWindowForProfile:(Profile *)profile;

// Hide the indicated hotkey window. If `suppressHideApp` is set then do not hide and then unhide
// iTerm after the hotkey window is dismissed (which would normally happen if iTerm2 was not the
// active app when the hotkey window was shown). The hide-unhide cycles moves all the iTerm2 windows
// behind the next app.
- (void)hideWindowForProfileHotKey:(iTermProfileHotKey *)profileHotKey
                          animated:(BOOL)animated
                   suppressHideApp:(BOOL)suppressHideApp;

// Indicates if the event is a hotkey event. Assumes the event is a keydown event.
- (BOOL)eventIsHotkey:(NSEvent *)event;

// Register a hotkey. The key/mod combo doesn't need to be unique.
- (void)addHotKey:(iTermBaseHotKey *)hotKey;

// Remove a registered hotkey.
- (void)removeHotKey:(iTermBaseHotKey *)hotKey;

// Updates -restorableState and invalidates the app's restorable state.
- (void)saveHotkeyWindowStates;

// Make the app that was active before the hotkey window was opened active.
- (void)hotKeyWindowWillClose:(PseudoTerminal *)windowController;

// Simulate pressing the hotkey.
- (void)hotkeyPressed:(NSEvent *)event;

- (iTermProfileHotKey *)profileHotKeyForWindowController:(PseudoTerminal *)windowController;

- (void)createHiddenWindowsFromRestorableStates:(NSArray *)states;
- (NSArray *)restorableStates;

@end
