#import "iTermPreviousState.h"

#import "DebugLogging.h"
#import "iTermController.h"
#import "iTermNotificationController.h"
#import "iTermPresentationController.h"
#import "iTermSecureKeyboardEntryController.h"
#import "iTermWarning.h"
#import "PseudoTerminal.h"

@implementation iTermPreviousState

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier
                               processID:(pid_t)processID {
    self = [super init];
    if (self) {
        if ([bundleIdentifier isEqualToString:[[NSBundle mainBundle] bundleIdentifier]]) {
            self.previouslyActiveAppPID = nil;
        } else {
            self.previouslyActiveAppPID = @(processID);
        }
        DLog(@"Previously active pid for %p is %@", self, @(processID));
        _itermWasActiveWhenHotkeyOpened = [NSApp isActive];
        DLog(@"_itermWasActiveWhenHotkeyOpened=%@", @(_itermWasActiveWhenHotkeyOpened));
    }
    return self;
}

- (instancetype)init {
    NSRunningApplication *runningApp = [[NSWorkspace sharedWorkspace] frontmostApplication];
    DLog(@"Saving state: active app is %@", runningApp);
    return [self initWithBundleIdentifier:runningApp.bundleIdentifier
                                processID:runningApp.processIdentifier];
}

- (instancetype)initWithRunningApp:(NSRunningApplication *)runningApp {
    return [self initWithBundleIdentifier:runningApp.bundleIdentifier
                                processID:runningApp.processIdentifier];
}

- (void)dealloc {
    [_owner release];
    [_previouslyActiveAppPID release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p itermWasActive=%@ other app pid=%@>", self.class, self, @(_itermWasActiveWhenHotkeyOpened), self.previouslyActiveAppPID];
}

- (NSRunningApplication *)appToSwitchBackToIfAllowed {
    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:[_previouslyActiveAppPID intValue]];
    if (!app) {
        return nil;
    }
    if (@available(macOS 11.0, *)) {
        if (![[iTermSecureKeyboardEntryController sharedInstance] isEnabled]) {
            return app;
        }
    } else {
        return app;
    }

    DLog(@"Secure keyboard entry is enabled.");
    if (![[iTermSecureKeyboardEntryController sharedInstance] isDesired]) {
        DLog(@"Some other app enabled secure keyboard entry");
        static NSInteger count = 0;
        if (count++ == 0) {
            [[iTermNotificationController sharedInstance] notify:@"Can’t Switch Apps"
                                                 withDescription:[NSString stringWithFormat:@"Can’t switch back to %@ because another app has enabled secure keyboard entry.",
                                                                  app.localizedName]];
        }
        return nil;
    }

    [[iTermSecureKeyboardEntryController sharedInstance] disableUntilDeactivated];
    return app;
}

- (BOOL)restorePreviouslyActiveApp {
    if (!_previouslyActiveAppPID) {
        DLog(@"Don't have a previously active app PID");
        return NO;
    }

    NSRunningApplication *app = [self appToSwitchBackToIfAllowed];
    BOOL result = NO;
    if (app) {
        DLog(@"Restore app %@", app);
        DLog(@"** Restor previously active app from\n%@", [NSThread callStackSymbols]);
        result = [app activateWithOptions:0];
        DLog(@"activateWithOptions:0 returned %@", @(result));
    }
    self.previouslyActiveAppPID = nil;
    return result;
}

- (BOOL)restoreAllowingAppSwitch:(BOOL)allowAppSwitch {
    DLog(@"Restore %p with previously active app %@", self, _previouslyActiveAppPID);
    BOOL result = allowAppSwitch && [self restorePreviouslyActiveApp];
    if (self.itermWasActiveWhenHotkeyOpened) {
        PseudoTerminal *currentTerm = [[iTermController sharedInstance] currentTerminal];
        if (currentTerm && ![currentTerm isHotKeyWindow] && [currentTerm fullScreen]) {
            [[iTermPresentationController sharedInstance] update];
        } else {
            [[iTermPresentationController sharedInstance] forceShowMenuBarAndDock];
        }
    }
    return result;
}

- (void)suppressHideApp {
    self.itermWasActiveWhenHotkeyOpened = YES;
}

- (NSInteger)indexOfFrontNonHotKeyTerminal {
    if (![NSApp isActive]) {
        return -1;
    }

    __block NSInteger result = -1;
    [[[iTermController sharedInstance] terminals] enumerateObjectsUsingBlock:^(PseudoTerminal *_Nonnull term,
                                                                               NSUInteger idx,
                                                                               BOOL *_Nonnull stop) {
        if (!term.isHotKeyWindow && [[term window] isKeyWindow]) {
            result = idx;
        }
    }];

    return result;
}

@end
