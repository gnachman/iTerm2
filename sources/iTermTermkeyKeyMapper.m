//
//  iTermTermkeyKeyMapper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/30/18.
//

#import "iTermTermkeyKeyMapper.h"

#import "DebugLogging.h"
#import "iTermKeyboardHandler.h"
#import "NSEvent+iTerm.h"
#import "VT100Output.h"

@implementation iTermTermkeyKeyMapper {
    NSEvent *_event;
}

#pragma mark - Pre-Cocoa

- (NSString *)preCocoaString {
    const unsigned int modifiers = [_event it_modifierFlags];

    NSString *charactersIgnoringModifiers = _event.charactersIgnoringModifiers;
    const unichar characterIgnoringModifiers = [charactersIgnoringModifiers length] > 0 ? [charactersIgnoringModifiers characterAtIndex:0] : 0;
    const BOOL shiftPressed = (modifiers & (NSEventModifierFlagShift | NSEventModifierFlagControl)) == NSEventModifierFlagShift;
    if (shiftPressed && characterIgnoringModifiers == 25) {
        // Shift-tab sends CSI Z, aka "backtab"
        NSString *string = [NSString stringWithFormat:@"%c[Z", 27];
        DLog(@"Backtab");
        return string;
    }

    const NSEventModifierFlags allEventModifierFlags = (NSEventModifierFlagControl |
                                                        NSEventModifierFlagOption |
                                                        NSEventModifierFlagShift |
                                                        NSEventModifierFlagCommand);
    if (_event.keyCode == kVK_Space &&
        (_event.modifierFlags & allEventModifierFlags) == NSEventModifierFlagShift) {
        // Shift+Space is special. No other unicode character + shift reports a CSI u.
        return [self termkeySequenceForEvent];
    }

    const BOOL onlyControlPressed = (modifiers & (NSEventModifierFlagControl | NSEventModifierFlagCommand | NSEventModifierFlagOption)) == NSEventModifierFlagControl;
    if (!onlyControlPressed) {
        DLog(@"Not only-control-pressed");
        return nil;
    }

    return [self termkeySequenceForEvent];
}

#pragma mark - Post-Cocoa

- (NSData *)postCocoaData {
    return [[self termkeySequenceForEvent] dataUsingEncoding:_configuration.encoding];
}

- (void)updateConfigurationWithEvent:(NSEvent *)event {
    _event = event;
    [self.delegate termkeyKeyMapperWillMapKey:self];
}

- (NSData *)keyMapperDataForKeyUp:(NSEvent *)event {
    return nil;
}

#pragma mark - Termkey

- (NSString *)stringWithCharacter:(unichar)character {
    return [NSString stringWithCharacters:&character length:1];
}

