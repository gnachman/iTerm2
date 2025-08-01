//
//  MovePaneController.m
//  iTerm2
//
//  Created by George Nachman on 8/26/11.

#import "MovePaneController.h"
#import "DebugLogging.h"
#import "iTermController.h"
#import "NSObject+iTerm.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "SessionView.h"
#import "TmuxController.h"

NSString *const iTermMovePaneDragType = @"iTermDragPanePBType";
NSString *const iTermSessionDidChangeTabNotification = @"iTermSessionDidChangeTabNotification";

@implementation MovePaneController {
    // If set then moving pane; otherwise swapping.
    BOOL isMove_;

    // The session being moved.
    PTYSession *session_;  // weak

    BOOL dragFailed_;
    BOOL didSplit_;
}

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

- (instancetype)init {
    self = [super init];
    if (self) {
        isMove_ = YES;
    }
    return self;
}

- (void)startWithSession:(PTYSession *)session move:(BOOL)move {
    if (session_) {
        DLog(@"Decline because we already have a session %@", session_);
        return;
    }
    DLog(@"startWithSession:%@ move:%@\n%@", session, @(move), [NSThread callStackSymbols]);
    isMove_ = move;
    session_ = [session liveSession];
    if (!session_) {
        session_ = session;
    }
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        [term setSplitSelectionMode:YES excludingSession:session_ move:move];
    }
}

- (void)movePane:(PTYSession *)session {
    DLog(@"movePane:%@", session);
    [self startWithSession:session move:YES];
}

- (void)swapPane:(PTYSession *)session {
    DLog(@"swapPane:%@", session);
    [self startWithSession:session move:NO];
}

- (void)exitMovePaneMode
{
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        [term setSplitSelectionMode:NO excludingSession:nil move:NO];
    }
    session_ = nil;
}

- (void)moveWindowBy:(NSPoint)point {
    NSWindow *window = session_.delegate.realParentWindow.window;
    NSPoint origin = window.frame.origin;
    origin.x += point.x;
    origin.y += point.y;
    DLog(@"Move window from %@ to %@",
         NSStringFromPoint(window.frame.origin), NSStringFromPoint(origin));
    [window setFrameOrigin:origin];
}

- (void)moveSession:(PTYSession *)movingSession toTabInWindow:(NSWindow *)window {
    PTYTab *oldTab = [movingSession.delegate.realParentWindow tabForSession:movingSession];
    assert(oldTab);
    if (oldTab.sessions.count < 2) {
        return;
    }

    NSWindowController<iTermWindowController> *term = oldTab.realParentWindow;

    if (movingSession.isTmuxClient) {
        [[movingSession tmuxController] breakOutWindowPane:[movingSession tmuxPane]
                                                toTabAside:term.terminalGuid];
        return;
    }
    SessionView *oldView = movingSession.view;
    [[oldView retain] autorelease];
    [[movingSession retain] autorelease];

    [oldTab removeSession:movingSession];
    NSInteger i = [term.tabs indexOfObject:oldTab];
    if (i == NSNotFound) {
        // I don't think this should be possible. It is just paranoia.
        i = term.tabs.count;
    } else {
        i += 1;
    }
    [term insertSession:movingSession atIndex:i];
    [oldTab numberOfSessionsDidChange];
    [term.currentTab numberOfSessionsDidChange];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermSessionDidChangeTabNotification object:movingSession];
    [movingSession didMoveSession];
}

- (void)moveSessionToNewWindow:(PTYSession *)movingSession atPoint:(NSPoint)point {
    DLog(@"moveSessionToNewWindow:%@", movingSession);
    if ([movingSession isTmuxClient]) {
        [[movingSession tmuxController] breakOutWindowPane:[movingSession tmuxPane]
                                                   toPoint:point];
        return;
    }
    PTYTab *theTab = [movingSession.delegate.realParentWindow tabForSession:movingSession];
    NSWindowController<iTermWindowController> *term =
        [[theTab realParentWindow] terminalDraggedFromAnotherWindowAtPoint:point];

    SessionView *oldView = [movingSession view];
    [oldView retain];

    // Prevent -removeSession from freeing the session.
    [[movingSession retain] autorelease];

    [theTab removeSession:movingSession];
    if ([[theTab sessions] count] == 0) {
        [[theTab realParentWindow] closeTab:theTab];
    }

    [term insertSession:movingSession atIndex:0];
    [oldView autorelease];
    [theTab numberOfSessionsDidChange];
    [[term currentTab] numberOfSessionsDidChange];

    [[NSNotificationCenter defaultCenter] postNotificationName:iTermSessionDidChangeTabNotification object:movingSession];
    [movingSession didMoveSession];
}

