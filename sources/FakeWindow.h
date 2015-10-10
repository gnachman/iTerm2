//
//  FakeWindow.h
//  iTerm
//
//  Created by George Nachman on 10/18/10.
//  Copyright 2010 George Nachman. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "PseudoTerminal.h"
#import "WindowControllerInterface.h"

@interface FakeWindow : NSObject <WindowControllerInterface>
{
    // FakeWindow always has exactly one session.
    PTYSession* session;

    // Saved state from old window.
    BOOL isFullScreen;
    BOOL isLionFullScreen;
    BOOL isMiniaturized;
    NSRect frame;
    NSScreen* screen;
    NSWindowController<iTermWindowController> * realWindow;

    // Changes the session has initiated that will be delayed and performed
    // in -[rejoin:].
    BOOL hasPendingBlurChange;
    double pendingBlurRadius;
    BOOL pendingBlur;
    BOOL hasPendingClose;
    BOOL hasPendingFitWindowToTab;
    BOOL hasPendingSizeChange;
    int pendingW;
    int pendingH;
    BOOL hasPendingSetWindowTitle;
    BOOL hasPendingResetTempTitle;

    BOOL scrollbarShouldBeVisible;
}

- (instancetype)initFromRealWindow:(NSWindowController<iTermWindowController> *)aTerm
                 session:(PTYSession*)aSession;

// PseudoTerminal should call this after adding the session to its tab view.
- (void)rejoin:(NSWindowController<iTermWindowController> *)aTerm;

@end
