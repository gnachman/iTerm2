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

    NSColor* pendingLabelColor;
    NSColor* pendingTabColor;
    BOOL scrollbarShouldBeVisible;
}

- (id)initFromRealWindow:(NSWindowController<iTermWindowController> *)aTerm
                 session:(PTYSession*)aSession;
- (void)dealloc;

// PseudoTerminal should call this after adding the session to its tab view.
- (void)rejoin:(NSWindowController<iTermWindowController> *)aTerm;

- (void)sessionInitiatedResize:(PTYSession*)session width:(int)width height:(int)height;
- (BOOL)fullScreen;
- (BOOL)anyFullScreen;
- (void)closeSession:(PTYSession*)aSession;
- (IBAction)nextTab:(id)sender;
- (IBAction)previousTab:(id)sender;
- (void)setLabelColor:(NSColor *)color forTabViewItem:tabViewItem;
- (void)setTabColor:(NSColor *)color forTabViewItem:tabViewItem;
- (NSColor*)tabColorForTabViewItem:(NSTabViewItem*)tabViewItem;
- (void)enableBlur:(double)radius;
- (void)disableBlur;
- (BOOL)tempTitle;
- (PTYTabView *)tabView;
- (PTYSession *)currentSession;
- (void)setWindowTitle;
- (void)resetTempTitle;
- (PTYTab*)currentTab;

- (void)windowSetFrameTopLeftPoint:(NSPoint)point;
- (void)windowPerformMiniaturize:(id)sender;
- (void)windowDeminiaturize:(id)sender;
- (void)windowOrderFront:(id)sender;
- (void)windowOrderBack:(id)sender;
- (BOOL)windowIsMiniaturized;
- (NSRect)windowFrame;
- (NSScreen*)windowScreen;
- (BOOL)scrollbarShouldBeVisible;

@end
