//
//  iTermStandardKeyMapper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/29/18.
//

#import "iTermStandardKeyMapper.h"

#import "DebugLogging.h"
#import "iTermKeyboardHandler.h"
#import "NSData+iTerm.h"
#import "VT100Output.h"

@implementation iTermStandardKeyMapper {
    NSEvent *_event;
}

- (void)updateConfigurationWithEvent:(NSEvent *)event {
    _event = event;
    [self.delegate standardKeyMapperWillMapKey:self];
}

- (NSData *)keyMapperDataForKeyUp:(NSEvent *)event {
    return nil;
}

#pragma mark - Pre-Cocoa

- (NSString *)preCocoaString {
    const unsigned int modflag = [_event modifierFlags];
    NSString *charactersIgnoringModifiers = _event.charactersIgnoringModifiers;
    const unichar characterIgnoringModifiers = [charactersIgnoringModifiers length] > 0 ? [charactersIgnoringModifiers characterAtIndex:0] : 0;
    const BOOL shiftPressed = !!(modflag & NSEventModifierFlagShift);
    if (shiftPressed && characterIgnoringModifiers == 25) {
        // Shift-tab sends CSI Z, aka "backtab"
        NSString *string = [NSString stringWithFormat:@"%c[Z", 27];
        DLog(@"Backtab");
        return string;
    }

    const BOOL onlyControlPressed = (modflag & (NSEventModifierFlagControl | NSEventModifierFlagCommand | NSEventModifierFlagOption)) == NSEventModifierFlagControl;
    if (!onlyControlPressed) {
        DLog(@"Not only-control-pressed");
        return nil;
    }

    const unichar controlCode = [self controlCodeForEvent:_event];
    if (controlCode == 0xffff) {
        DLog(@"Not a control code");
        return nil;
    }

    DLog(@"PTYTextView send control code %d", (int)controlCode);
    return [NSString stringWithCharacters:&controlCode length:1];
}

// Called when control is pressed and command and option are not pressed. Shift may or may not be pressed.
- (unichar)controlCodeForEvent:(NSEvent *)event {
    NSString *charactersIgnoringModifiers = [event charactersIgnoringModifiers];
    const unichar characterIgnoringModifiers = [charactersIgnoringModifiers length] > 0 ? [charactersIgnoringModifiers characterAtIndex:0] : 0;

    if (characterIgnoringModifiers >= 'a' && characterIgnoringModifiers <= 'z') {
        return characterIgnoringModifiers - 'a' + 1;
    }

    NSString *const characters = event.characters;
    const unichar character = characters.length > 0 ? [characters characterAtIndex:0] : 0;
    const BOOL shiftPressed = !!(event.modifierFlags & NSEventModifierFlagShift);
    if (character == '/' && shiftPressed) {
        return 127;
    }

    switch (characterIgnoringModifiers) {
        case ' ':
        case '2':
        case '@':
            return 0;

        case '[':
            return 27;

        case '\\':
        case '|':
            return 28;

        case ']':
            return 29;

        case '^':
        case '6':
            return 30;

        case '-':
        case '_':
        case '/':
            return 31;
    }

    return 0xffff;
}

#pragma mark - Post-Cocoa

- (NSData *)postCocoaData {
    if (_event.modifierFlags & NSEventModifierFlagFunction) {
        return [self dataForFunctionKeyPress];
    }

    if ([self shouldSendOptionModifiedKeypress]) {
        return [self dataForOptionModifiedKeypress];
    }

    // Regular path for inserting a character from a keypress.
    return [self dataForRegularKeypress];
}

