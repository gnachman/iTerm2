#import "ProfileModel.h"

#import "iTermProfileHotKey.h"
#import "iTermAppHotKey.h"
#import "PseudoTerminal.h"

#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

@class Profile;
@class PseudoTerminal;

@interface iTermHotKeyController : NSObject

// Returns the designated hotkey window or nil if there is none.
@property(nonatomic, readonly) NSArray<PseudoTerminal *> *hotKeyWindows;
@property(nonatomic, readonly) NSArray<Profile *> *hotKeyWindowProfiles;
@property(nonatomic, readonly) NSArray<PseudoTerminal *> *visibleWindowControllers;
@property(nonatomic, readonly) NSArray<iTermProfileHotKey *> *profileHotKeys;

@property(nonatomic, readonly) PseudoTerminal *topMostVisibleHotKeyWindowController;

+ (instancetype)sharedInstance;
- (instancetype)init NS_UNAVAILABLE;

// Reveal the hotkey window, creating it if needed.
- (void)showWindowForProfileHotKey:(iTermProfileHotKey *)profileHotKey;

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
