//
//  iTermModalSheetRunner.m
//  iTerm2
//

#import "iTermModalSheetRunner.h"

#import "DebugLogging.h"

NSModalResponse iTermRunModalForWindowAbortingIfParentCloses(NSWindow *modalWindow,
                                                             NSWindow *parentWindow) {
    if (parentWindow == nil) {
        // With no parent there is nothing to guard against, and registering the observer
        // with object:nil would fire for *every* window's close, aborting this modal the
        // moment any unrelated window closed. A nil parent also means the caller's
        // -beginSheet: no-op'd and the panel is app-modal, so there is no orphaning risk.
        return [NSApp runModalForWindow:modalWindow];
    }
    __block BOOL parentClosed = NO;
    __block NSTimer *drainTimer = nil;
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification
                                                                    object:parentWindow
                                                                     queue:nil
                                                                usingBlock:^(NSNotification *note) {
        if (parentClosed) {
            return;
        }
        parentClosed = YES;
        RLog(@"Parent window closed while a modal sheet was active; aborting modal(s) to avoid a deadlock");
        [NSApp abortModal];
        // -abortModal ends only the *topmost* modal session. If a nested modal (an
        // alert, an open/save panel, or another sheet these panels can present) was on
        // top when the parent closed, that abort tore down the nested session, not
        // ours, and our -runModalForWindow: would resume blocked over the now-dead
        // parent -- the very deadlock this guards against. Keep aborting on each
        // run-loop pass until our own session ends (which invalidates this timer).
        // Every modal above ours was begun over our sheet, so it belongs to the dead
        // parent's subtree and must unwind regardless. The common (no-nesting) case
        // never sees this timer fire: the abort above ends our session and
        // -runModalForWindow: returns before the timer's first tick.
        drainTimer = [NSTimer timerWithTimeInterval:0.01 repeats:YES block:^(NSTimer *timer) {
            [NSApp abortModal];
        }];
        // Modal sessions (ours and any nested ones) run the main run loop in
        // NSModalPanelRunLoopMode, so that is the only mode the drain needs.
        [[NSRunLoop mainRunLoop] addTimer:drainTimer forMode:NSModalPanelRunLoopMode];
    }];
    const NSModalResponse result = [NSApp runModalForWindow:modalWindow];
    [drainTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    return result;
}
