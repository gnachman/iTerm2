//
//  VT100PromptKind.h
//  iTerm2
//
//  OSC 133 `k=` (Semantic Prompt) attribute. Defined here separately from
//  VT100TerminalDelegate.h so that lightweight consumers (e.g. VT100ScreenMark)
//  can pick up just the enum without pulling in the full delegate protocol's
//  dependency chain.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, VT100PromptKind) {
    VT100PromptKindInitial = 0,       // k=i, k missing — primary first-line prompt
    VT100PromptKindSecondary,         // k=s — secondary continuation (PS2-style; not re-editable)
    VT100PromptKindContinuation,      // k=c — continuation (re-editable across lines)
    VT100PromptKindRight,             // k=r — right-aligned prompt
    VT100PromptKindUnknown            // k=<anything else>
};
