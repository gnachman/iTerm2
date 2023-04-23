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

@end

NS_ASSUME_NONNULL_END
