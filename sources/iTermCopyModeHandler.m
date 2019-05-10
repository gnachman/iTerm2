//
//  iTermCopyModeHandler.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/13/19.
//

#import "iTermCopyModeHandler.h"

#import "iTermCopyModeState.h"
#import "iTermNotificationController.h"
#import "NSEvent+iTerm.h"

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSUInteger, iTermCopyModeAction) {
    iTermCopyModeActionNone,

    iTermCopyModeActionCopySelection,
    iTermCopyModeActionExitCopyMode,
    iTermCopyModeActionMoveBackwardWord,
    iTermCopyModeActionMoveDown,
    iTermCopyModeActionMoveForwardWord,
    iTermCopyModeActionMoveLeft,
    iTermCopyModeActionMoveRight,
    iTermCopyModeActionMoveToBottomOfVisibleArea,
    iTermCopyModeActionMoveToEnd,
    iTermCopyModeActionMoveToEndOfLine,
    iTermCopyModeActionMoveToMiddleOfVisibleArea,
    iTermCopyModeActionMoveToStart,
    iTermCopyModeActionMoveToStartOfIndentation,
    iTermCopyModeActionMoveToStartOfLine,
    iTermCopyModeActionMoveToStartOfNextLine,
    iTermCopyModeActionMoveToTopOfVisibleArea,
    iTermCopyModeActionMoveUp,
    iTermCopyModeActionNextMark,
    iTermCopyModeActionPageDown,
    iTermCopyModeActionPageUp,
    iTermCopyModeActionPreviousMark,
    iTermCopyModeActionQuit,
    iTermCopyModeActionShowFindPanel,
    iTermCopyModeActionSwap,
    iTermCopyModeActionToggleBoxSelection,
    iTermCopyModeActionToggleCharacterSelection,
    iTermCopyModeActionToggleLineSelection,
};

static const NSEventModifierFlags sCopyModeEventModifierMask = (NSEventModifierFlagOption |
                                                                NSEventModifierFlagControl |
                                                                NSEventModifierFlagCommand);

@implementation iTermCopyModeHandler

- (void)setEnabled:(BOOL)copyMode {
    if (copyMode) {
        NSString *const key = @"NoSyncHaveUsedCopyMode";
        if ([[NSUserDefaults standardUserDefaults] objectForKey:key] == nil) {
            [self educateAboutCopyMode];
        }
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:key];
    }

    _enabled = copyMode;

    if (copyMode) {
        _state = [self.delegate copyModeHandlerCreateState:self];
    } else {
        _state = nil;
    }
    [self.delegate copyModeHandlerDidChangeEnabledState:self];
}

- (BOOL)wouldHandleEvent:(NSEvent *)event {
    // Reserve all keypresses except those with the command modifier. I don't
    // want users relying on some keystroke not being active in copy mode,
    // binding a shortcut to it, and later complaining when that keystroke
    // starts being used in copy mode. We never use command key in copy mode,
    // so that's safe.
    return ([self actionForEvent:event] != iTermCopyModeActionNone ||
            (event.it_modifierFlags & NSEventModifierFlagCommand) == 0);
}

- (BOOL)handleEvent:(NSEvent *)event {
    [self.delegate copyModeHandler:self redrawLine:_state.coord.y];
    BOOL wasSelecting = _state.selecting;

    const iTermCopyModeAction action = [self actionForEvent:event];
    if (![self wouldHandleEvent:event]) {
        return NO;
    }

    const BOOL moved = [self performAction:action];

    if (moved || (_state.selecting != wasSelecting)) {
        if (self.enabled) {
            [self.delegate copyModeHandler:self revealLine:_state.coord.y];
        }
        [self.delegate copyModeHandler:self redrawLine:_state.coord.y];
    }
    return YES;
}

- (BOOL)performAction:(iTermCopyModeAction)action {
    switch (action) {
        case iTermCopyModeActionPageUp:
            return [_state pageUp];
        case iTermCopyModeActionPageDown:
            return [_state pageDown];
        case iTermCopyModeActionToggleCharacterSelection:
            _state.selecting = !_state.selecting;
            _state.mode = kiTermSelectionModeCharacter;
            return NO;
        case iTermCopyModeActionExitCopyMode:
            self.enabled = NO;
            return NO;
        case iTermCopyModeActionCopySelection:
            [self.delegate copyModeHandlerCopySelection:self];
            self.enabled = NO;
            return NO;
        case iTermCopyModeActionToggleBoxSelection:
            _state.selecting = !_state.selecting;
            _state.mode = kiTermSelectionModeBox;
            return NO;
        case iTermCopyModeActionMoveBackwardWord:
            return [_state moveBackwardWord];
        case iTermCopyModeActionMoveForwardWord:
            return [_state moveForwardWord];
        case iTermCopyModeActionMoveToStartOfIndentation:
            return [_state moveToStartOfIndentation];
        case iTermCopyModeActionMoveToStartOfNextLine:
            return [_state moveToStartOfNextLine];
        case iTermCopyModeActionQuit:
            self.enabled = NO;
            _state.selecting = NO;
            return YES;
        case iTermCopyModeActionMoveToStartOfLine:
            return [_state moveToStartOfLine];
        case iTermCopyModeActionMoveToTopOfVisibleArea:
            return [_state moveToTopOfVisibleArea];
        case iTermCopyModeActionMoveToEnd:
            return [_state moveToEnd];
        case iTermCopyModeActionMoveToBottomOfVisibleArea:
            return [_state moveToBottomOfVisibleArea];
        case iTermCopyModeActionMoveToMiddleOfVisibleArea:
            return [_state moveToMiddleOfVisibleArea];
        case iTermCopyModeActionToggleLineSelection:
            _state.selecting = !_state.selecting;
            _state.mode = kiTermSelectionModeLine;
            return NO;
        case iTermCopyModeActionMoveToStart:
            return [_state moveToStart];
        case iTermCopyModeActionMoveLeft:
            return [_state moveLeft];
        case iTermCopyModeActionMoveDown:
            return [_state moveDown];
        case iTermCopyModeActionMoveUp:
            return [_state moveUp];
        case iTermCopyModeActionMoveRight:
            return [_state moveRight];
        case iTermCopyModeActionSwap:
            [_state swap];
            return YES;
        case iTermCopyModeActionShowFindPanel:
            [self.delegate copyModeHandlerShowFindPanel:self];
            return NO;
        case iTermCopyModeActionPreviousMark:
            return [_state previousMark];
        case iTermCopyModeActionNextMark:
            return [_state nextMark];
        case iTermCopyModeActionMoveToEndOfLine:
            return [_state moveToEndOfLine];
        case iTermCopyModeActionNone:
            return NO;
    }
}

