//
//  NSAlert+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/6/18.
//

#import "NSAlert+iTerm.h"
#import "DebugLogging.h"
#import "iTermModalSheetRunner.h"

@implementation NSAlert (iTerm)

- (NSModalResponse)runSheetModalForWindow:(NSWindow *)window {
    DLog(@"Run sheet modal for window %@", window);

    [NSApp activateIgnoringOtherApps:YES];

    // If the parent window is closed before the sheet is dismissed, the completion
    // handler never fires and runModalForWindow: would block forever (an unrecoverable
    // app hang). The shared guard observes the parent closing and aborts the modal
    // (draining any nested modals stacked over the dead parent).
    [self beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
        // Only stop our own session. If the sheet is being torn down because its parent
        // closed, iTermRunModalForWindowAbortingIfParentCloses has already aborted us, so
        // stopping here could hit whatever modal is current now.
        if (NSApp.modalWindow == self.window) {
            [NSApp stopModalWithCode:returnCode];
        }
    }];
    return iTermRunModalForWindowAbortingIfParentCloses(self.window, window);
}

@end
