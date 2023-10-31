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
#import "NSEvent+iTerm.h"
#import "NSStringITerm.h"
#import "VT100Output.h"

@implementation iTermStandardKeyMapper {
    NSEvent *_event;
}

- (void)updateConfigurationWithEvent:(NSEvent *)event {
    DLog(@"Load configuration for event %@", event);
    _event = event;
    [self.delegate standardKeyMapperWillMapKey:self];
}

- (NSData *)keyMapperDataForKeyUp:(NSEvent *)event {
    return nil;
}

- (BOOL)keyMapperWantsKeyEquivalent:(NSEvent *)event {
    const NSEventModifierFlags mask = (NSEventModifierFlagCommand |
                                       NSEventModifierFlagControl |
                                       NSEventModifierFlagShift |
                                       NSEventModifierFlagFunction);
    if ((event.modifierFlags & mask) == (NSEventModifierFlagControl | NSEventModifierFlagShift | NSEventModifierFlagFunction)) {
        // control+shift+arrow takes this path. See issue 8382. Possibly other things should, too.
        DLog(@"control|shift|function");
        return YES;
    }
    DLog(@"return no");
    return NO;
}

#pragma mark - Pre-Cocoa

- (NSString *)preCocoaString {
    if ([_event it_isNumericKeypadKey]) {
        DLog(@"PTYSession keyDown numeric keypad");
        NSData *data = [_configuration.outputFactory keypadDataForString:_event.characters
                                                               modifiers:_event.it_modifierFlags];
        return [[NSString alloc] initWithData:data encoding:_configuration.encoding];
    }

    const unsigned int modflag = [_event it_modifierFlags];
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
    const BOOL shiftPressed = !!(event.it_modifierFlags & NSEventModifierFlagShift);

    return [iTermStandardKeyMapper codeForSpecialControlCharacter:character
                                       characterIgnoringModifiers:characterIgnoringModifiers
                                                     shiftPressed:shiftPressed];
}

+ (unichar)codeForSpecialControlCharacter:(unichar)character
               characterIgnoringModifiers:(unichar)characterIgnoringModifiers
                             shiftPressed:(BOOL)shiftPressed {
    if (character == '|') {
        // This is necessary to handle Japanese keyboards correctly. Pressing Control+backslash
        // generates characters=@"|" and charactersIgnoringModifiers=@"¥". This code path existed
        // in iTerm 0.1.
        DLog(@"C-backslash");
        return 28;  // Control-backslash
    } else if (character == '/' && shiftPressed) {
        // This was in the original iTerm code. It's the normal path for US keyboards for ^-?.
        DLog(@"C-?");
        return 127;
    } else if (character == 0x7f) {
        DLog(@"C-h");
        return 8;  // Control-backspace -> ^H
    }

    DLog(@"Checking characterIgnoringModifiers %@", @(characterIgnoringModifiers));
    // control-number comes from xterm.
    switch (characterIgnoringModifiers) {
        case ' ':
        case '2':
        case '@':
            return 0;

        case '3':
        case '[':
            return 27;

        case '4':
        case '\\':
        case '|':
            return 28;

        case '5':
        case ']':
            return 29;

        case '^':
        case '6':
            return 30;

        case '7':
        case '-':
        case '_':
        case '/':
            return 31;

        case '8':
            return 127;
    }

    return 0xffff;
}

#pragma mark - Post-Cocoa

