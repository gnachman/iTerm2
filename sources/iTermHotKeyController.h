#import "ProfileModel.h"
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

@class PseudoTerminal;

@interface iTermHotKeyController : NSObject

// Hotkey windows' restorable state is saved in the application delegate because these windows are
// often ordered out, and ordered-out windows are not saved. This is assigned to when the app state
// is decoded and updated from saveHotkeyWindowState.
@property(nonatomic, retain) NSDictionary *restorableState;

// Is the hotkey window in the process of opening right now?
@property(nonatomic, readonly) BOOL rollingInHotkeyTerm;

// Is there a visible hotkey window right now?
@property(nonatomic, readonly, getter=isHotKeyWindowOpen) BOOL hotKeyWindowOpen;

// Returns the designated hotkey window or nil if there is none.
@property(nonatomic, readonly) PseudoTerminal *hotKeyWindow;

// Returns the profile to be used for new hotkey windows, or nil if none defined.
@property(nonatomic, readonly) Profile *profile;

// Indicates if pressing some hotkey opens a dedicated window.
@property(nonatomic, readonly) BOOL haveHotkeyBoundToWindow;

+ (instancetype)sharedInstance;
- (instancetype)init NS_UNAVAILABLE;

// Close `window` and reveal the already-visible hotkey window. If the hotkey window wasn't already
// visible then just close `window`. This is useful when closing a floating window.
- (void)closeWindowReturningToHotkeyWindowIfPossible:(NSWindow *)window;

// Reveal the hotkey window, creating it if needed.
- (void)showHotKeyWindow;

// Create the hotkey window if it doesn't already exist. It will be hidden but ordered in.
// You should not normally use this unless you know what you're doing.
- (PseudoTerminal *)createHotKeyWindow;

// Hide the indicated hotkey window. If `suppressHideApp` is set then do not hide and then unhide
// iTerm after the hotkey window is dismissed (which would normally happen if iTerm2 was not the
// active app when the hotkey window was shown). The hide-unhide cycles moves all the iTerm2 windows
// behind the next app.
- (void)hideHotKeyWindowAnimated:(BOOL)animated
                 suppressHideApp:(BOOL)suppressHideApp;

// Indicates if the event is a hotkey event. Assumes it is a keydown.
- (BOOL)eventIsHotkey:(NSEvent *)event;

// Sets the hotkey code and modifiers. Begins using it to toggle the hotkey window.
- (BOOL)registerHotkey:(NSUInteger)keyCode modifiers:(NSEventModifierFlags)modifiers;

// Stops toggling the hotkey window when a previously registered keycode+modifiers is pressed.
- (void)unregisterHotkey;

// Updates -restorableState and invalidates the app's restorable state.
- (void)saveHotkeyWindowState;

// Make the app that was active before the hotkey window was opened active.
- (void)restorePreviouslyActiveApp;

// Simulate pressing the hotkey.
- (void)hotkeyPressed;

@end
