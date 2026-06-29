#import "ProfileModel.h"

#import "iTermAppHotKey.h"
#import "iTermEncoderAdapter.h"
#import "iTermGraphEncoder.h"
#import "iTermProfileHotKey.h"
#import "NSDictionary+iTerm.h"
#import "PseudoTerminal.h"

#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

@class iTermPanel;
@class Profile;
@class PseudoTerminal;

// Key in window arrangement that gives the GUID for the profile that created the window. Used for
// restoring legacy hotkey window state.
extern NSString *const TERMINAL_ARRANGEMENT_PROFILE_GUID;

@interface iTermHotKeyController : NSObject<iTermGraphCodable>

// Returns the designated hotkey window or nil if there is none.
@property(nonatomic, readonly) NSArray<PseudoTerminal *> *hotKeyWindowControllers;
@property(nonatomic, readonly) NSArray<Profile *> *hotKeyWindowProfiles;
@property(nonatomic, readonly) NSArray<PseudoTerminal *> *visibleWindowControllers;
@property(nonatomic, readonly) NSArray<iTermProfileHotKey *> *profileHotKeys;
@property(nonatomic, readonly) NSArray *restorableStates;

+ (instancetype)sharedInstance;
- (instancetype)init NS_UNAVAILABLE;

// Returns the profile hotkey, if any, associated with a profile GUID.
- (iTermProfileHotKey *)profileHotKeyForGUID:(NSString *)guid;

// Reveal the hotkey window, creating it if needed. If url is non-nil and the window doesn't exist
// yet its initial session will be opened to this URL. Returns YES if a new window was created,
// or NO if an existing window was used.
- (BOOL)showWindowForProfileHotKey:(iTermProfileHotKey *)profileHotKey url:(NSURL *)url;

// Indicates if the event is a hotkey event. Assumes the event is a keydown event.
- (BOOL)eventIsHotkey:(NSEvent *)event;

// Register a hotkey. The key/mod combo doesn't need to be unique.
- (void)addHotKey:(iTermBaseHotKey *)hotKey;

// Remove a registered hotkey.
- (void)removeHotKey:(iTermBaseHotKey *)hotKey;

// Updates -restorableState and invalidates the app's restorable state.
- (void)saveHotkeyWindowStates;

// Simulate pressing the hotkey.
- (void)hotkeyPressed:(NSEvent *)event;

- (iTermProfileHotKey *)profileHotKeyForWindowController:(PseudoTerminal *)windowController;

- (NSInteger)createHiddenWindowsFromRestorableStates:(NSArray *)states;  // legacy
- (BOOL)createHiddenWindowsByDecoding:(iTermEncoderGraphRecord *)record;  // sqlite

// Resets invalidation state.
- (BOOL)anyProfileHotkeyWindowHasInvalidState;

// Auto hide all hotkey windows, if needed and possible.
- (void)autoHideHotKeyWindows;

// Auto hide a single hotkey window, if needed and possible. Called when `windowController` resigns key.
- (void)autoHideHotKeyWindows:(NSArray<NSWindowController *> *)windowControllersToConsiderHiding;

// Call this before calling autoHideHotKeyWindowsExcept:
- (void)nonHotKeyWindowDidBecomeKey;

// Auto hide all hotkey windows but for `exception`. Called when a window belonging to `exceptions` becomes key.
- (void)autoHideHotKeyWindowsExcept:(NSArray<NSWindowController *> *)exceptions;

- (NSArray<iTermHotKeyDescriptor *> *)descriptorsForProfileHotKeysExcept:(Profile *)profile;
- (NSArray<PseudoTerminal *> *)siblingWindowControllersOf:(PseudoTerminal *)windowController;

// Returns YES if an action as taken.
- (BOOL)dockIconClicked;

// Use when undoing the close of a window to indicate that it is a hotkey window. Returns NO if
// there is already a hotkey window for this role, in which case it should be made visible and resume
// life as a regular window.
- (BOOL)addRevivedHotkeyWindowController:(PseudoTerminal *)windowController
                      forProfileWithGUID:(NSString *)guid;

// Use this when creating a window that might be a hotkey window. Generally iTermProfileHotkey creates
// its own windows, but that's not the case for e.g. tmux windows. Returns the iTermProfileHotKey if
// the window controller was assigned a shotkey or nil if not.
- (iTermProfileHotKey *)didCreateWindowController:(PseudoTerminal *)windowController
                                      withProfile:(Profile *)profile;

// Alpha=1, level=floating, on all spaces hotkey windows.
- (NSArray<iTermPanel *> *)visibleFloatingHotkeyWindows;
- (NSArray<iTermPanel *> *)allFloatingHotkeyWindows;

@end
