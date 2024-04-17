//
//  iTermCopyModeHandler.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/13/19.
//

#import "iTermCopyModeHandler.h"

#import "iTermCopyModeState.h"
#import "iTermNSKeyBindingEmulator.h"
#import "iTermNotificationController.h"
#import "iTermPreferences.h"
#import "NSEvent+iTerm.h"
#import "NSFileManager+iTerm.h"

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSUInteger, iTermCopyModeAction) {
    iTermCopyModeActionNone,
    iTermCopyModeActionCopySelection,
    iTermCopyModeActionExitCopyMode,
    iTermCopyModeActionMoveBackwardWord,
    iTermCopyModeActionMoveBackwardBigWord,
    iTermCopyModeActionMoveDown,
    iTermCopyModeActionMoveForwardWord,
    iTermCopyModeActionMoveForwardBigWord,
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
    iTermCopyModeActionAccrueCount,
    iTermCopyModeActionMoveToStartOfLineOrAccrue0,
    iTermCopyModeActionPageDownHalfScreen,
    iTermCopyModeActionPageUpHalfScreen,
    iTermCopyModeActionScrollUp,
    iTermCopyModeActionScrollDown,

    iTermCopyModeAction_Count
};

static NSString *iTermCopyModeActionName(iTermCopyModeAction action) {
    switch (action) {
        case iTermCopyModeActionNone:
            return @"None";
        case iTermCopyModeActionCopySelection:
            return @"CopySelection";
        case iTermCopyModeActionExitCopyMode:
            return @"ExitCopyMode";
        case iTermCopyModeActionMoveBackwardWord:
            return @"MoveBackwardWord";
        case iTermCopyModeActionMoveBackwardBigWord:
            return @"MoveBackwardBigWord";
        case iTermCopyModeActionMoveDown:
            return @"MoveDown";
        case iTermCopyModeActionMoveForwardWord:
            return @"MoveForwardWord";
        case iTermCopyModeActionMoveForwardBigWord:
            return @"MoveForwardBigWord";
        case iTermCopyModeActionMoveLeft:
            return @"MoveLeft";
        case iTermCopyModeActionMoveRight:
            return @"MoveRight";
        case iTermCopyModeActionMoveToBottomOfVisibleArea:
            return @"MoveToBottomOfVisibleArea";
        case iTermCopyModeActionMoveToEnd:
            return @"MoveToEnd";
        case iTermCopyModeActionMoveToEndOfLine:
            return @"MoveToEndOfLine";
        case iTermCopyModeActionMoveToMiddleOfVisibleArea:
            return @"MoveToMiddleOfVisibleArea";
        case iTermCopyModeActionMoveToStart:
            return @"MoveToStart";
        case iTermCopyModeActionMoveToStartOfIndentation:
            return @"MoveToStartOfIndentation";
        case iTermCopyModeActionMoveToStartOfLine:
            return @"MoveToStartOfLine";
        case iTermCopyModeActionMoveToStartOfNextLine:
            return @"MoveToStartOfNextLine";
        case iTermCopyModeActionMoveToTopOfVisibleArea:
            return @"MoveToTopOfVisibleArea";
        case iTermCopyModeActionMoveUp:
            return @"MoveUp";
        case iTermCopyModeActionNextMark:
            return @"NextMark";
        case iTermCopyModeActionPageDown:
            return @"PageDown";
        case iTermCopyModeActionPageUp:
            return @"PageUp";
        case iTermCopyModeActionPreviousMark:
            return @"PreviousMark";
        case iTermCopyModeActionQuit:
            return @"Quit";
        case iTermCopyModeActionShowFindPanel:
            return @"ShowFindPanel";
        case iTermCopyModeActionSwap:
            return @"Swap";
        case iTermCopyModeActionToggleBoxSelection:
            return @"ToggleBoxSelection";
        case iTermCopyModeActionToggleCharacterSelection:
            return @"ToggleCharacterSelection";
        case iTermCopyModeActionToggleLineSelection:
            return @"ToggleLineSelection";
        case iTermCopyModeActionAccrueCount:
            return @"AccrueCount";
        case iTermCopyModeActionMoveToStartOfLineOrAccrue0:
            return @"MoveToStartOfLineOrAccrue0";
        case iTermCopyModeActionPageDownHalfScreen:
            return @"PageDownHalfScreen";
        case iTermCopyModeActionPageUpHalfScreen:
            return @"PageUpHalfScreen";
        case iTermCopyModeActionScrollUp:
            return @"ScrollUp";
        case iTermCopyModeActionScrollDown:
            return @"ScrollDown";

        case iTermCopyModeAction_Count:
            break;
    }
    return @"Undefined";
}

