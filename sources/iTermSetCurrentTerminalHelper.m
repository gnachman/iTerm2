//
//  iTermSetCurrentTerminalHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/3/18.
//

#import "iTermSetCurrentTerminalHelper.h"

#import "DebugLogging.h"
#import "PseudoTerminal.h"

@implementation iTermSetCurrentTerminalHelper {
    NSInteger _generation;
}

- (void)setCurrentTerminal:(PseudoTerminal *)thePseudoTerminal {
    _generation++;
    DLog(@"setCurrentTerminal:%@ generation<-%@", thePseudoTerminal, @(_generation));
    [self setCurrentTerminal:thePseudoTerminal generation:_generation isRetry:NO];
}

#pragma mark - Private

- (NSUserDefaults *)appleDockUserDefaults {
    static NSUserDefaults *userDefaults;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        userDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.apple.dock"];
    });
    return userDefaults;
}

- (BOOL)shouldDeferSetCurrentTerminal:(PseudoTerminal *)thePseudoTerminal {
    // When "minimize to application icon" is on then making a miniaturized window key puts it into
    // a broken state where it's visible but does not accept keypresses.
    return (thePseudoTerminal.restoringWindow &&
            thePseudoTerminal.window.isMiniaturized &&
            [[self appleDockUserDefaults] boolForKey:@"minimize-to-application"]);
}

- (void)scheduleSetCurrentTerminalRetry:(PseudoTerminal *)thePseudoTerminal generation:(NSInteger)generation {
    __weak PseudoTerminal *term = thePseudoTerminal;
    DLog(@"Defer making terminal current generation=%@", @(generation));
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (term) {
            [weakSelf setCurrentTerminal:term generation:generation isRetry:YES];
        }
    });
}

- (void)setCurrentTerminal:(PseudoTerminal *)thePseudoTerminal generation:(NSInteger)generation isRetry:(BOOL)isRetry {
    if (isRetry && generation != _generation) {
        DLog(@"Give up on setCurrentTerminal for generation %@", @(generation));
        return;
    }
    if ([self shouldDeferSetCurrentTerminal:thePseudoTerminal]) {
        [self scheduleSetCurrentTerminalRetry:thePseudoTerminal generation:generation];
    } else {
        [self.delegate reallySetCurrentTerminal:thePseudoTerminal];
    }
}

@end

