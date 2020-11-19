//
//  iTermUntitledWindowStateMachine.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/20.
//

#import "iTermUntitledWindowStateMachine.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "NSApplication+iTerm.h"


@implementation iTermUntitledWindowStateMachine {
    NSMutableSet<NSString *> *_contingencies;
    BOOL _windowRestorationComplete;
    BOOL _disableInitialWindow;
    BOOL _initializationComplete;
    BOOL _wantsWindow;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p windowRestorationComplete=%@ disableInitialWindow=%@ initializationComplete=%@ wantsWindow=%@>",
            self.class, self, @(_windowRestorationComplete), @(_disableInitialWindow),
            @(_initializationComplete), @(_wantsWindow)];
}

- (void)maybeOpenUntitledFile {
    DLog(@"untitled: maybeOpenUntitledFile %@\n%@", self, [NSThread callStackSymbols]);
    if (_disableInitialWindow && !_initializationComplete) {
        // This is the initial window.
        DLog(@"untitled: do nothing because this is the initial window.");
        return;
    }
    _wantsWindow = YES;
    [self openWindowIfWanted];
}

- (void)didRestoreSomeWindows {
    DLog(@"untitled: didRestoreSomeWindows %@", self);
    [self disableInitialUntitledWindow];
}

- (void)disableInitialUntitledWindow {
    DLog(@"untitled: didRestoreSomeWindows %@", self);
    _disableInitialWindow = YES;
    _wantsWindow = NO;
}

- (void)didFinishRestoringWindows {
    DLog(@"untitled: windowRestorationDidComplete %@", self);
    _windowRestorationComplete = YES;
    [self openWindowIfWanted];
}

- (void)didFinishInitialization {
    DLog(@"untitled: didFinishInitialization %@", self);
    _initializationComplete = YES;
    [self openWindowIfWanted];
}

- (void)openWindowIfWanted {
    DLog(@"untitled: openWindowIfWanted %@", self);
    if ([[NSApplication sharedApplication] isRunningUnitTests]) {
        DLog(@"Nope, running unit tests");
        return;
    }
    if (!_windowRestorationComplete || !_initializationComplete) {
        DLog(@"untitled: not ready yet %@", self);
        return;
    }
    if (!_wantsWindow) {
        DLog(@"untitled: doesn't want window %@", self);
        return;
    }

    DLog(@"untitled: actually open a window %@", self);
    [self.delegate untitledWindowStateMachineCreateNewWindow:self];
}

@end
