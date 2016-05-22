#import "ProfileModel.h"
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

@class PseudoTerminal;

@interface iTermHotKeyController : NSObject

// Hotkey windows' restorable state is saved in the application delegate because these windows are
// often ordered out, and ordered-out windows are not saved. This is assigned to when the app state
// is decoded and updated from saveHotkeyWindowState.
@property(nonatomic, retain) NSDictionary *restorableState;
@property(nonatomic, readonly) BOOL rollingInHotkeyTerm;
@property(nonatomic, readonly, getter=isHotKeyWindowOpen) BOOL hotKeyWindowOpen;

// Indicates if pressing some hotkey opens a dedicated window.
@property(nonatomic, readonly) BOOL haveHotkeyBoundToWindow;

+ (instancetype)sharedInstance;
+ (void)closeWindowReturningToHotkeyWindowIfPossible:(NSWindow *)window;

- (void)showHotKeyWindow;
- (void)createHiddenHotkeyWindow;
- (void)doNotOrderOutWhenHidingHotkeyWindow;
- (void)fastHideHotKeyWindow;
- (void)hideHotKeyWindow:(PseudoTerminal*)hotkeyTerm;
- (PseudoTerminal*)hotKeyWindow;
- (BOOL)eventIsHotkey:(NSEvent*)e;
- (void)unregisterHotkey;
- (BOOL)registerHotkey:(int)keyCode modifiers:(int)modifiers;

// Returns the profile to be used for new hotkey windows, or nil if none defined.
- (Profile *)profile;

// Updates -restorableState and invalidates the app's restorable state.
- (void)saveHotkeyWindowState;

// Make the app that was active before the hotkey window was opened active.
- (void)restorePreviouslyActiveApp;

@end
