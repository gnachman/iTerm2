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

typedef NS_ENUM(NSUInteger, iTermUntitledFileOpen) {
    iTermUntitledFileOpenUnsafe,
    iTermUntitledFileOpenPending,
    iTermUntitledFileOpenAllowed,
    iTermUntitledFileOpenComplete,
    iTermUntitledFileOpenDisallowed
};

@interface iTermUntitledWindowStateMachine()
@property (nonatomic) iTermUntitledFileOpen state;
@end

@implementation iTermUntitledWindowStateMachine

- (instancetype)init {
    self = [super init];
    if (self) {
        if ([iTermAdvancedSettingsModel openNewWindowAtStartup]) {
            self.state = iTermUntitledFileOpenUnsafe;
        } else {
            self.state = iTermUntitledFileOpenDisallowed;
        }
    }
    return self;
}

- (void)setState:(iTermUntitledFileOpen)state {
    DLog(@"%@ -> %@\n%@",
         [self stringForState:_state], [self stringForState:state], [NSThread callStackSymbols]);
    _state = state;
}

- (NSString *)stringForState:(iTermUntitledFileOpen)state {
    switch (state) {
        case iTermUntitledFileOpenUnsafe:
            return @"unsafe";
        case iTermUntitledFileOpenPending:
            return @"pending";
        case iTermUntitledFileOpenAllowed:
            return @"allowed";
        case iTermUntitledFileOpenComplete:
            return @"complete";
        case iTermUntitledFileOpenDisallowed:
            return @"disallowed";
    }
    return [@(state) stringValue];
}

- (void)didBecomeSafe {
    DLog(@"Did become safe");
    if ([[NSApplication sharedApplication] isRunningUnitTests]) {
        DLog(@"Running unit tests");
        self.state = iTermUntitledFileOpenUnsafe;
        return;
    }
    switch (_state) {
        case iTermUntitledFileOpenUnsafe:
            self.state = iTermUntitledFileOpenAllowed;
            break;
        case iTermUntitledFileOpenAllowed:
            // Shouldn't happen
            break;
        case iTermUntitledFileOpenPending:
            self.state = iTermUntitledFileOpenAllowed;
            [self maybeOpenUntitledFile];
            break;

        case iTermUntitledFileOpenComplete:
            // Shouldn't happen
            break;
        case iTermUntitledFileOpenDisallowed:
            break;
    }
}

- (void)maybeOpenUntitledFile {
    DLog(@"Maybe open untitled file %@", [self stringForState:_state]);
    if ([[NSApplication sharedApplication] isRunningUnitTests]) {
        DLog(@"Nope, running unit tests");
        return;
    }
    switch (_state) {
        case iTermUntitledFileOpenUnsafe:
            self.state = iTermUntitledFileOpenPending;
            break;
        case iTermUntitledFileOpenAllowed:
            self.state = iTermUntitledFileOpenComplete;
            DLog(@"OK");
            [self.delegate untitledWindowStateMachineCreateNewWindow:self];
            break;
        case iTermUntitledFileOpenPending:
            break;
        case iTermUntitledFileOpenComplete:
            DLog(@"OK");
            [self.delegate untitledWindowStateMachineCreateNewWindow:self];
            break;
        case iTermUntitledFileOpenDisallowed:
            break;
    }
}

- (void)didRestoreHotkeyWindows {
    DLog(@"Did restore hotkey windows");
    switch (_state) {
        case iTermUntitledFileOpenUnsafe:
        case iTermUntitledFileOpenAllowed:
        case iTermUntitledFileOpenDisallowed:
            self.state = iTermUntitledFileOpenDisallowed;
            break;
        case iTermUntitledFileOpenPending:
        case iTermUntitledFileOpenComplete:
            break;
    }
}

- (void)didPerformStartupActivities {
    DLog(@"Did perform startup activities");
    if (_state != iTermUntitledFileOpenDisallowed) {
        return;
    }
    // Don't need to worry about the initial window any more. Allow future clicks
    // on the dock icon to open an untitled window.
    self.state = iTermUntitledFileOpenAllowed;
}

@end
