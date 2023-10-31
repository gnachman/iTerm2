//
//  iTermModifyOtherKeysMapper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/12/20.
//

#import "iTermModifyOtherKeysMapper.h"

#import "DebugLogging.h"
#import "iTermKeyboardHandler.h"
#import "NSEvent+iTerm.h"
#import "NSStringITerm.h"
#import "VT100Output.h"

static BOOL CodePointInPrivateUseArea(unichar c) {
    return c >= 0xE000 && c <= 0xF8FF;
}

@implementation iTermModifyOtherKeysMapper

- (BOOL)eventIsControlCodeWithOption:(NSEvent *)event {
    if (event.keyCode == kVK_Escape) {
        // esc doesn't get treated like other control characters.
        return NO;
    }
    const NSEventModifierFlags allEventModifierFlags = (NSEventModifierFlagControl |
                                                        NSEventModifierFlagOption |
                                                        NSEventModifierFlagShift |
                                                        NSEventModifierFlagCommand);
    const NSEventModifierFlags controlOption = (NSEventModifierFlagControl | NSEventModifierFlagOption);
    if ((event.it_modifierFlags & allEventModifierFlags) != controlOption) {
        return NO;
    }
    if (event.characters.length != 1) {
        return NO;
    }
    if ([event.characters characterAtIndex:0] >= 32) {
        return NO;
    }
    const unichar controlCode = [event.characters characterAtIndex:0] + '@';
    if ([[NSString stringWithCharacters:&controlCode length:1] isEqualTo:event.charactersIgnoringModifiers]) {
        // On US keyboards, when you just press control+opt+<char> you get:
        //  event.characters="<control code>" event.charactersIgnoringModifiers="<char>"
        // On Spanish ISO (and presumably all others like it) when you press control+opt+<char> you can get:
        //  event.characters="<control code>" event.charactersIgnoringModifiers="<some random other thing on the key>"
        // This code path prevents control-opt-char from ignoring the Option modifier on US-style
        // keyboards. Those should not be treated as control keys. The reason I think this is correct
        // is that on a keyboard that *requires* you to press option to get a control, it must be
        // because the default character for the key is not the one that goes with the control. For
        // example, on Spanish ISO the key labeled + becomes ] when you press option. So to send
        // C-] you have to press C-Opt-], and modifyOtherKeys should treat it as C-].
        return NO;
    }
    // This is a control key. We can't just send it in modifyOtherKeys=2 mode. For example,
    // in issue 9279 @elias.baixas notes that on a Spanish ISO keyboard you press control-alt-+
    // to get control-]. characters="<0x1d>".
    return YES;
}

- (UTF32Char)codePointForEvent:(NSEvent *)event {
    NSString *charactersIgnoringModifiers = event.charactersIgnoringModifiers;
    if (event.keyCode == kVK_Tab) {
        // For some reason shift-tab gives 25.
        return 9;
    }
    if ([self eventIsControlCodeWithOption:event]) {
        // Keyboards that require you to press control+option+something to generate a control code
        // take this path.
        const unichar controlCode = [event.characters characterAtIndex:0];
        return controlCode + '@';
    }
    return [charactersIgnoringModifiers firstCharacter];
}

