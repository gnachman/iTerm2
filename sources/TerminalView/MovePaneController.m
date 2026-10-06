//
//  MovePaneController.m
//  iTerm2
//
//  Created by George Nachman on 8/26/11.

#import "MovePaneController.h"
#import "DebugLogging.h"
#import "iTermController.h"
#import "iTermPreferences.h"
#import "NSObject+iTerm.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "SessionView.h"
#import "TmuxController.h"
#import "iTerm2SharedARC-Swift.h"

NSString *const iTermMovePaneDragType = @"iTermDragPanePBType";
NSString *const iTermSessionDidChangeTabNotification = @"iTermSessionDidChangeTabNotification";

@implementation MovePaneController {
    // If set then moving pane; otherwise swapping.
    BOOL isMove_;

    // The session being moved.
    PTYSession *session_;  // weak

    BOOL dragFailed_;
    BOOL didSplit_;

    // The dragged session was a float when the drag began.
    BOOL _draggingFloatingPane;

    // Where the pointer held the dragged session's view, from its top left, in points.
    NSSize _grabOffset;

    // Tabs whose floats are hidden because Control is held during the drag.
    NSMutableSet<PTYTab *> *_tabsHidingFloatingPanes;
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
        RLog(@"Decline because we already have a session %@", session_);
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
    if (session.delegate.realParentWindow.layoutLocked) {
        DLog(@"Layout is locked, refusing to move");
        return;
    }
    if (session.locked) {
        DLog(@"Session is locked, refusing to move");
        return;
    }
    [self startWithSession:session move:YES];
}

- (void)swapPane:(PTYSession *)session {
    DLog(@"swapPane:%@", session);
    if (session.delegate.realParentWindow.layoutLocked) {
        DLog(@"Layout is locked, refusing to swap");
        return;
    }
    if (session.locked) {
        DLog(@"Session is locked, refusing to swap");
        return;
    }
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

- (void)moveSessionToTab:(PTYSession *)movingSession {
    DLog(@"moveSessionToTab:%@", movingSession);
    if (movingSession.delegate.realParentWindow.layoutLocked) {
        DLog(@"Layout is locked, refusing to move session to a new tab");
        return;
    }
    PseudoTerminal *term = [PseudoTerminal castFrom:[movingSession.delegate realParentWindow]];
    if (!term) {
        return;
    }
    (void)[self moveSession:movingSession toNewTabIn:term atIndex:-1];
}

- (void)moveSessionToNewWindow:(PTYSession *)movingSession atPoint:(NSPoint)point {
    DLog(@"moveSessionToNewWindow:%@ atPoint:%@", movingSession, NSStringFromPoint(point));
    if (movingSession.delegate.realParentWindow.layoutLocked) {
        DLog(@"Layout is locked, refusing to move session to a new window");
        return;
    }
    if (movingSession.locked) {
        DLog(@"Locked");
        return;
    }
    if ([movingSession isTmuxClient]) {
        [[movingSession tmuxController] breakOutWindowPane:[movingSession tmuxPane]
                                                   toPoint:point];
        return;
    }
    PseudoTerminal *sourceTerm = [[iTermController sharedInstance] windowForSession:movingSession];
    if (!sourceTerm) {
        return;
    }
    NSWindowController<iTermWindowController> *newTerm =
        [sourceTerm terminalDraggedFromAnotherWindowAtPoint:point];
    if (!newTerm) {
        return;
    }
    (void)[self moveSession:movingSession toNewTabIn:(PseudoTerminal *)newTerm atIndex:0];
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
    RLog(@"reallyDropInSession:%@ half:%@ atPoint:%@", dest, @(half), NSStringFromPoint(point));
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
    [self beginDrag:session grabPointInWindow:[NSApp currentEvent].locationInWindow];
}

- (void)beginDrag:(PTYSession *)session grabPointInWindow:(NSPoint)grabPoint {
    DLog(@"beginDrag:%@ grabPoint:%@", session, NSStringFromPoint(grabPoint));
    if (session.delegate.realParentWindow.layoutLocked) {
        DLog(@"Layout is locked, refusing to drag");
        return;
    }
    if (session.locked) {
        DLog(@"Session is locked, refusing to drag");
        return;
    }
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
    _grabOffset = NSMakeSize(grabPoint.x - NSMinX(rect), NSMaxY(rect) - grabPoint.y);
    // Put the image under the pointer, held where the view was grabbed.
    const NSPoint pointer = [NSApp currentEvent].locationInWindow;
    const NSPoint imageOrigin = NSMakePoint(pointer.x - _grabOffset.width,
                                            pointer.y + _grabOffset.height - NSHeight(rect));
    _draggingFloatingPane = [theTab sessionIsFloating:session] && !theTab.isTmuxTab;
    NSWindow *theWindow = [[theTab realParentWindow] window];
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        [[term window] disableCursorRects];
    }
    [[NSCursor closedHandCursor] set];
    _isDragInProgress = YES;
    // Force tab bars to remain visible while a session is dragged so that
    // single-tab destination windows can act as drop targets — same fix as
    // for tab drags in PSMTabDragAssistant. See iTerm2 issue 12846.
    [iTermPreferences setHideTabBarSuppressedDuringDrag:YES];
    [theWindow dragImage:[session dragImage]
                      at:imageOrigin
                  offset:NSZeroSize
                   event:[NSApp currentEvent]
              pasteboard:pboard
                  source:source
               slideBack:NO];
    [iTermPreferences setHideTabBarSuppressedDuringDrag:NO];
    _isDragInProgress = NO;
    [self showFloatingPanesHiddenForDrag];
    _draggingFloatingPane = NO;
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        [[term window] enableCursorRects];
    }
    [[NSCursor openHandCursor] set];
    [source autorelease];
    session_ = nil;
}

