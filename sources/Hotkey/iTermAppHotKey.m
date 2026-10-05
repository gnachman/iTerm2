#import "iTermAppHotKey.h"

#import "DebugLogging.h"
#import "iTermController.h"
#import "iTermPreferences.h"
#import "iTermPreviousState.h"
#import "iTermShortcutInputView.h"
#import "NSTextField+iTerm.h"
#import "PreferencePanel.h"

@class iTermHotKey;

@implementation iTermAppHotKey {
    NSRunningApplication *_previousApp;
    iTermPreviousState *_previousState;
}

- (instancetype)initWithShortcuts:(NSArray<iTermShortcut *> *)shortcuts
            hasModifierActivation:(BOOL)hasModifierActivation
               modifierActivation:(iTermHotKeyModifierActivation)modifierActivation {
    self = [super initWithShortcuts:shortcuts
              hasModifierActivation:hasModifierActivation
                 modifierActivation:modifierActivation];
    if (self) {
        _previousState = [[iTermPreviousState alloc] init];
        DLog(@"Initialize previousState to %@", _previousState);
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                               selector:@selector(workspaceDidDeactivateApplication:)
                                                                   name:NSWorkspaceDidDeactivateApplicationNotification
                                                                 object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidBecomeActive:)
                                                     name:NSApplicationDidBecomeActiveNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    [_previousApp release];
    [_previousState release];
    [super dealloc];
}

- (NSArray<iTermBaseHotKey *> *)hotKeyPressedWithSiblings:(NSArray<iTermBaseHotKey *> *)siblings {
    DLog(@"hotkey pressed");

    if ([NSApp isActive]) {
        PreferencePanel *prefsWindowController = [PreferencePanel sharedInstance];
        // Don't load the Settings window just to check whether it's in use: if it was never
        // loaded, it can't be. Loading it needlessly also surfaces a damaged bundle (e.g., after
        // the app was replaced while running) on an unrelated keystroke.
        NSWindow *prefsWindow = prefsWindowController.isWindowLoaded ? prefsWindowController.window : nil;
        NSWindow *keyWindow = [[NSApplication sharedApplication] keyWindow];
        const BOOL prefsHasHotkeyFocus = (prefsWindow != nil &&
                                          prefsWindow == keyWindow &&
                                          prefsWindow.firstResponder == prefsWindowController.hotkeyField);
        if (!prefsHasHotkeyFocus) {
            if (_previousState && (keyWindow.styleMask & NSWindowStyleMaskFullScreen)) {
                RLog(@"Retore previously active app %@", _previousState);
                [_previousState restorePreviouslyActiveApp];
            } else {
                RLog(@"Hide app");
                [NSApp hide:nil];
            }
        } else {
            RLog(@"Ignoring hotkey because prefs is active");
        }
    } else {
        iTermController *controller = [iTermController sharedInstance];
        int numberOfTerminals = [controller numberOfTerminals];
        RLog(@"Activate app");
        [[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        if (numberOfTerminals == 0) {
            RLog(@"Make new window");
            [controller newWindow:nil];
        }
    }
    return nil;
}

- (void)workspaceDidDeactivateApplication:(NSNotification *)notification {
    [_previousApp autorelease];
    _previousApp = [notification.userInfo[NSWorkspaceApplicationKey] retain];
    DLog(@"workspace did deactivate. Set previous app to %@", notification.userInfo);

}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    DLog(@"erase previous state");
    [_previousState autorelease];
    _previousState = nil;
    if (_previousApp) {
        _previousState = [[iTermPreviousState alloc] initWithRunningApp:_previousApp];
        DLog(@"Set previous state to %@ from %@", _previousState, _previousApp);
    }
}

@end