- (NSString *)stringForEvent:(NSEvent *)event {
    const NSEventModifierFlags allEventModifierFlags = (NSEventModifierFlagControl |
                                                        NSEventModifierFlagOption |
                                                        NSEventModifierFlagShift |
                                                        NSEventModifierFlagCommand);
    NSString *charactersIgnoringModifiers = event.charactersIgnoringModifiers;
    if (charactersIgnoringModifiers.length == 0) {
        return nil;
    }
    if (charactersIgnoringModifiers.length > 1) {
        DLog(@"Got multiple characters for keystroke: %@", charactersIgnoringModifiers);
        return charactersIgnoringModifiers;
    }
    const UTF32Char codePoint = [self codePointForEvent:event];
    const NSEventModifierFlags maybeFunction = CodePointInPrivateUseArea(codePoint) ? NSEventModifierFlagFunction : 0;
    const NSEventModifierFlags allEventModifierFlagsExShift = (NSEventModifierFlagControl |
                                                               NSEventModifierFlagOption |
                                                               maybeFunction);
    if ((event.it_modifierFlags & allEventModifierFlagsExShift) == NSEventModifierFlagOption) {
        if ([self optionKeyBehaviorForEvent:event] != OPT_NORMAL) {
            return [self stringWhenOptionPressedForEvent:event];
        }
    }

    NSEventModifierFlags mask = allEventModifierFlags;
    if ([self eventIsControlCodeWithOption:event]) {
        // This is intended for keyboards like Spanish ISO that require you to press option to get
        // certain control codes (like ctrl+opt++ for C-]).
        mask &= (~NSEventModifierFlagOption);
    }
    const NSEventModifierFlags modifiers = [event it_modifierFlags] & mask;
    return [self stringForCodePoint:codePoint modifiers:modifiers];
}

- (NSString *)stringWhenOptionPressedForEvent:(NSEvent *)event {
    switch ([self optionKeyBehaviorForEvent:event]) {
        case OPT_NORMAL:
            return event.charactersIgnoringModifiers;
        case OPT_ESC:
        case OPT_META:
            break;
    }
    const NSEventModifierFlags allEventModifierFlags = (NSEventModifierFlagControl |
                                                        NSEventModifierFlagOption |
                                                        NSEventModifierFlagShift |
                                                        NSEventModifierFlagCommand);
    const NSEventModifierFlags modifiers = [event it_modifierFlags] & allEventModifierFlags;
    return [self stringForCodePoint:event.charactersIgnoringModifiers.firstCharacter modifiers:modifiers];
}

- (iTermOptionKeyBehavior)optionKeyBehaviorForEvent:(NSEvent *)event {
    const NSEventModifierFlags modflag = event.it_modifierFlags;
    const BOOL rightAltPressed = (modflag & NSRightAlternateKeyMask) == NSRightAlternateKeyMask;
    const BOOL leftAltPressed = (modflag & NSEventModifierFlagOption) == NSEventModifierFlagOption && !rightAltPressed;
    assert(leftAltPressed || rightAltPressed);

    iTermOptionKeyBehavior left, right;
    [self.delegate modifyOtherKeys:self getOptionKeyBehaviorLeft:&left right:&right];
    if (leftAltPressed) {
        return left;
    } else {
        return right;
    }
}

