//
//  VT100ScreenMutableState+MRR.m
//  iTerm2
//
//  Created by George Nachman on 2/29/24.
//

#import "VT100ScreenMutableState+MRR.h"
#import "VT100ScreenMutableState+Private.h"
#import "VT100ScreenState+Private.h"

@implementation VT100ScreenMutableState(MRR)

- (void)fastTerminal:(VT100Terminal *)terminal
willExecuteToken:(VT100Token *)token
     defaultChar:(const screen_char_t *)defaultChar
            encoding:(NSStringEncoding)encoding {
    if (_primaryGrid) {
        _primaryGrid->_defaultChar = *defaultChar;
    }
    if (_altGrid) {
        _altGrid->_defaultChar = *defaultChar;
    }
    
    const BOOL hadDetectedPrompt = _triggerDidDetectPrompt;
    if (_autoComposerEnabled || token->type == XTERMCC_FINAL_TERM) {
        [_promptStateMachine handleToken:token withEncoding:encoding];
    }
    if (!hadDetectedPrompt && _triggerDidDetectPrompt) {
        // This is here to handle a very specific problem.
        // Suppose you have a prompt-detecting trigger but shell integration is otherwise working for FTCS B, C, and D (just not A).
        // When B arrives, the prompt state machine will ask its delegate to run triggers. The trigger will detect a prompt and schedule
        // a post-trigger action in -triggerSession:didDetectPromptAt:. Normally post-trigger actions cannot run during token processing
        // because the session could be in some weird state (there are so many tokens that could lead to prompt detection and I cannot
        // test them all). But in this case, we make an exception because we are in a controlled state where while a token is technically
        // executing nothing important has happened and it's safe to run post-trigger actions. At any rate, running the post-trigger
        // action at this time causes the prompt mark to be added before FTCS B is handled in the regular course of events.
        // Issue 10537.
        [self executePostTriggerActions];
    }
}

@end