iTermCopyModeAction iTermCopyModeActionFromName(NSString *name, BOOL *ok) {
    for (NSUInteger i = 0; i < iTermCopyModeAction_Count; i++) {
        if ([iTermCopyModeActionName(i) isEqualToString:name]) {
            *ok = YES;
            return i;
        }
    }
    *ok = NO;
    return iTermCopyModeActionNone;
}

@implementation iTermCopyModeHandler {
    iTermNSKeyBindingEmulator *_keyBindingEmulator;
    // 0: Regular state, perform action once. "MoveToStartOfLineOrAccrue0" moves to start of line.
    // 1..inf: Perform action this many times. "MoveToStartOfLineOrAccrue0" accrues a digit.
    NSInteger _count;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _count = 0;
        NSString *path;
        path = [[[NSFileManager defaultManager] applicationSupportDirectoryWithoutCreating] stringByAppendingPathComponent:@"CopyModeKeyBindings.dict"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            path = [[NSBundle bundleForClass:[iTermCopyModeHandler class]] pathForResource:@"iTermCopyModeKeyBindings" ofType:@"dict"];
        }

        _keyBindingEmulator = [[iTermNSKeyBindingEmulator alloc] initWithFile:path allowedActions:nil];
    }
    return self;
}

- (void)setEnabled:(BOOL)copyMode {
    if (copyMode && [self shouldAutoEnterWithEventIgnoringPrefs:NSApp.currentEvent]) {
        // This is a cute hack. If you bind a keystroke to enable copy mode then we treat it as an
        // auto-enter if possible so the cursor will be at the right side of the selection. Issue 10164.
        [self handleAutoEnteringEvent:NSApp.currentEvent];
        return;
    }
    [self setEnabledWithoutCleverness:copyMode];
}

- (void)setEnabledWithoutCleverness:(BOOL)copyMode {
    if (copyMode) {
        NSString *const key = @"NoSyncHaveUsedCopyMode";
        if ([[NSUserDefaults standardUserDefaults] objectForKey:key] == nil) {
            [self educateAboutCopyMode];
        }
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:key];
    }

    _enabled = copyMode;
    _count = 0;
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
    // so that's safe.z
    return ([self actionForEvent:event] != iTermCopyModeActionNone ||
            (event.it_modifierFlags & NSEventModifierFlagCommand) == 0);
}

- (NSInteger)autoEnterEventDirection:(NSEvent *)event {
    NSString *const string = event.charactersIgnoringModifiers;
    const unichar code = [string length] > 0 ? [string characterAtIndex:0] : 0;
    switch (code) {
        case NSPageUpFunctionKey:
        case NSLeftArrowFunctionKey:
        case NSUpArrowFunctionKey:
        case NSHomeFunctionKey:
            return -1;

        case NSPageDownFunctionKey:
        case NSDownArrowFunctionKey:
        case NSRightArrowFunctionKey:
        case NSEndFunctionKey:
            return 1;

        default:
            return 0;

    }
}

- (BOOL)shouldAutoEnterWithEvent:(NSEvent *)event {
    if (self.enabled) {
        return NO;
    }
    if (![iTermPreferences boolForKey:kPreferenceKeyEnterCopyModeAutomatically]) {
        return NO;
    }
    return [self shouldAutoEnterWithEventIgnoringPrefs:event];
}

- (BOOL)shouldAutoEnterWithEventIgnoringPrefs:(NSEvent *)event {
    if (event.type != NSEventTypeKeyDown) {
        return NO;
    }
    if ([self autoEnterEventDirection:event] == 0) {
        return NO;
    }
    const NSEventModifierFlags masks[] = {
        NSEventModifierFlagShift,
        NSEventModifierFlagShift | NSEventModifierFlagOption,
        NSEventModifierFlagShift | NSEventModifierFlagControl,  // in xcode this moves by CamelCaseWord
        NSEventModifierFlagShift | NSEventModifierFlagCommand
    };
    const NSEventModifierFlags mask = (NSEventModifierFlagCommand |
                                       NSEventModifierFlagShift |
                                       NSEventModifierFlagControl |
                                       NSEventModifierFlagOption);
    for (size_t i = 0; i < sizeof(masks) / sizeof(*masks); i++) {
        if ((event.modifierFlags & mask) == masks[i]) {
            return YES;
        }
    }
    return NO;
}