#pragma mark Floating panes

- (BOOL)controlIsHeld {
    return ([NSEvent modifierFlags] & NSEventModifierFlagControl) != 0;
}

- (BOOL)dropPlacesFloatingPaneOverFloat:(BOOL)overFloat {
    if (!_isDragInProgress || !session_) {
        return NO;
    }
    return overFloat || (_draggingFloatingPane && ![self controlIsHeld]);
}

- (void)dragDidMove {
    if (!_isDragInProgress) {
        return;
    }
    if (![self controlIsHeld]) {
        [self showFloatingPanesHiddenForDrag];
        return;
    }
    if (!_tabsHidingFloatingPanes) {
        _tabsHidingFloatingPanes = [[NSMutableSet alloc] init];
    }
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        PTYTab *tab = term.currentTab;
        if (tab.floatingPanes.count == 0 || tab.floatingPanesTemporarilyHidden) {
            continue;
        }
        DLog(@"Hide floats in %@ while Control is held during a drag", tab);
        tab.floatingPanesTemporarilyHidden = YES;
        [_tabsHidingFloatingPanes addObject:tab];
    }
}

- (void)showFloatingPanesHiddenForDrag {
    for (PTYTab *tab in _tabsHidingFloatingPanes) {
        tab.floatingPanesTemporarilyHidden = NO;
    }
    [_tabsHidingFloatingPanes removeAllObjects];
}

- (BOOL)dropFloatingPaneInTab:(PTYTab *)destinationTab atWindowPoint:(NSPoint)point {
    // The drop is handled here, so the end of the drag must not also move the session to a new
    // window.
    didSplit_ = YES;
    PTYSession *movingSession = session_;
    PTYTab *sourceTab = [movingSession.delegate.realParentWindow tabForSession:movingSession];
    RLog(@"Drop %@ as a float in %@ at %@", movingSession, destinationTab, NSStringFromPoint(point));
    if (!movingSession || !sourceTab || !destinationTab) {
        return NO;
    }
    if (movingSession.isTmuxClient || sourceTab.isTmuxTab || destinationTab.isTmuxTab) {
        DLog(@"tmux floats are not supported");
        return NO;
    }
    if (destinationTab.realParentWindow.layoutLocked || movingSession.liveSession) {
        DLog(@"Layout locked or showing a synthetic session");
        return NO;
    }
    const BOOL wasFloating = [sourceTab sessionIsFloating:movingSession];
    if (sourceTab == destinationTab && !wasFloating) {
        DLog(@"A tiled pane dropped on a float in its own tab stays where it is");
        return NO;
    }
    NSView *container = destinationTab.realRootView;
    if (!container) {
        return NO;
    }
    // Keep the pointer where it held the session's view. The float's outline sits just outside it.
    const NSPoint topLeftInWindow = NSMakePoint(point.x - _grabOffset.width - [iTermFloatingPaneView outlineWidth],
                                                point.y + _grabOffset.height + [iTermFloatingPaneView outlineWidth]);
    const NSPoint topLeftInContainer = [container convertPoint:topLeftInWindow fromView:nil];
    const NSPoint visualTopLeft = NSMakePoint(topLeftInContainer.x,
                                              container.isFlipped ? topLeftInContainer.y : NSHeight(container.bounds) - topLeftInContainer.y);
    const int columns = movingSession.columns;
    const int rows = movingSession.rows;

    if (sourceTab == destinationTab) {
        iTermFloatingPaneView *pane = [destinationTab floatingPaneForSession:movingSession];
        [iTermFloatingPaneLayout placeFloatingPane:pane session:movingSession visualTopLeft:visualTopLeft columns:columns rows:rows];
        [destinationTab floatingPanesDidChange];
        return YES;
    }

    [[movingSession retain] autorelease];
    [[movingSession.view retain] autorelease];
    if ([sourceTab hasMaximizedPane]) {
        [sourceTab unmaximize];
    }
    [sourceTab removeSession:movingSession];
    if (sourceTab.sessions.count == 0) {
        [[sourceTab realParentWindow] closeTab:sourceTab];
    } else {
        [sourceTab numberOfSessionsDidChange];
        [sourceTab updateSessionOrdinals];
    }

    iTermFloatingPaneView *pane = [destinationTab installFloatingSession:movingSession
                                                            outlineFrame:NSMakeRect(0, 0, 100, 100)];
    [iTermFloatingPaneLayout placeFloatingPane:pane session:movingSession visualTopLeft:visualTopLeft columns:columns rows:rows];
    [iTermFloatingPaneLayout updateUnderlayOfFloatingPane:pane session:movingSession];
    [destinationTab setActiveSession:movingSession];
    [destinationTab updateSessionOrdinals];
    [destinationTab recheckBlur];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermSessionDidChangeTabNotification object:movingSession];
    [movingSession didMoveSession];
    return YES;
}

#pragma mark Delegate

- (void)didSelectDestinationSession:(PTYSession *)session half:(SplitSessionHalf)half {
    [self dropInSession:session half:half atPoint:NSZeroPoint];
    [self exitMovePaneMode];
}

@end
