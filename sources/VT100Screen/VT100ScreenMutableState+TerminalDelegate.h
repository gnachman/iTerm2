//
//  VT100ScreenMutableState+TerminalDelegate.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/13/22.
//

#import "VT100ScreenMutableState.h"
#import "VT100Terminal.h"

NS_ASSUME_NONNULL_BEGIN

@interface VT100ScreenMutableState (TerminalDelegate)<VT100TerminalDelegate>

// A progress state reported the way OSC 9;4 reports one: sets the screen's progress and tells the
// delegate the program said so, which is what an expiring status listens for. Used by the status
// API on behalf of a program that reports through hooks but never emits the protocol itself.
- (void)setProgressFromProtocol:(VT100ScreenProgress)progress;

@end

NS_ASSUME_NONNULL_END