- (void)handleAutoEnteringEvent:(NSEvent *)event {
    const NSInteger direction = [self autoEnterEventDirection:event];
    assert(direction != 0);
    [self setEnabledWithoutCleverness:YES];
    if (direction < 0) {
        [_state swap];
    }
    [self handleEvent:event];
}

- (BOOL)handleEvent:(NSEvent *)event {
    [self.delegate copyModeHandler:self redrawLine:_state.coord.y];
    BOOL wasSelecting = _state.selecting;

    const iTermCopyModeAction action = [self actionForEvent:event];
    if (![self wouldHandleEvent:event]) {
        _count = 0;
        return NO;
    }

    const int countAccrued = [self countAccruedByAction:action event:event];
    if (countAccrued >= 0) {
        _count *= 10;
        _count += countAccrued;
        return YES;
    }

    const NSInteger count = MAX(1, _count);
    _count = 0;
    for (int i = 0; i < count; i++) {
        const BOOL moved = [self performAction:action event:event];

        if (moved || (_state.selecting != wasSelecting)) {
            if (self.enabled) {
                [self.delegate copyModeHandler:self revealLine:_state.coord.y];
            }
            [self.delegate copyModeHandler:self redrawLine:_state.coord.y];
        }
    }
    return YES;
}

// Returns -1 to indicate none
- (int)countAccruedByAction:(iTermCopyModeAction)action event:(NSEvent *)event {
    switch (action) {
        case iTermCopyModeActionAccrueCount:
            return [event.characters characterAtIndex:0] - '0';
        case iTermCopyModeActionMoveToStartOfLineOrAccrue0:
            if (_count == 0) {
                return -1;
            }
            return 0;
        default:
            return -1;
    }
}

- (BOOL)performAction:(iTermCopyModeAction)action event:(NSEvent *)event {
    switch (action) {
        case iTermCopyModeActionAccrueCount:
            assert(NO);
            break;
        case iTermCopyModeActionPageDownHalfScreen:
            return [_state pageDownHalfScreen];
        case iTermCopyModeActionPageUpHalfScreen:
            return [_state pageUpHalfScreen];
        case iTermCopyModeActionScrollUp:
            return [_state scrollUp];
        case iTermCopyModeActionScrollDown:
            return [_state scrollDown];
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
        case iTermCopyModeActionMoveBackwardBigWord:
            return [_state moveBackwardBigWord];
        case iTermCopyModeActionMoveForwardWord:
            return [_state moveForwardWord];
        case iTermCopyModeActionMoveForwardBigWord:
            return [_state moveForwardBigWord];
        case iTermCopyModeActionMoveToStartOfIndentation:
            return [_state moveToStartOfIndentation];
        case iTermCopyModeActionMoveToStartOfNextLine:
            return [_state moveToStartOfNextLine];
        case iTermCopyModeActionQuit:
            self.enabled = NO;
            _state.selecting = NO;
            return YES;
        case iTermCopyModeActionMoveToStartOfLine:
        case iTermCopyModeActionMoveToStartOfLineOrAccrue0:
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
        case iTermCopyModeAction_Count:
            return NO;
    }
}

- (iTermCopyModeAction)actionForEvent:(NSEvent *)event {
    BOOL pointless = NO;
    NSMutableArray<NSEvent *> *extraEvents = [NSMutableArray array];
    NSString *name = nil;
    if (![_keyBindingEmulator handlesEvent:event pointlessly:&pointless extraEvents:extraEvents action:&name]) {
        return iTermCopyModeActionNone;
    }
    BOOL ok = NO;
    const iTermCopyModeAction action = iTermCopyModeActionFromName(name, &ok);
    if (!ok) {
        return iTermCopyModeActionNone;
    }
    return action;
}

- (void)educateAboutCopyMode {
    [[iTermNotificationController sharedInstance] postNotificationWithTitle:@"Copy Mode"
                                                                     detail:@"Copy Mode lets you make a selection with the keyboard. Click to view the manual."
                                                                        URL:[NSURL URLWithString:@"https://iterm2.com/documentation-copymode.html"]];
}


@end