- (NSData *)dataForRegularKeypress {
    DLog(@"PTYSession keyDown regular path");
    NSString *characters = [_event characters];

    // Enter key is on numeric keypad, but not marked as such
    const unichar character = _event.characters.length > 0 ? [_event.characters characterAtIndex:0] : 0;
    NSString *const charactersIgnoringModifiers = [_event charactersIgnoringModifiers];
    const unichar characterIgnoringModifier = [charactersIgnoringModifiers length] > 0 ? [charactersIgnoringModifiers characterAtIndex:0] : 0;
    NSEventModifierFlags mutableModifiers = _event.modifierFlags;

    if (character == NSEnterCharacter && characterIgnoringModifier == NSEnterCharacter) {
        mutableModifiers |= NSEventModifierFlagNumericPad;
        DLog(@"PTYSession keyDown enter key");
        characters = @"\015";  // Enter key -> 0x0d
    }

    if ([self shouldSquelchKeystrokeWithString:characters modifiers:mutableModifiers]) {
        // Do not send anything for cmd+number because the user probably
        // fat-fingered switching of tabs/windows.
        // Do not send anything for cmd+[shift]+enter if it wasn't
        // caught by the menu.
        DLog(@"PTYSession keyDown cmd+0-9 or cmd+enter");
        return nil;
    }

    const BOOL isNumericKeypadKey = !!(mutableModifiers & NSEventModifierFlagNumericPad);
    if (isNumericKeypadKey || [self keycodeShouldHaveNumericKeypadFlag:_event.keyCode]) {
        DLog(@"PTYSession keyDown numeric keypad");
        return [_configuration.outputFactory keypadData:character keystr:characters];
    }

    if (characters.length != 1 || [characters characterAtIndex:0] > 0x7f) {
        DLog(@"PTYSession keyDown non-ascii");
        return [characters dataUsingEncoding:_configuration.encoding];
    }

    DLog(@"PTYSession keyDown ascii");
    // Commit a00a9385b2ed722315ff4d43e2857180baeac2b4 in old-iterm suggests this is
    // necessary for some Japanese input sources, but is vague.
    return [characters dataUsingEncoding:NSUTF8StringEncoding];
}

- (iTermOptionKeyBehavior)optionKeyBehavior {
    const NSEventModifierFlags modflag = _event.modifierFlags;
    const BOOL rightAltPressed = (modflag & NSRightAlternateKeyMask) == NSRightAlternateKeyMask;
    const BOOL leftAltPressed = (modflag & NSEventModifierFlagOption) == NSEventModifierFlagOption && !rightAltPressed;
    assert(leftAltPressed || rightAltPressed);

    if (leftAltPressed) {
        return _configuration.leftOptionKey;
    } else {
        return _configuration.rightOptionKey;
    }
}

- (NSData *)dataWhenOptionPressed {
    const unichar unicode = _event.characters.length > 0 ? [_event.characters characterAtIndex:0] : 0;
    const BOOL controlPressed = !!(_event.modifierFlags & NSEventModifierFlagControl);
    if (controlPressed && unicode > 0) {
        return [_event.characters dataUsingEncoding:_configuration.encoding];
    } else {
        return [_event.charactersIgnoringModifiers dataUsingEncoding:_configuration.encoding];
    }
}

