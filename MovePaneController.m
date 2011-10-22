//
//  MovePaneController.m
//  iTerm2
//
//  Created by George Nachman on 8/26/11.

#import "MovePaneController.h"
#import "PTYSession.h"
#import "iTermController.h"
#import "PseudoTerminal.h"
#import "PTYTab.h"
#import "SessionView.h"

@implementation MovePaneController

@synthesize dragFailed = dragFailed_;
@synthesize session = session_;

+ (MovePaneController *)sharedInstance
{
    static MovePaneController *inst;
    if (!inst) {
        inst = [[MovePaneController alloc] init];
    }
    return inst;
}

- (void)movePane:(PTYSession *)session
{
    session_ = [session liveSession];
    if (!session_) {
        session_ = session;
    }
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        [term setSplitSelectionMode:YES excludingSession:session_];
    }
}

- (void)exitMovePaneMode
{
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        [term setSplitSelectionMode:NO excludingSession:nil];
    }
    session_ = nil;
}

- (void)moveSessionToNewWindow:(PTYSession *)movingSession atPoint:(NSPoint)point
{
    PTYTab *theTab = [movingSession tab];
    PseudoTerminal *term = [[theTab realParentWindow] terminalDraggedFromAnotherWindowAtPoint:point];

    SessionView *oldView = [movingSession view];
    [oldView retain];
    [theTab removeSession:movingSession];
    if ([[theTab sessions] count] == 0) {
        [[theTab realParentWindow] closeTab:theTab];
    }

    [term insertSession:movingSession atIndex:0];
    [oldView autorelease];
    [theTab numberOfSessionsDidChange];
    [[term currentTab] numberOfSessionsDidChange];
 }

- (SessionView *)removeAndClearSession
{
    SessionView *oldView = [session_ view];
    [oldView retain];
    PTYSession *movingSession = session_;
    PTYTab *theTab = [movingSession tab];
    [[movingSession tab] removeSession:movingSession];
    if ([[theTab sessions] count] == 0) {
        [[theTab realParentWindow] closeTab:theTab];
    }
    session_ = nil;
    return oldView;
}

- (BOOL)dropTab:(PTYTab *)tab
      inSession:(PTYSession *)dest
           half:(SplitSessionHalf)half
        atPoint:(NSPoint)point
{
    if ([[tab sessions] count] != 1) {
        // This sometimes can't be done at all, and it usually can't be done right if tabs' sizes
        // differ, etc. Just wimp out, basically.
        return NO;
    }

    session_ = [[tab sessions] objectAtIndex:0];
    return [self dropInSession:dest half:half atPoint:point];
}

// This function is either called once or twice at the end of a drag.
// If only one call is made, then dest will be nil and the session will be moved to a new window.
// If two calls are made, the first has dest non-null and will perform a split. The second call will
// be ignored.
// It isn't called at all if a session is dragged into an existing tab bar, though.
- (BOOL)dropInSession:(PTYSession *)dest
                 half:(SplitSessionHalf)half
              atPoint:(NSPoint)point
{
    if (dest == session_ || !session_) {
        didSplit_ = YES;
        return NO;
    }

    if (!dest && !didSplit_) {
        // We were not called before, so move the session to a new window.
        [self moveSessionToNewWindow:session_ atPoint:point];
        return YES;
    } else if (!dest) {
        // This is the second call and a split has already been performed.
        return NO;
    }

    didSplit_ = YES;

    PTYSession *movingSession = session_;
    BOOL isVertical = (half == kWestHalf || half == kEastHalf);
    if (![[[dest tab] realParentWindow] canSplitPaneVertically:isVertical
                                                  withBookmark:[movingSession addressBookEntry]]) {
        return NO;
    }

    SessionView *oldView = [movingSession view];
    [oldView retain];
    PTYTab *theTab = [movingSession tab];
    [[movingSession tab] removeSession:movingSession];
    if ([[theTab sessions] count] == 0) {
        [[theTab realParentWindow] closeTab:theTab];
    }
    [[[dest tab] realParentWindow] splitVertically:isVertical
                                            before:(half == kNorthHalf || half == kWestHalf)
                                     addingSession:movingSession
                                     targetSession:dest
                                      performSetup:NO];
    [oldView release];
    [[dest tab] fitSessionToCurrentViewSize:movingSession];
    return YES;
}

- (BOOL)isMovingSession:(PTYSession *)s
{
    return session_ == s;
}

- (void)beginDrag:(PTYSession *)session
{
    [self exitMovePaneMode];
    session_ = session;
    self.dragFailed = NO;
    NSPasteboard *pboard;

    pboard = [NSPasteboard pasteboardWithName:NSDragPboard];
    [pboard declareTypes:[NSArray arrayWithObjects:@"iTermDragPanePBType", nil] owner: nil];
    [pboard setString:@"" forType:@"iTermDragPanePBType"];

    PTYTab *theTab = [session tab];
    NSRect rect = [[[session view] superview] convertRect:[[session view] frame] toView:nil];
    SessionView *source = [session view];
    [source retain];
    didSplit_ = NO;
    NSWindow *theWindow = [[theTab realParentWindow] window];
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        [[term window] disableCursorRects];
    }
    [[NSCursor closedHandCursor] set];
    [theWindow dragImage:[session dragImage]
                      at:rect.origin
                  offset:NSZeroSize
                   event:[NSApp currentEvent]
              pasteboard:pboard
                  source:source
               slideBack:NO];
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        [[term window] enableCursorRects];
    }
    [[NSCursor openHandCursor] set];
    [source autorelease];
    session_ = nil;
}

#pragma mark Delegate

- (void)didSelectDestinationSession:(PTYSession *)dest
                               half:(SplitSessionHalf)half
{
    [self dropInSession:dest half:half atPoint:NSZeroPoint];
    [self exitMovePaneMode];
}

@end
