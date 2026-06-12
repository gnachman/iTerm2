//
//  iTermClickSideEffects.h
//  iTerm2
//
//  Created by George Nachman on 7/5/21.
//

typedef NS_OPTIONS(NSUInteger, iTermClickSideEffects) {
    iTermClickSideEffectsNone = 0,
    iTermClickSideEffectsModifySelection = (1 << 0),
    iTermClickSideEffectsPerformBoundAction = (1 << 1),
    iTermClickSideEffectsOpenTarget = (1 << 2),
    iTermClickSideEffectsReport = (1 << 3),
    iTermClickSideEffectsMoveCursor = (1 << 4),
    iTermClickSideEffectsMoveFindOnPageCursor = (1 << 5),
    iTermClickSideEffectsOpenPasswordManager = (1 << 6),
    iTermClickSideEffectsDrag = (1 << 7),

    iTermClickSideEffectsIgnore = 0xfffffffffffffffULL
};

typedef NS_ENUM(NSUInteger, iTermMouseState) {
    iTermMouseStateUp,
    iTermMouseStateDown,
    iTermMouseStateDrag
};
