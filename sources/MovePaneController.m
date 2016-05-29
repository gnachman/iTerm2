//
//  MovePaneController.m
//  iTerm2
//
//  Created by George Nachman on 8/26/11.

#import "MovePaneController.h"
#import "DebugLogging.h"
#import "iTermController.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "SessionView.h"
#import "TmuxController.h"

NSString *const iTermMovePaneDragType = @"iTermDragPanePBType";

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
    [self startWithSession:session move:YES];
}

- (void)swapPane:(PTYSession *)session {
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

- (void)moveSessionToNewWindow:(PTYSession *)movingSession atPoint:(NSPoint)point {
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
// If two calls are made, the both have dest non-null but only the first call will perform a split.
// The second call will do nothing.
// It isn't called at all if a session is dragged into an existing tab bar.
- (BOOL)dropInSession:(PTYSession *)dest
                 half:(SplitSessionHalf)half
              atPoint:(NSPoint)point {
    if ((dest && ![session_ isCompatibleWith:dest]) ||  // Would create hetero-tmuxual splits in tab
        dest == session_ ||  // move to self
        !session_) {         // no source (?)
        didSplit_ = YES;
        return NO;
    }

    if (!dest && !didSplit_) {
        // We were not called before, so move the session to a new window.
        [self moveSessionToNewWindow:session_ atPoint:point];
        return YES;
    } else if (!dest) {
        // This is the second call and a split has already been performed/aborted.
        return NO;
    }

    didSplit_ = YES;

    if ([self.session isTmuxClient]) {
        // Do this after setting didSplit becasue a second call to this method
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
        return YES;
    }

    PTYTab *destinationTab = [dest.delegate.realParentWindow tabForSession:dest];
    if (isMove_) {
        PTYSession *movingSession = session_;
        BOOL isVertical = (half == kWestHalf || half == kEastHalf);
        if (![[destinationTab realParentWindow] canSplitPaneVertically:isVertical
                                                          withBookmark:[movingSession profile]]) {
            return NO;
        }

        SessionView *oldView = [movingSession view];
        [[oldView retain] autorelease];
        [[movingSession retain] autorelease];
        PTYTab *theTab = [movingSession.delegate.realParentWindow tabForSession:movingSession];
        [theTab removeSession:movingSession];
        if ([[theTab sessions] count] == 0) {
            [[theTab realParentWindow] closeTab:theTab];
        }

        [[destinationTab realParentWindow] splitVertically:isVertical
                                                    before:(half == kNorthHalf || half == kWestHalf)
                                             addingSession:movingSession
                                             targetSession:dest
                                              performSetup:NO];
        [destinationTab fitSessionToCurrentViewSize:movingSession];
    } else {
        [destinationTab swapSession:dest withSession:session_];
    }
    return YES;
}

- (BOOL)isMovingSession:(PTYSession *)s
{
    return session_ == s;
}

- (void)beginDrag:(PTYSession *)session {
    isMove_ = YES;
    [self exitMovePaneMode];
    session_ = session;
    self.dragFailed = NO;
    NSPasteboard *pboard;

    pboard = [NSPasteboard pasteboardWithName:NSDragPboard];
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

- (void)didSelectDestinationSession:(PTYSession *)session half:(SplitSessionHalf)half {
    [self dropInSession:session half:half atPoint:NSZeroPoint];
    [self exitMovePaneMode];
}

@end
