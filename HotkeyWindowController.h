#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

@class PseudoTerminal;
@class GTMCarbonHotKey;

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

@end