+ (void)moveTab:(PTYTab *)tab toWindow:(PseudoTerminal *)term atIndex:(NSInteger)index {
    PseudoTerminal *sourceTerm = [PseudoTerminal castFrom:tab.realParentWindow];
    assert(sourceTerm);
    NSInteger sourceIndex = [sourceTerm.tabs indexOfObject:tab];
    assert(sourceIndex != NSNotFound);
    [sourceTerm.tabBarControl moveTabAtIndex:sourceIndex toTabBar:term.tabBarControl atIndex:index];
}

- (void)clearSession
{
    session_ = nil;
}

- (SessionView *)removeAndClearSession
{
    SessionView *oldView = [session_ view];
    [oldView retain];
    PTYSession *movingSession = session_;
    PTYTab *theTab = [movingSession.delegate.realParentWindow tabForSession:movingSession];
    [movingSession.delegate removeSession:movingSession];
    if ([[theTab sessions] count] == 0) {
        [[theTab realParentWindow] closeTab:theTab];
    }
    session_ = nil;
    return [oldView autorelease];
}

- (BOOL)dropTab:(PTYTab *)tab
      inSession:(PTYSession *)dest
           half:(SplitSessionHalf)half
        atPoint:(NSPoint)point {
    DLog(@"dropTab:%@ inSession:%@ half:%@ point:%@", tab, dest, @(half), NSStringFromPoint(point));
    _dropping = YES;
    isMove_ = YES;
    const BOOL result = [self reallyDropTab:tab inSession:dest half:half atPoint:point];
    _dropping = NO;
    return result;
}

- (BOOL)reallyDropTab:(PTYTab *)tab
            inSession:(PTYSession *)dest
                 half:(SplitSessionHalf)half
              atPoint:(NSPoint)point
{
    if ([[tab sessions] count] != 1) {
        // This sometimes can't be done at all, and it usually can't be done right if tabs' sizes
        // differ, etc. Just wimp out, basically.
        DLog(@"Tab has multiple sessions. Abort.");
        return NO;
    }

    session_ = [[tab sessions] objectAtIndex:0];
    return [self dropInSession:dest half:half atPoint:point];
}

// This function is either called once or twice at the end of a drag.
// If only one call is made, then dest will be nil and the session will be moved to a new window.
// If two calls are made, the both have dest non-null but only the first call will perform a split.
// The second call will do nothing.
// It isn't called at all if a session is dragged into an existing tab bar.
- (BOOL)dropInSession:(PTYSession *)dest
                 half:(SplitSessionHalf)half
              atPoint:(NSPoint)point {
    _dropping = YES;
    const BOOL result = [self reallyDropInSession:dest half:half atPoint:point];
    _dropping = NO;
    return result;
}