// CSI code
// CSI 1 ; modifiers code
- (NSString *)reallySpecialSequenceWithCode:(NSString *)code
                             eventModifiers:(NSEventModifierFlags)eventModifiers {
    const int csiModifiers = [self csiModifiersForEventModifiers:eventModifiers];
    if (csiModifiers == 1) {
        return [NSString stringWithFormat:@"%c[%@", 27, code];
    } else {
        return [NSString stringWithFormat:@"%c[1;%d%@", 27, csiModifiers, code];
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

- (NSString *)csiUForCode:(NSString *)code eventModifiers:(NSEventModifierFlags)eventModifiers {
    const int csiModifiers = [self csiModifiersForEventModifiers:eventModifiers];
    if (csiModifiers == 1) {
        return [NSString stringWithFormat:@"%c[%@u", 27, code];
    } else {
        return [NSString stringWithFormat:@"%c[%@;%du", 27, code, csiModifiers];
    }
}

- (NSString *)csiZWithEventModifiers:(NSEventModifierFlags)eventModifiers {
    const int csiModifiers = [self csiModifiersForEventModifiers:eventModifiers];
    if (csiModifiers == 2) {
        // Just shift gives CSI Z
        return [NSString stringWithFormat:@"%c[Z", 27];
    } else {
        // Anything else gets both parts.
        return [NSString stringWithFormat:@"%c[1;%dZ", 27, csiModifiers];
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

// SS3
// esc O code
// esc [ 1 ; modifiers code
- (NSString *)cursorModeStringWithCode:(NSString *)code eventModifiers:(NSEventModifierFlags)eventModifiers {
    const int flags = [self csiModifiersForEventModifiers:eventModifiers];
    if (flags == 1) {
        return [NSString stringWithFormat:@"%cO%@", 27, code];
    } else {
        return [NSString stringWithFormat:@"%c[1;%d%@", 27, flags, code];
    }
}

- (NSString *)sequenceForApplicationCursorCodePoint:(int)unicode
                                            keyCode:(int)keyCode
                                     eventModifiers:(NSEventModifierFlags)eventModifiers {
    // DECCKM selects behavior for arrows, home, and end. This is what xterm does.
    switch (unicode) {
        case NSUpArrowFunctionKey:
            return [self cursorModeStringWithCode:@"A" eventModifiers:eventModifiers];
        case NSDownArrowFunctionKey:
            return [self cursorModeStringWithCode:@"B" eventModifiers:eventModifiers];
        case NSRightArrowFunctionKey:
            return [self cursorModeStringWithCode:@"C" eventModifiers:eventModifiers];
        case NSLeftArrowFunctionKey:
            return [self cursorModeStringWithCode:@"D" eventModifiers:eventModifiers];
        case NSHomeFunctionKey:
            return [self cursorModeStringWithCode:@"H" eventModifiers:eventModifiers];
        case NSEndFunctionKey:
            return [self cursorModeStringWithCode:@"F" eventModifiers:eventModifiers];
    }
    return nil;
}

- (NSString *)sequenceForApplicationKeypadCodePoint:(int)unicode
                                            keyCode:(int)keyCode
                                     eventModifiers:(NSEventModifierFlags)eventModifiers {
    switch (keyCode) {
        case kVK_ANSI_KeypadEnter:
            return [self cursorModeStringWithCode:@"M" eventModifiers:eventModifiers];
        case kVK_ANSI_KeypadMultiply:
            return [self cursorModeStringWithCode:@"j" eventModifiers:eventModifiers];
        case kVK_ANSI_KeypadPlus:
            return [self cursorModeStringWithCode:@"k" eventModifiers:eventModifiers];
        case kVK_ANSI_KeypadMinus:
            return [self cursorModeStringWithCode:@"m" eventModifiers:eventModifiers];
        case kVK_ANSI_KeypadDecimal:
            return [self cursorModeStringWithCode:@"n" eventModifiers:eventModifiers];
        case kVK_ANSI_KeypadDivide:
            return [self cursorModeStringWithCode:@"o" eventModifiers:eventModifiers];
        case kVK_ANSI_Keypad0:
            return [self cursorModeStringWithCode:@"p" eventModifiers:eventModifiers];
        case kVK_ANSI_Keypad1:
            return [self cursorModeStringWithCode:@"q" eventModifiers:eventModifiers];
        case kVK_ANSI_Keypad2:
            return [self cursorModeStringWithCode:@"r" eventModifiers:eventModifiers];
        case kVK_ANSI_Keypad3:
            return [self cursorModeStringWithCode:@"s" eventModifiers:eventModifiers];
        case kVK_ANSI_Keypad4:
            return [self cursorModeStringWithCode:@"t" eventModifiers:eventModifiers];
        case kVK_ANSI_Keypad5:
            return [self cursorModeStringWithCode:@"u" eventModifiers:eventModifiers];
        case kVK_ANSI_Keypad6:
            return [self cursorModeStringWithCode:@"v" eventModifiers:eventModifiers];
        case kVK_ANSI_Keypad7:
            return [self cursorModeStringWithCode:@"w" eventModifiers:eventModifiers];
        case kVK_ANSI_Keypad8:
            return [self cursorModeStringWithCode:@"x" eventModifiers:eventModifiers];
        case kVK_ANSI_Keypad9:
            return [self cursorModeStringWithCode:@"y" eventModifiers:eventModifiers];
        case kVK_ANSI_KeypadEquals:
            return [self cursorModeStringWithCode:@"X" eventModifiers:eventModifiers];
    }

    return nil;
}

- (NSString *)sequenceForApplicationModeCodePoint:(int)unicode
                                          keyCode:(int)keyCode
                                   eventModifiers:(NSEventModifierFlags)eventModifiers {
    if (_configuration.applicationCursorMode) {
        NSString *result = [self sequenceForApplicationCursorCodePoint:unicode
                                                               keyCode:keyCode
                                                        eventModifiers:eventModifiers];
        if (result) {
            return result;
        }
    }
    if (_configuration.applicationKeypadMode) {
        NSString *result = [self sequenceForApplicationKeypadCodePoint:unicode
                                                               keyCode:keyCode
                                                        eventModifiers:eventModifiers];
        if (result) {
            return result;
        }
    }

    return nil;
}

// Function keys, arrows, and keypad.
- (NSString *)termkeySequenceForSpecialKey:(int)unicode
                                   keyCode:(int)keyCode
                            eventModifiers:(NSEventModifierFlags)eventModifiers {
    NSString *applicationModeResult = [self sequenceForApplicationModeCodePoint:unicode
                                                                        keyCode:keyCode
                                                                 eventModifiers:eventModifiers];
    if (applicationModeResult) {
        return applicationModeResult;
    }

    if (!(_event.it_modifierFlags & NSEventModifierFlagFunction)) {
        return nil;
    }

    switch (unicode) {
        // Special keys
        case NSInsertFunctionKey:
        case NSHelpFunctionKey:  // On Apple keyboards help is where insert belongs.
            return [self sequenceForNonUnicodeKeypress:@"2" eventModifiers:eventModifiers];
        case NSDeleteFunctionKey:
            return [self sequenceForNonUnicodeKeypress:@"3" eventModifiers:eventModifiers];
        case NSPageUpFunctionKey:
            return [self sequenceForNonUnicodeKeypress:@"5" eventModifiers:eventModifiers];
        case NSPageDownFunctionKey:
            return [self sequenceForNonUnicodeKeypress:@"6" eventModifiers:eventModifiers];
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

        // Really special keys
        case NSUpArrowFunctionKey:
            return [self reallySpecialSequenceWithCode:@"A" eventModifiers:eventModifiers];
        case NSDownArrowFunctionKey:
            return [self reallySpecialSequenceWithCode:@"B" eventModifiers:eventModifiers];
        case NSRightArrowFunctionKey:
            return [self reallySpecialSequenceWithCode:@"C" eventModifiers:eventModifiers];
        case NSLeftArrowFunctionKey:
            return [self reallySpecialSequenceWithCode:@"D" eventModifiers:eventModifiers];
        case NSHomeFunctionKey:
            return [self reallySpecialSequenceWithCode:@"H" eventModifiers:eventModifiers];
        case NSEndFunctionKey:
            return [self reallySpecialSequenceWithCode:@"F" eventModifiers:eventModifiers];
        case NSF1FunctionKey:
            return [self reallySpecialSequenceWithCode:@"P" eventModifiers:eventModifiers];
        case NSF2FunctionKey:
            return [self reallySpecialSequenceWithCode:@"Q" eventModifiers:eventModifiers];
        case NSF3FunctionKey:
            return [self reallySpecialSequenceWithCode:@"R" eventModifiers:eventModifiers];
        case NSF4FunctionKey:
            return [self reallySpecialSequenceWithCode:@"S" eventModifiers:eventModifiers];
    }

    return nil;
}

- (NSString *)termkeySequenceForModifiedC0Control:(int)keyCode
                                   eventModifiers:(NSEventModifierFlags)eventModifiers {
    const NSEventModifierFlags allEventModifierFlags = (NSEventModifierFlagControl |
                                                        NSEventModifierFlagOption |
                                                        NSEventModifierFlagShift);
    if ((eventModifiers & allEventModifierFlags) == NSEventModifierFlagOption) {
        // Prefer to use esc+ for these, per LeoNerd in email.
        return nil;
    }
    if (keyCode == kVK_Space && (eventModifiers & allEventModifierFlags) == NSEventModifierFlagControl) {
        // Control-space -> '\0'
        const unichar c = 0;
        return [NSString stringWithCharacters:&c length:1];
    }

    // Modified C0 controls. These keys encode shift.
    const BOOL anyModifierPressed = !!(eventModifiers & allEventModifierFlags);
    if (!anyModifierPressed) {
        switch (keyCode) {
            case kVK_Return:
            case kVK_ANSI_KeypadEnter:  // Keypad enter appears to be unspecified.
                return [self stringWithCharacter:0x0d];
            case kVK_Escape:
                return [self stringWithCharacter:0x1b];
            case kVK_Delete: // Backspace
                return [self stringWithCharacter:0x7f];
            case kVK_Space:
                return [self stringWithCharacter:0x20];
            case kVK_Tab:
                return [self stringWithCharacter:0x09];
        }
        return nil;
    }

    // Some modifier pressed. These support reporting the shift key.
    switch (keyCode) {
        case kVK_Return:
        case kVK_ANSI_KeypadEnter:  // Keypad enter appears to be unspecified.
            return [self csiUForCode:@"13" eventModifiers:eventModifiers];
        case kVK_Escape:
            return [self csiUForCode:@"27" eventModifiers:eventModifiers];
        case kVK_Delete: // Backspace
            return [self csiUForCode:@"127" eventModifiers:eventModifiers];
        case kVK_Space:
            return [self csiUForCode:@"32" eventModifiers:eventModifiers];
        case kVK_Tab:
            if (eventModifiers & NSEventModifierFlagShift) {
                // A really careful reading of the spec shows you ignore the shift modifier here.
                // The shiftness is communicated by being CSI code 'Z' rather than 'u'.
                return [self csiZWithEventModifiers:(eventModifiers & ~NSEventModifierFlagShift)];
            } else {
                return [self csiUForCode:@"9" eventModifiers:eventModifiers];
            }
    }

    return nil;
}

- (NSData *)dataWhenOptionPressed {
    return [_event.charactersIgnoringModifiers dataUsingEncoding:_configuration.encoding];
}

- (iTermOptionKeyBehavior)optionKeyBehavior {
    const NSEventModifierFlags modflag = _event.it_modifierFlags;
    const BOOL rightAltPressed = (modflag & NSRightAlternateKeyMask) == NSRightAlternateKeyMask;
    const BOOL leftAltPressed = (modflag & NSEventModifierFlagOption) == NSEventModifierFlagOption && !rightAltPressed;
    assert(leftAltPressed || rightAltPressed);

    if (leftAltPressed) {
        return _configuration.leftOptionKey;
    } else {
        return _configuration.rightOptionKey;
    }
}

- (NSData *)dataForOptionModifiedKeypress {
    NSData *data = [self dataWhenOptionPressed];
    if (data.length == 0) {
        return nil;
    }
    switch ([self optionKeyBehavior]) {
        case OPT_ESC:
            return [self dataByPrependingEsc:data];

        case OPT_META:
            if (data.length > 0) {
                return [self dataBySettingMetaFlagOnFirstByte:data];
            }
            return data;

        case OPT_NORMAL:
            return data;
    }
}

- (NSData *)dataByPrependingEsc:(NSData *)data {
    NSMutableData *temp = [data mutableCopy];
    [temp replaceBytesInRange:NSMakeRange(0, 0) withBytes:"\e" length:1];
    return temp;
}

- (NSData *)dataBySettingMetaFlagOnFirstByte:(NSData *)data {
    // I'm pretty sure this is a no-win situation when it comes to any encoding other
    // than ASCII, but see here for some ideas about this mess:
    // http://www.chiark.greenend.org.uk/~sgtatham/putty/wishlist/meta-bit.html
    const char replacement = ((char *)data.bytes)[0] | 0x80;
    NSMutableData *temp = [data mutableCopy];
    [temp replaceBytesInRange:NSMakeRange(0, 1) withBytes:&replacement length:1];
    return temp;
}

// Only control pressed
- (NSString *)modifiedUnicodeStringForControlCharacter:(unichar)codePoint
                                          shiftPressed:(BOOL)shiftPressed {
    switch (codePoint) {
        case 'i':
        case 'm':
            return nil;

        case '[':
            // Intentional deviation from the CSI u spec because of the stupid touch bar.
            if (shiftPressed) {
                return nil;
            }
            return [self stringWithCharacter:27];

        case ' ':
            if (shiftPressed) {
                return nil;
            }
            return [self stringWithCharacter:0];

        case '2':
        case '@':  // Intentional deviation from the CSI u spec because control+number changes desktops.
            return [self stringWithCharacter:0];

        case '\\':
            if (shiftPressed) {
                return nil;
            }
            return [self stringWithCharacter:28];

        case ']':
            if (shiftPressed) {
                return nil;
            }
            return [self stringWithCharacter:29];

        case '^':  // Intentional deviation from the CSI u spec because control+number changes desktops.
        case '6':
            return [self stringWithCharacter:30];

        case '-':
        case '_':  // Intentional deviation from the CSI u spec for emacs users.
            return [self stringWithCharacter:31];

        case '/':  // Intentional deviation from the CSI u spec for the sake of tradition.
            if (shiftPressed) {
                return nil;
            }
            return [self stringWithCharacter:0x7f];
    }

    if (codePoint < 'a') {
        return nil;
    }
    if (codePoint > 'z') {
        return nil;
    }
    // Legacy code path: control-letter, only control pressed.
    unichar controlCode = codePoint - 'a' + 1;
    return [NSString stringWithCharacters:&controlCode length:1];
}

static BOOL CodePointInPrivateUseArea(unichar c) {
    return c >= 0xE000 && c <= 0xF8FF;
}

- (NSString *)termkeySequenceForCodePoint:(unichar)codePoint
                                modifiers:(NSEventModifierFlags)eventModifiers
                                  keyCode:(int)keyCode {
    // Modified C0
    // Enter, delete, space, tab.
    NSString *sequence = [self termkeySequenceForModifiedC0Control:keyCode eventModifiers:eventModifiers];
    if (sequence) {
        return sequence;
    }

    const NSEventModifierFlags maybeFunction = CodePointInPrivateUseArea(codePoint) ? NSEventModifierFlagFunction : 0;
    const NSEventModifierFlags allEventModifierFlags = (NSEventModifierFlagControl |
                                                        NSEventModifierFlagOption |
                                                        NSEventModifierFlagShift |
                                                        maybeFunction);

    // Special and very special keys
    // Function keys, arrows, and keypad in application keypad mode.
    NSString *possibleResult = [self termkeySequenceForSpecialKey:codePoint keyCode:keyCode eventModifiers:eventModifiers];
    if (possibleResult) {
        return possibleResult;
    }

    // Unmodified unicode
    if ((eventModifiers & allEventModifierFlags) == 0) {
        return _event.characters;
    }
    if ((eventModifiers & allEventModifierFlags) == NSEventModifierFlagShift) {
        return _event.characters;
    }

    // Modified unicode - control
    const NSEventModifierFlags allEventModifierFlagsExShift = (NSEventModifierFlagControl |
                                                               NSEventModifierFlagOption |
                                                               maybeFunction);
    if ((eventModifiers & allEventModifierFlagsExShift) == NSEventModifierFlagControl) {
        NSString *string = [self modifiedUnicodeStringForControlCharacter:codePoint shiftPressed:!!(eventModifiers & NSEventModifierFlagShift)];
        if (string) {
            return string;
        }
    }

    // Modified Unicode - option
    if ((eventModifiers & allEventModifierFlags) == NSEventModifierFlagOption) {
        // Legacy code path: option-letter, for the "simplest form of these keys." Not sure what
        // he meant exactly, but anything that's not a function key seems simple to me. ¯\_(ツ)_/¯
        NSData *data = [self dataForOptionModifiedKeypress];
        if (data) {
            return [[NSString alloc] initWithData:data encoding:_configuration.encoding];
        }
    }

    if (![self codePointIsCharacter:codePoint]) {
        return nil;
    }

    // The new thing
    NSEventModifierFlags modifiers = [self shiftAllowedForKeycode:keyCode] ? eventModifiers : (eventModifiers & ~NSEventModifierFlagShift);
    const int csiModifiers = [self csiModifiersForEventModifiers:modifiers];
    return [NSString stringWithFormat:@"%c[%d;%du", 27, (int)codePoint, csiModifiers];
}

static NSRange iTermMakeRange(NSInteger smallestValueInRange,
                              NSInteger largestValueInRange) {
    return NSMakeRange(smallestValueInRange, largestValueInRange - smallestValueInRange + 1);
}

- (BOOL)codePointIsCharacter:(unichar)codePoint {
    static dispatch_once_t onceToken;
    static NSCharacterSet *characters;
    dispatch_once(&onceToken, ^{
        NSMutableCharacterSet *mutableSet = [[NSMutableCharacterSet alloc] init];
        [mutableSet addCharactersInRange:iTermMakeRange(0xe000, 0xf8ff)];
        [mutableSet addCharactersInRange:iTermMakeRange(0xfdd0, 0xfdd0)];
        [mutableSet addCharactersInRange:iTermMakeRange(0xfdef, 0xfdef)];
        [mutableSet addCharactersInRange:iTermMakeRange(0xfff0, 0xffff)];
        [mutableSet invert];
        characters = mutableSet;
    });
    return [characters characterIsMember:codePoint];
}

- (BOOL)shiftAllowedForKeycode:(int)code {
    switch (code) {
        case kVK_Return:
        case kVK_ANSI_KeypadEnter:  // Keypad enter appears to be unspecified.
        case kVK_Escape:
        case kVK_Delete:  // backspace
        case kVK_Space:
        case kVK_Tab:
            return YES;
    }
    return NO;
}

- (NSString *)termkeySequenceForEvent {
    if (_event.charactersIgnoringModifiers.length == 0) {
        return nil;
    }
    const unichar codePoint = [_event.charactersIgnoringModifiers characterAtIndex:0];
    return [self termkeySequenceForCodePoint:codePoint
                                   modifiers:_event.it_modifierFlags
                                     keyCode:_event.keyCode];
}

#pragma mark - iTerm

- (NSString *)keyMapperStringForPreCocoaEvent:(NSEvent *)event {
    if (event.type != NSEventTypeKeyDown) {
        return nil;
    }
    [self updateConfigurationWithEvent:event];
    return [self preCocoaString];
}

- (NSData *)keyMapperDataForPostCocoaEvent:(NSEvent *)event {
    if (event.type != NSEventTypeKeyDown) {
        return nil;
    }
    [self updateConfigurationWithEvent:event];
    return [self postCocoaData];
}

- (BOOL)keyMapperShouldBypassPreCocoaForEvent:(NSEvent *)event {
    const NSEventModifierFlags modifiers = event.it_modifierFlags;
    const BOOL isSpecialKey = !!(modifiers & (NSEventModifierFlagNumericPad | NSEventModifierFlagFunction));
    if (isSpecialKey) {
        // Arrow key, function key, etc.
        return YES;
    }

    const BOOL isNonEmpty = [[event charactersIgnoringModifiers] length] > 0;  // Dead keys have length 0
    const BOOL rightAltPressed = (modifiers & NSRightAlternateKeyMask) == NSRightAlternateKeyMask;
    const BOOL leftAltPressed = (modifiers & NSEventModifierFlagOption) == NSEventModifierFlagOption && !rightAltPressed;
    const BOOL leftOptionModifiesKey = (leftAltPressed && _configuration.leftOptionKey != OPT_NORMAL);
    const BOOL rightOptionModifiesKey = (rightAltPressed && _configuration.rightOptionKey != OPT_NORMAL);
    const BOOL optionModifiesKey = (leftOptionModifiesKey || rightOptionModifiesKey);
    const BOOL willSendOptionModifiedKey = (isNonEmpty && optionModifiesKey);
    if (willSendOptionModifiedKey) {
        // Meta+key or Esc+ key
        return YES;
    }

    if (event.charactersIgnoringModifiers.length > 0) {
        const unichar codePoint = [event.charactersIgnoringModifiers characterAtIndex:0];
        if ([self sequenceForApplicationModeCodePoint:codePoint
                                              keyCode:event.keyCode
                                       eventModifiers:event.it_modifierFlags]) {
            // Application cursor keys in effect. Don't let cocoa call insertText:.
            return YES;
        }
    }

    return NO;
}

@end
