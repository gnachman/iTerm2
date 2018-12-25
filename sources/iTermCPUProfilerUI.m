//
//  iTermCPUProfilerUI.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/24/18.
//

#import "iTermCPUProfilerUI.h"
#import <Cocoa/Cocoa.h>
#import "ToastWindowController.h"

@implementation iTermCPUProfilerUI

+ (void)createProfileWithCompletion:(void (^)(iTermCPUProfile * _Nonnull))completion {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Create CPU Profile";
    alert.informativeText = @"To create a good profile, reproduce the performance problem you wish to diagnose for five seconds. Start when the countdown ends.";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    NSModalResponse response = [alert runModal];
    if (response == NSAlertSecondButtonReturn) {
        return;
    }

    [self startCountdownWithCount:5 completion:completion];
}

+ (void)startCountdownWithCount:(NSInteger)count completion:(void (^)(iTermCPUProfile * _Nonnull))completion {
    [ToastWindowController showToastWithMessage:[NSString stringWithFormat:@"%@…", @(count)] duration:1];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (count > 1) {
            [self startCountdownWithCount:count - 1 completion:completion];
            return;
        }
        [ToastWindowController showToastWithMessage:@"Collecting Sample" duration:5];
        [[iTermCPUProfiler sharedInstance] startProfilingForDuration:5 completion:completion];
    });
}

@end
