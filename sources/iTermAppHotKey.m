#import "iTermAppHotKey.h"

#import "DebugLogging.h"
#import "iTermController.h"
#import "iTermPreferences.h"
#import "NSTextField+iTerm.h"
#import "PreferencePanel.h"

@class iTermHotKey;

@implementation iTermAppHotKey

- (NSArray<iTermBaseHotKey *> *)hotKeyPressedWithSiblings:(NSArray<iTermBaseHotKey *> *)siblings {
    DLog(@"hotkey pressed");

    if ([NSApp isActive]) {
        PreferencePanel *prefsWindowController = [PreferencePanel sharedInstance];
        NSWindow *prefsWindow = [prefsWindowController window];
        NSWindow *keyWindow = [[NSApplication sharedApplication] keyWindow];
        if (prefsWindow != keyWindow ||
            prefsWindowController.window.firstResponder != prefsWindowController.hotkeyField) {
            [NSApp hide:nil];
        }
    } else {
        iTermController *controller = [iTermController sharedInstance];
        int numberOfTerminals = [controller numberOfTerminals];
        [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
        if (numberOfTerminals == 0) {
            [controller newWindow:nil];
        }
    }
    return nil;
}

@end