- (BOOL)reallyDropInSession:(PTYSession *)dest
                       half:(SplitSessionHalf)half
                    atPoint:(NSPoint)point {
    DLog(@"reallyDropInSession:%@ half:%@ atPoint:%@", dest, @(half), NSStringFromPoint(point));
    if ((dest && ![session_ isCompatibleWith:dest]) ||  // Would create hetero-tmuxual splits in tab
        dest == session_ ||  // move to self
        !session_) {         // no source (?)
        DLog(@"Abort because of heterotmuxuality, move to self, or no source");
        didSplit_ = YES;
        return NO;
    }

    if (!dest && !didSplit_) {
        // We were not called before, so move the session to a new window.
        [self moveSessionToNewWindow:session_ atPoint:point];
        return YES;
    } else if (!dest) {
        // This is the second call and a split has already been performed/aborted.
        DLog(@"Split was already peformed/aborted");
        return NO;
    }

    didSplit_ = YES;

    if ([self.session isTmuxClient]) {
        DLog(@"Moving tmux session");
        // Do this after setting didSplit because a second call to this method
        // will happen no matter what and we want it to do nothing if we get
        // here.
        if (isMove_) {
            [[self.session tmuxController] movePane:[self.session tmuxPane]
                                           intoPane:[dest tmuxPane]
                                         isVertical:(half == kEastHalf || half == kWestHalf)
                                             before:(half == kNorthHalf || half == kWestHalf)];
        } else {
            [[self.session tmuxController] swapPane:[self.session tmuxPane]
                                           withPane:[dest tmuxPane]];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermSessionDidChangeTabNotification object:self.session];
        return YES;
    }

    PTYTab *destinationTab = [dest.delegate.realParentWindow tabForSession:dest];
    if (isMove_) {
        DLog(@"Will move");
        [destinationTab checkInvariants:@"Before move"];
        PTYSession *movingSession = session_;
        BOOL isVertical = (half == kWestHalf || half == kEastHalf);
        if (![[destinationTab realParentWindow] canSplitPaneVertically:isVertical
                                                          withBookmark:[movingSession profile]]) {
            DLog(@"Cannot split");
            return NO;
        }

        SessionView *oldView = [movingSession view];
        [[oldView retain] autorelease];
        [[movingSession retain] autorelease];
        PTYTab *theTab = [movingSession.delegate.realParentWindow tabForSession:movingSession];
        [theTab removeSession:movingSession];
        const NSUInteger sourceCount = theTab.sessions.count;
        if (sourceCount == 0) {
            DLog(@"Moving tab without sessions. Closing it");
            [[theTab realParentWindow] closeTab:theTab];
        }

        [[destinationTab realParentWindow] splitVertically:isVertical
                                                    before:(half == kNorthHalf || half == kWestHalf)
                                             addingSession:movingSession
                                             targetSession:dest
                                              performSetup:NO];
        [destinationTab fitSessionToCurrentViewSize:movingSession];
        [destinationTab checkInvariants:@"After move"];
        [destinationTab updateSessionOrdinals];
        if (sourceCount) {
            [theTab updateSessionOrdinals];
        }
    } else {
        DLog(@"Will swap");
        [destinationTab checkInvariants:@"Before swap"];
        [destinationTab swapSession:dest withSession:session_];
        [destinationTab checkInvariants:@"After swap"];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermSessionDidChangeTabNotification object:self.session];
    return YES;
}

- (BOOL)isMovingSession:(PTYSession *)s
{
    return session_ == s;
}

- (void)beginDrag:(PTYSession *)session {
    DLog(@"beginDrag:%@", session);
    isMove_ = YES;
    [self exitMovePaneMode];
    session_ = session;
    self.dragFailed = NO;
    NSPasteboard *pboard;

    pboard = [NSPasteboard pasteboardWithName:NSPasteboardNameDrag];
    [pboard declareTypes:@[ iTermMovePaneDragType ] owner: nil];
    [pboard setString:@"" forType:iTermMovePaneDragType];

    PTYTab *theTab = [session.delegate.realParentWindow tabForSession:session];
    NSRect rect = [[[session view] superview] convertRect:[[session view] frame] toView:nil];
    SessionView *source = [session view];
    [source retain];
    didSplit_ = NO;
    NSWindow *theWindow = [[theTab realParentWindow] window];
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        [[term window] disableCursorRects];
    }
    [[NSCursor closedHandCursor] set];
    _isDragInProgress = YES;
    [theWindow dragImage:[session dragImage]
                      at:rect.origin
                  offset:NSZeroSize
                   event:[NSApp currentEvent]
              pasteboard:pboard
                  source:source
               slideBack:NO];
    _isDragInProgress = NO;
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        [[term window] enableCursorRects];
    }
    [[NSCursor openHandCursor] set];
    [source autorelease];
    session_ = nil;
}

#pragma mark Delegate

- (void)didSelectDestinationSession:(PTYSession *)session half:(SplitSessionHalf)half {
    [self dropInSession:session half:half atPoint:NSZeroPoint];
    [self exitMovePaneMode];
}

@end
