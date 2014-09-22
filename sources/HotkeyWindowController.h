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

+ (id)sharedInstance;
+ (void)closeWindowReturningToHotkeyWindowIfPossible:(NSWindow *)window;

- (BOOL)rollingInHotkeyTerm;
- (void)showHotKeyWindow;
- (void)doNotOrderOutWhenHidingHotkeyWindow;
- (void)fastHideHotKeyWindow;
- (void)hideHotKeyWindow:(PseudoTerminal*)hotkeyTerm;
- (BOOL)isHotKeyWindowOpen;
- (PseudoTerminal*)hotKeyWindow;
- (BOOL)eventIsHotkey:(NSEvent*)e;
- (void)unregisterHotkey;
- (BOOL)haveEventTap;
- (BOOL)registerHotkey:(int)keyCode modifiers:(int)modifiers;
- (void)beginRemappingModifiers;
- (void)stopEventTap;

// Returns the profile to be used for new hotkey windows, or nil if none defined.
- (Profile *)profile;

// Saves or deletes the hotkey window's state from user defaults.
- (void)saveHotkeyWindowState;

- (int)controlRemapping;
- (int)leftOptionRemapping;
- (int)rightOptionRemapping;
- (int)leftCommandRemapping;
- (int)rightCommandRemapping;
- (BOOL)isAnyModifierRemapped;

@end
