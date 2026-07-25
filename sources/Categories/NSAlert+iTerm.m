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
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification
                                                                    object:window
                                                                     queue:nil
                                                                usingBlock:^(NSNotification *note) {
        if (stopped) {
            return;
        }
        stopped = YES;
        DLog(@"Parent window closed while sheet modal was active; aborting modal");
        [NSApp abortModal];
    }];

    [self beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
        if (stopped) {
            return;
        }
        stopped = YES;
        [NSApp stopModalWithCode:returnCode];
    }];
    const NSModalResponse result = [NSApp runModalForWindow:[self window]];
    // Remove the observer on every exit path, including when the modal was
    // unwound by something other than our two blocks (e.g. a third party calling
    // -[NSApp abortModal] during app termination). Otherwise a stale observer
    // survives and could later abort an unrelated modal when this window closes.
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    return result;
}

@end