- (iTermCopyModeAction)actionForEvent:(NSEvent *)event {
    NSString *const string = event.charactersIgnoringModifiers;
    const unichar code = [string length] > 0 ? [string characterAtIndex:0] : 0;

    if ((event.it_modifierFlags & sCopyModeEventModifierMask) == NSEventModifierFlagControl) {
        switch (code) {
            case 'b':
                return iTermCopyModeActionPageUp;
            case 'f':
                return iTermCopyModeActionPageDown;
            case ' ':
                return iTermCopyModeActionToggleCharacterSelection;
            case 'c':
            case 'g':
                return iTermCopyModeActionExitCopyMode;
            case 'k':
                return iTermCopyModeActionCopySelection;
            case 'v':
                return iTermCopyModeActionToggleBoxSelection;
        }
        return iTermCopyModeActionNone;
    }
    if ((event.it_modifierFlags & sCopyModeEventModifierMask) == NSEventModifierFlagOption) {
        switch (code) {
            case 'b':
            case NSLeftArrowFunctionKey:
                return iTermCopyModeActionMoveBackwardWord;
            case 'f':
            case NSRightArrowFunctionKey:
                return iTermCopyModeActionMoveForwardWord;
            case 'm':
                return iTermCopyModeActionMoveToStartOfIndentation;
        }
        return iTermCopyModeActionNone;
    }
    if ((event.it_modifierFlags & sCopyModeEventModifierMask) == 0) {
        switch (code) {
            case NSPageUpFunctionKey:
                return iTermCopyModeActionPageUp;
            case NSPageDownFunctionKey:
                return iTermCopyModeActionPageDown;
            case '\t':
                if (event.it_modifierFlags & NSEventModifierFlagShift) {
                    return iTermCopyModeActionMoveBackwardWord;
                } else {
                    return iTermCopyModeActionMoveForwardWord;
                }
            case '\n':
            case '\r':
                return iTermCopyModeActionMoveToStartOfNextLine;
            case 27:
            case 'q':
                return iTermCopyModeActionQuit;
            case ' ':
            case 'v':
                return iTermCopyModeActionToggleCharacterSelection;
            case 'b':
                return iTermCopyModeActionMoveBackwardWord;
            case '0':
                return iTermCopyModeActionMoveToStartOfLine;
            case 'H':
                return iTermCopyModeActionMoveToTopOfVisibleArea;
            case 'G':
                return iTermCopyModeActionMoveToEnd;
            case 'L':
                return iTermCopyModeActionMoveToBottomOfVisibleArea;
            case 'M':
                return iTermCopyModeActionMoveToMiddleOfVisibleArea;
            case 'V':
                return iTermCopyModeActionToggleLineSelection;
            case 'g':
                return iTermCopyModeActionMoveToStart;
            case 'h':
            case NSLeftArrowFunctionKey:
                return iTermCopyModeActionMoveLeft;
            case 'j':
            case NSDownArrowFunctionKey:
                return iTermCopyModeActionMoveDown;
            case 'k':
            case NSUpArrowFunctionKey:
                return iTermCopyModeActionMoveUp;
            case 'l':
            case NSRightArrowFunctionKey:
                return iTermCopyModeActionMoveRight;
            case 'o':
                return iTermCopyModeActionSwap;
            case 'w':
                return iTermCopyModeActionMoveForwardWord;
            case 'y':
                return iTermCopyModeActionCopySelection;
            case '/':
                return iTermCopyModeActionShowFindPanel;
            case '[':
                return iTermCopyModeActionPreviousMark;
            case ']':
                return iTermCopyModeActionNextMark;
            case '^':
                return iTermCopyModeActionMoveToStartOfIndentation;
            case '$':
                return iTermCopyModeActionMoveToEndOfLine;
        }
        return iTermCopyModeActionNone;
    }

    return iTermCopyModeActionNone;
}

- (void)educateAboutCopyMode {
    [[iTermNotificationController sharedInstance] postNotificationWithTitle:@"Copy Mode"
                                                                     detail:@"Copy Mode lets you make a selection with the keyboard. Click to view the manual."
                                                                        URL:[NSURL URLWithString:@"https://iterm2.com/documentation-copymode.html"]];
}


@end