// A key was pressed while holding down option and the option key
// is not behaving normally. Apply the modified behavior.
- (NSData *)dataForOptionModifiedKeypress {
    DLog(@"PTYSession keyDown opt + key -> modkey");

    NSData *data = [self dataWhenOptionPressed];
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

    assert(NO);
    return data;
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

- (BOOL)shouldSendOptionModifiedKeypress {
    const NSEventModifierFlags modifiers = _event.modifierFlags;
    const BOOL rightAltPressed = (modifiers & NSRightAlternateKeyMask) == NSRightAlternateKeyMask;
    const BOOL leftAltPressed = (modifiers & NSEventModifierFlagOption) == NSEventModifierFlagOption && !rightAltPressed;

    if (leftAltPressed && _configuration.leftOptionKey != OPT_NORMAL) {
        return YES;
    }

    if (rightAltPressed && _configuration.rightOptionKey != OPT_NORMAL) {
        return YES;
    }
    return NO;
}

- (NSData *)dataForFunctionKeyPress {
    NSString *const characters = _event.characters;
    const NSEventModifierFlags modifiers = _event.modifierFlags;
    const unichar unicode = [characters length] > 0 ? [characters characterAtIndex:0] : 0;
    DLog(@"PTYSession keyDown is a function key");

    // Handle all "special" keys (arrows, etc.)
    switch (unicode) {
        case NSUpArrowFunctionKey:
            return [_configuration.outputFactory keyArrowUp:modifiers];
            break;
        case NSDownArrowFunctionKey:
            return [_configuration.outputFactory keyArrowDown:modifiers];
            break;
        case NSLeftArrowFunctionKey:
            return [_configuration.outputFactory keyArrowLeft:modifiers];
            break;
        case NSRightArrowFunctionKey:
            return [_configuration.outputFactory keyArrowRight:modifiers];
            break;
        case NSInsertFunctionKey:
            return [_configuration.outputFactory keyInsert];
            break;
        case NSDeleteFunctionKey:
            // This is forward delete, not backspace.
            return [_configuration.outputFactory keyDelete];
            break;
        case NSHomeFunctionKey:
            return [_configuration.outputFactory keyHome:modifiers screenlikeTerminal:_configuration.screenlike];
            break;
        case NSEndFunctionKey:
            return [_configuration.outputFactory keyEnd:modifiers screenlikeTerminal:_configuration.screenlike];
            break;
        case NSPageUpFunctionKey:
            return [_configuration.outputFactory keyPageUp:modifiers];
            break;
        case NSPageDownFunctionKey:
            return [_configuration.outputFactory keyPageDown:modifiers];
            break;
        case NSClearLineFunctionKey:
            return [@"\e" dataUsingEncoding:NSUTF8StringEncoding];
            break;
        case NSF1FunctionKey:
        case NSF2FunctionKey:
        case NSF3FunctionKey:
        case NSF4FunctionKey:
        case NSF5FunctionKey:
        case NSF6FunctionKey:
        case NSF7FunctionKey:
        case NSF8FunctionKey:
        case NSF9FunctionKey:
        case NSF10FunctionKey:
        case NSF11FunctionKey:
        case NSF12FunctionKey:
        case NSF13FunctionKey:
        case NSF14FunctionKey:
        case NSF15FunctionKey:
        case NSF16FunctionKey:
        case NSF17FunctionKey:
        case NSF18FunctionKey:
        case NSF19FunctionKey:
        case NSF20FunctionKey:
        case NSF21FunctionKey:
        case NSF22FunctionKey:
        case NSF23FunctionKey:
        case NSF24FunctionKey:
        case NSF25FunctionKey:
        case NSF26FunctionKey:
        case NSF27FunctionKey:
        case NSF28FunctionKey:
        case NSF29FunctionKey:
        case NSF30FunctionKey:
        case NSF31FunctionKey:
        case NSF32FunctionKey:
        case NSF33FunctionKey:
        case NSF34FunctionKey:
        case NSF35FunctionKey:
            return [_configuration.outputFactory keyFunction:unicode - NSF1FunctionKey + 1];
    }

    return [characters dataUsingEncoding:_configuration.encoding];
}

// In issue 4039 we see that in some cases the numeric keypad mask isn't set properly.
- (BOOL)keycodeShouldHaveNumericKeypadFlag:(unsigned short)keycode {
    switch (keycode) {
        case kVK_ANSI_KeypadDecimal:
        case kVK_ANSI_KeypadMultiply:
        case kVK_ANSI_KeypadPlus:
        case kVK_ANSI_KeypadClear:
        case kVK_ANSI_KeypadDivide:
        case kVK_ANSI_KeypadEnter:
        case kVK_ANSI_KeypadMinus:
        case kVK_ANSI_KeypadEquals:
        case kVK_ANSI_Keypad0:
        case kVK_ANSI_Keypad1:
        case kVK_ANSI_Keypad2:
        case kVK_ANSI_Keypad3:
        case kVK_ANSI_Keypad4:
        case kVK_ANSI_Keypad5:
        case kVK_ANSI_Keypad6:
        case kVK_ANSI_Keypad7:
        case kVK_ANSI_Keypad8:
        case kVK_ANSI_Keypad9:
            DLog(@"Key code 0x%x forced to have numeric keypad mask set", (int)keycode);
            return YES;

        default:
            return NO;
    }
}

- (BOOL)shouldSquelchKeystrokeWithString:(NSString *)keystr
                               modifiers:(NSEventModifierFlags)modflag {
    const NSEventModifierFlags deviceIndependentModifiers = modflag & NSEventModifierFlagDeviceIndependentFlagsMask;
    const BOOL pressingCommand = !!(deviceIndependentModifiers & NSEventModifierFlagCommand);
    if (!pressingCommand) {
        return NO;
    }

    if (keystr.length != 1) {
        return NO;
    }
    unichar byte = [keystr characterAtIndex:0];
    if (byte >= '0' && byte <= '9') {
        return YES;
    }
    if (byte == '\r') {
        // Enter key
        return YES;
    }

    return NO;
}

#pragma mark - iTermKeyMapper

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
    const NSEventModifierFlags modifiers = event.modifierFlags;
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

    return NO;
}

@end
