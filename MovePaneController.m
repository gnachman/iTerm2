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

#pragma mark Delegate

- (void)didSelectDestinationSession:(PTYSession *)dest
                               half:(SplitSessionHalf)half
{
    PTYSession *movingSession = session_;
    [self exitMovePaneMode];
    BOOL isVertical = (half == kWestHalf || half == kEastHalf);
    if (![[[dest tab] realParentWindow] canSplitPaneVertically:isVertical
                                                  withBookmark:[movingSession addressBookEntry]]) {
        NSBeep();
        return;
    }

    [movingSession retain];
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
    [[dest tab] fitSessionToCurrentViewSize:movingSession];
}

@end
