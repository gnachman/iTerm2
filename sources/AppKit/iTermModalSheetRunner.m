//
//  iTermModalSheetRunner.m
//  iTerm2
//

#import "iTermModalSheetRunner.h"

#import "DebugLogging.h"

NSModalResponse iTermRunModalForWindowAbortingIfParentCloses(NSWindow *modalWindow,
                                                             NSWindow *parentWindow) {
    __block BOOL aborted = NO;
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification
                                                                    object:parentWindow
                                                                     queue:nil
                                                                usingBlock:^(NSNotification *note) {
        if (aborted) {
            return;
        }
        aborted = YES;
        DLog(@"Parent window closed while a modal sheet was active; aborting modal to avoid a deadlock");
        [NSApp abortModal];
    }];
    const NSModalResponse result = [NSApp runModalForWindow:modalWindow];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    return result;
}
