#import "ProfileModel.h"
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

@class GTMCarbonHotKey;
@class PseudoTerminal;

@interface HotkeyWindowController : NSObject {
    // Set while window is appearing.
    BOOL rollingIn_;

    // Set when iTerm was key at the time the hotkey window was opened.
    BOOL itermWasActiveWhenHotkeyOpened_;

    // The keycode that opens the hotkey window
    int hotkeyCode_;

    // Modifiers for the keypress that opens the hotkey window
    int hotkeyModifiers_;

    // The registered carbon hotkey that listens for hotkey presses.
    GTMCarbonHotKey* carbonHotKey_;

    // When using an event tap, these will be set:
    CFMachPortRef machPortRef_;
    CFRunLoopSourceRef eventSrc_;
}

// Hotkey windows' restorable state is saved in the application delegate because these windows are
// often ordered out, and ordered-out windows are not saved. This is assigned to when the app state
// is decoded and updated from saveHotkeyWindowState.
@property(nonatomic, retain) NSDictionary *restorableState;

+ (instancetype)sharedInstance;
+ (void)closeWindowReturningToHotkeyWindowIfPossible:(NSWindow *)window;

@property (readonly) BOOL rollingInHotkeyTerm;
- (void)showHotKeyWindow;
- (void)createHiddenHotkeyWindow;
- (void)doNotOrderOutWhenHidingHotkeyWindow;
- (void)fastHideHotKeyWindow;
- (void)hideHotKeyWindow:(PseudoTerminal*)hotkeyTerm;
@property (readonly, getter=isHotKeyWindowOpen) BOOL hotKeyWindowOpen;
- (PseudoTerminal*)hotKeyWindow;
- (BOOL)eventIsHotkey:(NSEvent*)e;
- (void)unregisterHotkey;
@property (readonly) BOOL haveEventTap;
- (BOOL)registerHotkey:(int)keyCode modifiers:(int)modifiers;
- (void)beginRemappingModifiers;
- (void)stopEventTap;

// Returns the profile to be used for new hotkey windows, or nil if none defined.
- (Profile *)profile;

// Updates -restorableState and invalidates the app's restorable state.
- (void)saveHotkeyWindowState;

@property (readonly) int controlRemapping;
@property (readonly) int leftOptionRemapping;
@property (readonly) int rightOptionRemapping;
@property (readonly) int leftCommandRemapping;
@property (readonly) int rightCommandRemapping;
@property (readonly, getter=isAnyModifierRemapped) BOOL anyModifierRemapped;

@end