- (NSData *)postCocoaData {
    if (_event.it_modifierFlags & NSEventModifierFlagFunction) {
        return [self dataForFunctionKeyPress];
    }

    const NSEventModifierFlags mask = NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagShift;
    if ([_event.characters isEqual:@"\x7f"]) {
        if ((_event.it_modifierFlags & mask) == (NSEventModifierFlagOption | NSEventModifierFlagControl)) {
            // This is an odd edge case that I noticed in xterm. Control-option-backspace is the only
            // collection of modifiers+backspace that gets you a CSI ~ sequence that I could find.
            return [[NSString stringWithFormat:@"%c[3;7~", 27] dataUsingEncoding:NSUTF8StringEncoding];
        }
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
    NSEventModifierFlags mutableModifiers = _event.it_modifierFlags;

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

    if ([_event it_isNumericKeypadKey]) {
        DLog(@"PTYSession keyDown numeric keypad");
        return [_configuration.outputFactory keypadDataForString:characters
                                                       modifiers:_event.it_modifierFlags];
    }

    if (characters.length != 1 || [characters characterAtIndex:0] > 0x7f) {
        DLog(@"PTYSession keyDown non-ascii");
        return [characters dataUsingEncoding:_configuration.encoding];
    }

    if ([characters isEqualToString:@"\x7f"] && !!(mutableModifiers & NSEventModifierFlagControl)) {
        // Control+(any mods)+backspace -> ^H
        const unichar ch = 8;
        return [NSData dataWithBytes:&ch length:1];
    }
    DLog(@"PTYSession keyDown ascii");
    // Commit a00a9385b2ed722315ff4d43e2857180baeac2b4 in old-iterm suggests this is
    // necessary for some Japanese input sources, but is vague.
    return [characters dataUsingEncoding:NSUTF8StringEncoding];
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

- (NSData *)dataWhenOptionPressed {
    const unichar unicode = _event.characters.length > 0 ? [_event.characters characterAtIndex:0] : 0;
    const BOOL controlPressed = !!(_event.it_modifierFlags & NSEventModifierFlagControl);
    if (controlPressed && _event.characters.length > 0) {
        const BOOL shiftPressed = !!(_event.it_modifierFlags & NSEventModifierFlagShift);
        NSString *charactersIgnoringModifiers = _event.charactersIgnoringModifiers;
        const unichar characterIgnoringModifiers = [charactersIgnoringModifiers length] > 0 ? [charactersIgnoringModifiers characterAtIndex:0] : 0;
        const unichar specialCode = [iTermStandardKeyMapper codeForSpecialControlCharacter:unicode
                                                                characterIgnoringModifiers:characterIgnoringModifiers
                                                                              shiftPressed:shiftPressed];
        if (specialCode != 0xffff) {
            // e.g., control-2. This lets control-meta-2 send ^[^@
            return [[NSString stringWithCharacters:&specialCode length:1] dataUsingEncoding:_configuration.encoding];
        }
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
    const NSEventModifierFlags modifiers = _event.it_modifierFlags;
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
    const NSEventModifierFlags modifiers = _event.it_modifierFlags;
    const unichar unicode = [characters length] > 0 ? [characters characterAtIndex:0] : 0;
    DLog(@"PTYSession keyDown is a function key. unicode=%@", @(unicode));

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
            return [_configuration.outputFactory keyDelete:modifiers];
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
            return [_configuration.outputFactory keyFunction:unicode - NSF1FunctionKey + 1
                                                   modifiers:modifiers];
    }

    return [characters dataUsingEncoding:_configuration.encoding];
}

// In issue 4039 we see that in some cases the numeric keypad mask isn't set properly.
- (BOOL)keycodeShouldHaveNumericKeypadFlag:(unsigned short)keycode {
    return [NSEvent it_keycodeShouldHaveNumericKeypadFlag:keycode];
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

- (void)keyMapperSetEvent:(NSEvent *)event {
    [self updateConfigurationWithEvent:event];
}

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
        DLog(@"isSpecialKey: %@ -> bypass pre-cocoa", event);
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
        DLog(@"isNonEmpty=%@ rightAltPressed=%@ leftAltPressed=%@ leftOptionModifiesKey=%@ rightOptionModifiesKey=%@ willSendOptionModifiedKey=%@ -> bypass pre-cocoa",
             @(isNonEmpty),
             @(rightAltPressed),
             @(leftAltPressed),
             @(leftOptionModifiesKey),
             @(rightOptionModifiesKey),
             @(willSendOptionModifiedKey));
        return YES;
    }

    DLog(@"Not bypassing pre-cocoa");
    return NO;
}

- (NSDictionary *)keyMapperDictionaryValue {
    [self.delegate standardKeyMapperWillMapKey:self];
    return iTermStandardKeyMapperConfigurationDictionaryValue(_configuration);
}

@end

NSDictionary *iTermStandardKeyMapperConfigurationDictionaryValue(iTermStandardKeyMapperConfiguration *config) {
    return @{ @"output": config.outputFactory.configDictionary ?: @{},
              @"encoding": @(config.encoding),
              @"leftOptionKey": @(config.leftOptionKey),
              @"rightOptionKey": @(config.rightOptionKey),
              @"screenlike": @(config.screenlike)
    };
}

@implementation iTermStandardKeyMapperConfiguration
@end

