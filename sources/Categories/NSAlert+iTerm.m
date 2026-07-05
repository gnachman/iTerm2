//
//  NSAlert+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/6/18.
//

#import "NSAlert+iTerm.h"
#import "DebugLogging.h"

@implementation NSAlert (iTerm)

- (NSModalResponse)runSheetModalForWindow:(NSWindow *)window {
    DLog(@"Run sheet modal for window %@", window);

    [NSApp activateIgnoringOtherApps:YES];

    // If the parent window is closed before the user dismisses the sheet,
    // the completion handler will never fire and the modal loop in
    // runModalForWindow: will run forever, blocking the entire app.
    // Observe the parent window closing so we can abort the modal.
    __block BOOL stopped = NO;
    __block id observer = nil;
    observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification
                                                                 object:window
                                                                  queue:nil
                                                             usingBlock:^(NSNotification *note) {
        if (stopped) {
            return;
        }
        stopped = YES;
        DLog(@"Parent window closed while sheet modal was active — aborting modal");
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        [NSApp abortModal];
    }];

    [self beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
        if (stopped) {
            return;
        }
        stopped = YES;
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        [NSApp stopModalWithCode:returnCode];
    }];
    return [NSApp runModalForWindow:[self window]];
}

@end
