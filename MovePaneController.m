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

- (BOOL)dropInSession:(PTYSession *)dest
                 half:(SplitSessionHalf)half
{
    if (dest == session_ || !session_) {
        return NO;
    }

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

    NSPasteboard *pboard;

    pboard = [NSPasteboard pasteboardWithName:NSDragPboard];
    [pboard declareTypes:[NSArray arrayWithObjects:@"iTermDragPanePBType", nil] owner: nil];
    [pboard setString:@"" forType:@"iTermDragPanePBType"];

    PTYTab *theTab = [session tab];
    NSRect rect = [[[session view] superview] convertRect:[[session view] frame] toView:nil];
    SessionView *source = [session view];
    [source retain];
    [[[theTab realParentWindow] window] dragImage:[session dragImage]
                                               at:rect.origin
                                           offset:NSZeroSize
                                            event:[NSApp currentEvent]
                                       pasteboard:pboard
                                           source:source
                                        slideBack:YES];
    [source autorelease];
}

#pragma mark Delegate

- (void)didSelectDestinationSession:(PTYSession *)dest
                               half:(SplitSessionHalf)half
{
    [self dropInSession:dest half:half];
    [self exitMovePaneMode];
}

@end