@implementation iTermShortcutNavigationModeHandler
- (BOOL)wouldHandleEvent:(NSEvent *)event {
    const NSEventModifierFlags mask = (NSEventModifierFlagCommand |
                                       NSEventModifierFlagControl);
    if ((event.modifierFlags & mask) != 0) {
        return NO;
    }
    if (event.characters.length == 0) {
        return NO;
    }
    if ([event.characters characterAtIndex:0] == 27) {
        return  YES;
    }
    return [self.delegate shortcutNavigationActionForKeyEquivalent:event.charactersIgnoringModifiers] != nil;
}

- (BOOL)handleEvent:(NSEvent *)event {
    if (![self wouldHandleEvent:event]) {
        return NO;
    }
    if ([event.characters characterAtIndex:0] == 27) {
        return YES;
    }
    void (^block)(NSEvent *) = [self.delegate shortcutNavigationActionForKeyEquivalent:event.charactersIgnoringModifiers];
    if (!block) {
        return NO;
    }
    block(event);
    return YES;
}

@end

@implementation iTermSessionModeHandler {
    iTermCopyModeHandler *_copyModeHandler;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _copyModeHandler = [[iTermCopyModeHandler alloc] init];
        _shortcutNavigationModeHandler = [[iTermShortcutNavigationModeHandler alloc] init];
    }
    return self;
}

- (iTermCopyModeHandler *)copyModeHandler {
    return _copyModeHandler;
}

- (void)setDelegate:(id<iTermCopyModeHandlerDelegate,iTermShortcutNavigationModeHandlerDelegate>)delegate {
    _delegate = delegate;
    _copyModeHandler.delegate = delegate;
    _shortcutNavigationModeHandler.delegate = delegate;
}

- (void)setMode:(iTermSessionMode)mode {
    if (mode == _mode) {
        return;
    }
    const iTermSessionMode original = _mode;
    _mode = mode;
    if (mode == iTermSessionModeCopy) {
        _copyModeHandler.enabled = YES;
    } else if (original == iTermSessionModeCopy) {
        _copyModeHandler.enabled = NO;
    }
    if (mode == iTermSessionModeShortcutNavigation) {
        [self.delegate shortcutNavigationDidBegin];
    } else if (original == iTermSessionModeShortcutNavigation) {
        [self.delegate shortcutNavigationDidComplete];
    }
}

- (BOOL)wouldHandleEvent:(NSEvent *)event {
    switch (_mode) {
        case iTermSessionModeDefault:
            return NO;
        case iTermSessionModeShortcutNavigation:
            return [self.shortcutNavigationModeHandler wouldHandleEvent:event];
        case iTermSessionModeCopy:
            return [self.copyModeHandler wouldHandleEvent:event];
    }
    assert(NO);
    return NO;
}

- (void)enterCopyModeWithoutCleverness {
    _mode = iTermSessionModeCopy;
    [_copyModeHandler setEnabledWithoutCleverness:YES];
}

- (BOOL)handleEvent:(NSEvent *)event {
    switch (_mode) {
        case iTermSessionModeDefault:
            return NO;
        case iTermSessionModeShortcutNavigation: {
            const BOOL handled = [_shortcutNavigationModeHandler handleEvent:event];
            if (handled) {
                self.mode = iTermSessionModeDefault;
            }
            return handled;
        }
        case iTermSessionModeCopy: {
            const BOOL handled = [self.copyModeHandler handleEvent:event];
            if (!self.copyModeHandler.enabled) {
                // Disabled itself
                self.mode = iTermSessionModeDefault;
            }
            return handled;
        }
    }
    assert(NO);
    return NO;
}

- (BOOL)shouldAutoEnterWithEvent:(NSEvent *)event {
    switch (_mode) {
        case iTermSessionModeDefault:
            return [self.copyModeHandler shouldAutoEnterWithEvent:event];
        case iTermSessionModeShortcutNavigation:
            return NO;
        case iTermSessionModeCopy:
            return NO;
    }
    assert(NO);
    return NO;
}

- (BOOL)previousMark {
    switch (_mode) {
        case iTermSessionModeDefault:
        case iTermSessionModeShortcutNavigation:
            return NO;
        case iTermSessionModeCopy:
            return [_copyModeHandler.state previousMark];
    }
}

- (BOOL)nextMark {
    switch (_mode) {
        case iTermSessionModeDefault:
        case iTermSessionModeShortcutNavigation:
            return NO;
        case iTermSessionModeCopy:
            return [_copyModeHandler.state nextMark];
    }
}


@end
