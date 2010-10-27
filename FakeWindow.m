//
//  FakeWindow.m
//  iTerm
//
//  Created by George Nachman on 10/18/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "FakeWindow.h"
#import "iTerm/PTYSession.h"

@implementation FakeWindow

- (id)initFromRealWindow:(PseudoTerminal*)aTerm session:(PTYSession*)aSession
{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    isFullScreen = [aTerm fullScreen];
    isMiniaturized = [[aTerm window] isMiniaturized];
    frame = [[aTerm window] frame];
    screen = [[aTerm window] screen];
    session = aSession;
    [session retain];
    return self;
}

- (void)dealloc
{
    if (pendingLabelColor) {
        [pendingLabelColor release];
    }
    [super dealloc];
}

- (void)rejoin:(PseudoTerminal*)aTerm
{
    [session release];
    if (hasPendingClose) {
        [aTerm closeSession:session];
        return;
    }
    
    if (hasPendingBlurChange) {
        if (pendingBlur) {
            [aTerm enableBlur];
        } else {
            [aTerm disableBlur];
        }
    }
    if (hasPendingSizeChange) {
        [aTerm sessionInitiatedResize:session width:pendingW height:pendingH];
    }
    if (hasPendingFitWindowToSession) {
        [aTerm fitWindowToSession:session];
    }
    if (pendingLabelColor) {
        [aTerm setLabelColor:pendingLabelColor forTabViewItem:[session tabViewItem]];
    }
    if (hasPendingSetWindowTitle) {
        [aTerm setWindowTitle];
    }
    if (hasPendingResetTempTitle) {
        [aTerm resetTempTitle];
    }
}

- (void)sessionInitiatedResize:(PTYSession*)session width:(int)width height:(int)height
{
    hasPendingSizeChange = YES;
    pendingW = width;
    pendingH = height;
}

- (BOOL)fullScreen
{
    return isFullScreen;
}

// TODO(georgen): disable send input to all sessions when you transition to
// dvr mode; or else make it work.
- (BOOL)sendInputToAllSessions
{
    return NO;
}

- (PTYSession *)currentSession
{
    return session;
}

- (void)closeSession:(PTYSession*)aSession
{
    hasPendingClose = YES;
}

- (IBAction)nextSession:(id)sender
{
}

- (IBAction)previousSession:(id)sender
{
}

- (void)setLabelColor:(NSColor *)color forTabViewItem:tabViewItem
{
    [pendingLabelColor release];
    pendingLabelColor = color;
    [pendingLabelColor retain];
}

- (void)enableBlur
{
    hasPendingBlurChange = YES;
    pendingBlur = YES;
}

- (void)disableBlur
{
    hasPendingBlurChange = YES;
    pendingBlur = NO;
}

- (BOOL)tempTitle
{
    return NO;
}

- (void)fitWindowToSession:(PTYSession*)session
{
    hasPendingFitWindowToSession = YES;
}

- (PTYTabView *)tabView
{
    return nil;
}

- (void)setWindowTitle
{
    hasPendingSetWindowTitle = YES;
}

- (void)resetTempTitle
{
    hasPendingResetTempTitle = YES;
}

- (void)sendInputToAllSessions:(NSData *)data
{
}

- (void)windowSetFrameTopLeftPoint:(NSPoint)point
{
}

- (void)windowPerformMiniaturize:(id)sender
{
}

- (void)windowDeminiaturize:(id)sender
{
}

- (void)windowOrderFront:(id)sender
{
}

- (void)windowOrderBack:(id)sender
{
}

- (BOOL)windowIsMiniaturized
{
    return isMiniaturized;
}

- (NSRect)windowFrame
{
    return frame;
}

- (NSScreen*)windowScreen
{
    return screen;
}


@end