- (NSString *)stringForCodePoint:(UTF32Char)codePoint
                       modifiers:(NSEventModifierFlags)eventModifiers {
    switch (codePoint) {
        case NSInsertFunctionKey:
        case NSHelpFunctionKey:  // On Apple keyboards help is where insert belongs.
            return [self sequenceForNonUnicodeKeypress:@"2" eventModifiers:eventModifiers];
        case NSDeleteFunctionKey:
            return [self sequenceForNonUnicodeKeypress:@"3" eventModifiers:eventModifiers];
        case NSPageUpFunctionKey:
            return [self sequenceForNonUnicodeKeypress:@"5" eventModifiers:eventModifiers];
        case NSPageDownFunctionKey:
            return [self sequenceForNonUnicodeKeypress:@"6" eventModifiers:eventModifiers];
        case NSF1FunctionKey:
            return [self sequenceForFunctionKeyWithCode:@"P" eventModifiers:eventModifiers];
        case NSF2FunctionKey:
            return [self sequenceForFunctionKeyWithCode:@"Q" eventModifiers:eventModifiers];
        case NSF3FunctionKey:
            return [self sequenceForFunctionKeyWithCode:@"R" eventModifiers:eventModifiers];
        case NSF4FunctionKey:
            return [self sequenceForFunctionKeyWithCode:@"S" eventModifiers:eventModifiers];
        case NSF5FunctionKey:
            return [self sequenceForNonUnicodeKeypress:@"15" eventModifiers:eventModifiers];
        case NSF6FunctionKey:
            return [self sequenceForNonUnicodeKeypress:@"17" eventModifiers:eventModifiers];
        case NSF7FunctionKey:
            return [self sequenceForNonUnicodeKeypress:@"18" eventModifiers:eventModifiers];
        case NSF8FunctionKey:
            return [self sequenceForNonUnicodeKeypress:@"19" eventModifiers:eventModifiers];
        case NSF9FunctionKey:
            return [self sequenceForNonUnicodeKeypress:@"20" eventModifiers:eventModifiers];
        case NSF10FunctionKey:
            return [self sequenceForNonUnicodeKeypress:@"21" eventModifiers:eventModifiers];
        case NSF11FunctionKey:
            return [self sequenceForNonUnicodeKeypress:@"23" eventModifiers:eventModifiers];
        case NSF12FunctionKey:
            return [self sequenceForNonUnicodeKeypress:@"24" eventModifiers:eventModifiers];
        case NSF13FunctionKey:
            return [self sequenceForNonUnicodeKeypress:@"25" eventModifiers:eventModifiers];
        case NSF14FunctionKey:
            return [self sequenceForNonUnicodeKeypress:@"26" eventModifiers:eventModifiers];
        case NSF15FunctionKey:
            return [self sequenceForNonUnicodeKeypress:@"28" eventModifiers:eventModifiers];
        case NSUpArrowFunctionKey:
        case NSDownArrowFunctionKey:
        case NSRightArrowFunctionKey:
        case NSLeftArrowFunctionKey:
        case NSHomeFunctionKey:
        case NSEndFunctionKey:
            return [self reallySpecialSequenceWithCode:codePoint eventModifiers:eventModifiers];
        case '\t':
            if (eventModifiers == NSEventModifierFlagShift) {
                // Issue 9202 - hack to make vim work. xterm does this on linux but not macos.
                // See also https://github.com/vim/vim/issues/7189
                // Private email thread with Thomas Dickey subject line "Shift-tab and modifyOtherKeys=2"
                return [NSString stringWithFormat:@"\e[Z"];
            }
            // fall through
        default:
            if (eventModifiers == 0) {
                return [NSString stringWithLongCharacter:codePoint];
            }
            return [NSString stringWithFormat:@"\e[27;%d;%d~",
                    [self csiModifiersForEventModifiers:eventModifiers],
                    codePoint];
    }
}

- (NSString *)sequenceForFunctionKeyWithCode:(NSString *)code
                              eventModifiers:(NSEventModifierFlags)eventModifiers {
    const int csiModifiers = [self csiModifiersForEventModifiers:eventModifiers];
    if (csiModifiers == 1) {
        // esc O code
        return [NSString stringWithFormat:@"%cO%@", 27, code];
    } else {
        // CSI 1 ; mods code
        return [NSString stringWithFormat:@"%c[1;%d%@", 27, csiModifiers, code];
    }
}

- (NSString *)reallySpecialSequenceWithCode:(UTF32Char)code
                             eventModifiers:(NSEventModifierFlags)eventModifiers {
    VT100Output *output = [self.delegate modifyOtherKeysOutputFactory:self];
    const BOOL screenlike = [self.delegate modifyOtherKeysTerminalIsScreenlike:self];
    switch (code) {
        case NSUpArrowFunctionKey:
            return [[NSString alloc] initWithData:[output keyArrowUp:eventModifiers]
                                         encoding:NSISOLatin1StringEncoding];
        case NSDownArrowFunctionKey:
            return [[NSString alloc] initWithData:[output keyArrowDown:eventModifiers]
                                         encoding:NSISOLatin1StringEncoding];
        case NSRightArrowFunctionKey:
            return [[NSString alloc] initWithData:[output keyArrowRight:eventModifiers]
                                         encoding:NSISOLatin1StringEncoding];
        case NSLeftArrowFunctionKey:
            return [[NSString alloc] initWithData:[output keyArrowLeft:eventModifiers]
                                         encoding:NSISOLatin1StringEncoding];
        case NSHomeFunctionKey:
            return [[NSString alloc] initWithData:[output keyHome:eventModifiers screenlikeTerminal:screenlike]
                                         encoding:NSISOLatin1StringEncoding];
        case NSEndFunctionKey:
            return [[NSString alloc] initWithData:[output keyEnd:eventModifiers screenlikeTerminal:screenlike]
                                         encoding:NSISOLatin1StringEncoding];
    }

    ITCriticalError(NO, @"Unexpected code %@", [NSString stringWithLongCharacter:code]  );
    const int csiModifiers = [self csiModifiersForEventModifiers:eventModifiers];
    if (csiModifiers == 1) {
        // esc code
        return [NSString stringWithFormat:@"%c[%@", 27, [NSString stringWithLongCharacter:code]];
    } else {
        // CSI 1 ; mods code
        return [NSString stringWithFormat:@"%c[1;%d%@", 27, csiModifiers, [NSString stringWithLongCharacter:code]];
    }
}

