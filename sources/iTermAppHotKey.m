#import "iTermAppHotKey.h"

#import "DebugLogging.h"
#import "iTermController.h"
#import "iTermPreferences.h"
#import "iTermPreviousState.h"
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
        NSWindow *prefsWindow = [prefsWindowController window];
        NSWindow *keyWindow = [[NSApplication sharedApplication] keyWindow];
        if (prefsWindow != keyWindow ||
            prefsWindowController.window.firstResponder != prefsWindowController.hotkeyField) {
            if (_previousState && (keyWindow.styleMask & NSFullScreenWindowMask)) {
                [_previousState restorePreviouslyActiveApp];
            } else {
                [NSApp hide:nil];
            }
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

- (void)workspaceDidDeactivateApplication:(NSNotification *)notification {
    [_previousApp autorelease];
    _previousApp = [notification.userInfo[NSWorkspaceApplicationKey] retain];

}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    [_previousState autorelease];
    _previousState = nil;
    if (_previousApp) {
        _previousState = [[iTermPreviousState alloc] initWithRunningApp:_previousApp];
    }
}

@end
