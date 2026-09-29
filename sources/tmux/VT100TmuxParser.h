//
//  VT100TmuxParser.h
//  iTerm
//
//  Created by George Nachman on 3/10/14.
//
//

#import <Foundation/Foundation.h>
#import "VT100Token.h"
#import "iTermParser.h"
#import "VT100DCSParser.h"

@interface VT100TmuxParser : NSObject <VT100DCSParserHook>

// tmux 1.8 could send %exit inside a %begin/%end block with no closing guard, so while this is
// YES a %exit line inside a response block ends tmux mode. Every later server closes the block
// first, so once the server is known to be at least 1.9 this should be NO: a %exit line inside a
// block is then response data, such as capture-pane output from a pane whose scrollback holds
// control-mode text. Defaults to YES until the version is known. Set on the mutation thread (via
// VT100Parser, under its lock), read from the parser thread.
@property(atomic) BOOL serverMayOmitEndGuardBeforeExit;

- (instancetype)initInRecoveryMode;
@end