// CSI code ~
// CSI code ; modifier ~
- (NSString *)sequenceForNonUnicodeKeypress:(NSString *)code
                             eventModifiers:(NSEventModifierFlags)eventModifiers {
    const int csiModifiers = [self csiModifiersForEventModifiers:eventModifiers];
    if (csiModifiers == 1) {
        return [NSString stringWithFormat:@"%c[%@~", 27, code];
    } else {
        return [NSString stringWithFormat:@"%c[%@;%d~", 27, code, csiModifiers];
    }
}

- (int)csiModifiersForEventModifiers:(NSEventModifierFlags)eventModifiers {
    const int shiftMask = 1;
    const int optionMask = 2;
    const int controlMask = 4;
    int csiModifiers = 0;
    if (eventModifiers & NSEventModifierFlagShift) {
        csiModifiers |= shiftMask;
    }
    if (eventModifiers & NSEventModifierFlagOption) {
        csiModifiers |= optionMask;
    }
    if (eventModifiers & NSEventModifierFlagControl) {
        csiModifiers |= controlMask;
    }
    return csiModifiers + 1;
}

#pragma mark - iTermKeyMapper

// Handle control modifier when it's alone or in concert with option, provided that sends a control.
- (nullable NSString *)keyMapperStringForPreCocoaEvent:(NSEvent *)event {
    if (event.type != NSEventTypeKeyDown) {
        return nil;
    }
    if ([event it_isNumericKeypadKey]) {
        VT100Output *output = [self.delegate modifyOtherKeysOutputFactory:self];
        const NSStringEncoding encoding = [self.delegate modifiyOtherKeysDelegateEncoding:self];
        return [[NSString alloc] initWithData:[output keypadDataForString:event.characters modifiers:event.it_modifierFlags]
                                     encoding:encoding];
    }

    const NSEventModifierFlags allEventModifierFlags = (NSEventModifierFlagControl |
                                                        NSEventModifierFlagOption |
                                                        NSEventModifierFlagShift |
                                                        NSEventModifierFlagCommand);
    if (event.keyCode == kVK_Space &&
        (event.it_modifierFlags & allEventModifierFlags) == NSEventModifierFlagShift) {
        // Shift+Space is special. No other unicode character + shift reports a control sequence.
        return [self stringForEvent:event];
    }
    if ((event.it_modifierFlags & NSEventModifierFlagControl) == 0) {
        return nil;
    }
    // Always send a modifyOtherKeys sequence for control+anything.
    return [self stringForEvent:event];
}

// For events that are not handled by the pre-cocoa code (because it was bypassed, the pre-cocoa
// handler returned nil, or it was a repeating keypress not otherwise handled), they may come here
// as the last resort after the controller has a chance to handle it.
- (nullable NSData *)keyMapperDataForPostCocoaEvent:(NSEvent *)event {
    if (event.type != NSEventTypeKeyDown) {
        return nil;
    }
    const NSStringEncoding encoding = [self.delegate modifiyOtherKeysDelegateEncoding:self];
    return [[self stringForEvent:event] dataUsingEncoding:encoding];
}

- (nullable NSData *)keyMapperDataForKeyUp:(NSEvent *)event {
    return nil;
}

// If this returns YES then the event will be sent to the controller which, if it does not handle
// the event itself, will send the event to the post-cocoa handler here. Don't return YES if the
// event should go through the IME.
- (BOOL)keyMapperShouldBypassPreCocoaForEvent:(NSEvent *)event {
    const NSEventModifierFlags modifiers = event.it_modifierFlags;
    const BOOL isNonEmpty = [[event charactersIgnoringModifiers] length] > 0;  // Dead keys have length 0
    const BOOL rightAltPressed = (modifiers & NSRightAlternateKeyMask) == NSRightAlternateKeyMask;
    const BOOL leftAltPressed = (modifiers & NSEventModifierFlagOption) == NSEventModifierFlagOption && !rightAltPressed;
    iTermOptionKeyBehavior left, right;
    [self.delegate modifyOtherKeys:self getOptionKeyBehaviorLeft:&left right:&right];
    const BOOL leftOptionModifiesKey = (leftAltPressed && left != OPT_NORMAL);
    const BOOL rightOptionModifiesKey = (rightAltPressed && right != OPT_NORMAL);
    const BOOL optionModifiesKey = (leftOptionModifiesKey || rightOptionModifiesKey);

    if ([self eventIsControlCodeWithOption:event]) {
        // Always handle control+anything ourselves. We certainly don't want
        // cocoa to get ahold of it and call insertText: or
        // performKeyEquivalent:, which bypasses all the modifyOtherKeys goodness.
        return NO;
    }

    if ([event it_isNumericKeypadKey] && [[self.delegate modifyOtherKeysOutputFactory:self] keypadMode]) {
        DLog(@"In application keypad mode.");
        return NO;
    }

    const BOOL willSendOptionModifiedKey = (isNonEmpty && optionModifiesKey);
    if (willSendOptionModifiedKey) {
        // Meta+key or Esc+ key
        DLog(@"isNonEmpty=%@ rightAltPressed=%@ leftAltPressed=%@ leftOptionModifiesKey=%@ rightOptionModifiesKey=%@ optionModifiesKey=%@ willSendOptionModifiedKey=%@ -> bypass pre-cocoa",
             @(isNonEmpty), @(rightAltPressed), @(leftAltPressed), @(leftOptionModifiesKey), @(rightOptionModifiesKey), @(optionModifiesKey), @(willSendOptionModifiedKey));
        return YES;
    }

    return NO;
}

// Prepare to handle this event. Update config from delegate.
- (void)keyMapperSetEvent:(NSEvent *)event {
}

// When a keystroke is routed to performKeyEquivalent instead of keyDown, this is called to check
// if the key mapper is interested in it.
- (BOOL)keyMapperWantsKeyEquivalent:(NSEvent *)event {
    const BOOL cmdPressed = !!(event.modifierFlags & NSEventModifierFlagCommand);
    DLog(@"!cmdPressed=%@", @(!cmdPressed));
    return !cmdPressed;
}

- (NSDictionary *)keyMapperDictionaryValue {
    return iTermModifyOtherKeysMapperDictionary(self, self.delegate);
}

@end

@implementation iTermModifyOtherKeysMapper2
@end


NSDictionary *iTermModifyOtherKeysMapperDictionary(iTermModifyOtherKeysMapper *self,
                                                   id<iTermModifyOtherKeysMapperDelegate> delegate) {
    iTermOptionKeyBehavior left, right;
    [delegate modifyOtherKeys:self getOptionKeyBehaviorLeft:&left right:&right];
    VT100Output *output = [delegate modifyOtherKeysOutputFactory:self];
    return @{ @"encoding": @([delegate modifiyOtherKeysDelegateEncoding:self]),
              @"leftOptionKeyBehavior": @(left),
              @"rightOptionKeyBehavior": @(right),
              @"output": [output configDictionary] ?: @{},
              @"screenLike": @([delegate modifyOtherKeysTerminalIsScreenlike:self]) };
}
