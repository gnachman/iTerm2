//
//  iTermKeystrokeFormatter.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/21/20.
//

#import "iTermKeystrokeFormatter.h"

#import "iTermKeystroke.h"
#import "DebugLogging.h"
#import "NSStringITerm.h"

#import <Carbon/Carbon.h>

@implementation iTermKeystrokeFormatter

+ (NSString *)stringForKeystroke:(iTermKeystroke *)keystroke {
    BOOL isArrow = NO;
    NSString *charactersAsString = [self stringForKeyCode:keystroke.virtualKeyCode
                                               hasKeyCode:keystroke.hasVirtualKeyCode
                                                character:keystroke.character
                                                  isArrow:&isArrow];

    NSMutableString *result = [[NSString stringForModifiersWithMask:keystroke.modifierFlags] mutableCopy];
    if ((keystroke.modifierFlags & NSEventModifierFlagNumericPad) && !isArrow) {
        [result appendString: NSLocalizedStringWithDefaultValue(@"KeyName.NumericKeypadPrefix", nil, [NSBundle mainBundle], @"num-", @"Prefix shown before a key name to indicate it is on the numeric keypad, as in “num-5”")];
    }
    [result appendString:charactersAsString];
    return result;
}

+ (NSString *)stringForKeystrokeIgnoringKeycode:(iTermKeystroke *)keystroke {
    BOOL isArrow = NO;
    NSString *charactersAsString = [self stringForCharacter:keystroke.character isArrow:&isArrow];

    NSMutableString *result = [[NSString stringForModifiersWithMask:keystroke.modifierFlags] mutableCopy];
    if ((keystroke.modifierFlags & NSEventModifierFlagNumericPad) && !isArrow) {
        [result appendString: NSLocalizedStringWithDefaultValue(@"KeyName.NumericKeypadPrefix", nil, [NSBundle mainBundle], @"num-", @"Prefix shown before a key name to indicate it is on the numeric keypad, as in “num-5”")];
    }
    [result appendString:charactersAsString];
    return result;
}

+ (NSString *)stringForKeyCode:(CGKeyCode)virtualKeyCode
                    hasKeyCode:(BOOL)hasKeyCode
                     character:(unichar)character
                       isArrow:(BOOL *)isArrow {
    DLog(@"stringForKeyCode:%@ hasKeyCode:%@ character:%@", @(virtualKeyCode), @(hasKeyCode), @(character));
    TISInputSourceRef inputSource = NULL;
    NSString *result = nil;

    if (hasKeyCode) {
        inputSource = TISCopyCurrentKeyboardInputSource();
        if (inputSource == NULL) {
            DLog(@"nil input source");
            goto exit;
        }

        CFDataRef keyLayoutData = TISGetInputSourceProperty(inputSource,
                                                            kTISPropertyUnicodeKeyLayoutData);
        if (keyLayoutData == NULL) {
            DLog(@"nil key layout data");
            goto exit;
        }

        const UCKeyboardLayout *keyLayoutPtr = (const UCKeyboardLayout *)CFDataGetBytePtr(keyLayoutData);
        if (keyLayoutPtr == NULL) {
            DLog(@"nil key layout");
            goto exit;
        }

        UInt32 deadKeyState = 0;
        UniChar unicodeString[4];
        UniCharCount actualStringLength;

        OSStatus status = UCKeyTranslate(keyLayoutPtr,
                                         virtualKeyCode,
                                         kUCKeyActionDisplay,
                                         0,
                                         LMGetKbdType(),
                                         kUCKeyTranslateNoDeadKeysBit,
                                         &deadKeyState,
                                         sizeof(unicodeString) / sizeof(*unicodeString),
                                         &actualStringLength,
                                         unicodeString);
        if (status != noErr) {
            DLog(@"status %@", @(status));
            goto exit;
        }

        if (actualStringLength == 0) {
            DLog(@"empty actual string");
            goto exit;
        }

        if (unicodeString[0] <= ' ' || unicodeString[0] == 127) {
            DLog(@"invalid unicodeString[0] %@", @(unicodeString[0]));
            goto exit;
        }

        result = [NSString stringWithCharacters:unicodeString length:actualStringLength];
        DLog(@"result=%@", result);
    }

exit:
    if (inputSource != NULL) {
        CFRelease(inputSource);
    }
    if (result == nil) {
        result = [self stringForCharacter:character isArrow:isArrow];
    }
    return result;
}

+ (NSString *)stringForCharacter:(unsigned int)character isArrow:(BOOL *)isArrowPtr {
    DLog(@"stringForCharacter:%@", @(character));
    BOOL isArrow = NO;
    NSString *aString = nil;
    switch (character) {
        case NSDownArrowFunctionKey:
            aString = @"↓";
            isArrow = YES;
            break;
        case NSLeftArrowFunctionKey:
            aString = @"←";
            isArrow = YES;
            break;
        case NSRightArrowFunctionKey:
            aString =@"→";
            isArrow = YES;
            break;
        case NSUpArrowFunctionKey:
            aString = @"↑";
            isArrow = YES;
            break;
        case NSDeleteFunctionKey:
            aString = NSLocalizedStringWithDefaultValue(@"KeyName.ForwardDelete", nil, [NSBundle mainBundle], @"Del→", @"Display name for the forward-delete key in a keystroke");
            break;
        case 0x7f:
            aString = NSLocalizedStringWithDefaultValue(@"KeyName.Delete", nil, [NSBundle mainBundle], @"←Delete", @"Display name for the backspace/delete key in a keystroke");
            break;
        case NSEndFunctionKey:
            aString = NSLocalizedStringWithDefaultValue(@"KeyName.End", nil, [NSBundle mainBundle], @"End", @"Display name for the End key in a keystroke");
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
            aString = [NSString stringWithFormat: @"F%d", (character - NSF1FunctionKey + 1)];
            break;
        case NSHelpFunctionKey:
            aString = NSLocalizedStringWithDefaultValue(@"KeyName.Help", nil, [NSBundle mainBundle], @"Help", @"Display name for the Help key in a keystroke");
            break;
        case NSHomeFunctionKey:
            aString = NSLocalizedStringWithDefaultValue(@"KeyName.Home", nil, [NSBundle mainBundle], @"Home", @"Display name for the Home key in a keystroke");
            break;

        // These are standard on Apple en_GB keyboards where ~ and ` go on US keyboards (between esc
        // and tab).
        case 0xa7:
            aString = @"§";
            break;
        case 0xb1: // shifted version of above.
            aString = @"±";
            break;

        case '0':
        case '1':
        case '2':
        case '3':
        case '4':
        case '5':
        case '6':
        case '7':
        case '8':
        case '9':
            aString = [NSString stringWithFormat: @"%d", (character - '0')];
            break;
        case '=':
            aString = @"=";
            break;
        case '/':
            aString = @"/";
            break;
        case '*':
            aString = @"*";
            break;
        case '-':
            aString = @"-";
            break;
        case '+':
            aString = @"+";
            break;
        case '.':
            aString = @".";
            break;
        case NSClearLineFunctionKey:
            aString = NSLocalizedStringWithDefaultValue(@"KeyName.NumLock", nil, [NSBundle mainBundle], @"Numlock", @"Display name for the Num Lock key in a keystroke");
            break;
        case NSPageDownFunctionKey:
            aString = NSLocalizedStringWithDefaultValue(@"KeyName.PageDown", nil, [NSBundle mainBundle], @"Page Down", @"Display name for the Page Down key in a keystroke");
            break;
        case NSPageUpFunctionKey:
            aString = NSLocalizedStringWithDefaultValue(@"KeyName.PageUp", nil, [NSBundle mainBundle], @"Page Up", @"Display name for the Page Up key in a keystroke");
            break;
        case 0x3: // 'enter' on numeric key pad
            aString = @"↩";
            break;
        case NSInsertFunctionKey:  // Fall through
        case NSInsertCharFunctionKey:
            aString = NSLocalizedStringWithDefaultValue(@"KeyName.Insert", nil, [NSBundle mainBundle], @"Insert", @"Display name for the Insert key in a keystroke");
            break;

        default:
            if (character > ' ' && (character < 0xe800 || character > 0xfdff) && character < 0xffff) {
                DLog(@"Is regular character");
                aString = [NSString stringWithFormat:@"%C", (unichar)character];
            } else {
                DLog(@"Is special");
                switch (character) {
                    case ' ':
                        aString = NSLocalizedStringWithDefaultValue(@"KeyName.Space", nil, [NSBundle mainBundle], @"Space", @"Display name for the Space bar in a keystroke");
                        break;

                    case '\r':
                        aString = NSLocalizedStringWithDefaultValue(@"KeyName.Return", nil, [NSBundle mainBundle], @"Return ↩", @"Display name for the Return key in a keystroke; keep the ↩ symbol");
                        break;

                    case 27:
                        aString = NSLocalizedStringWithDefaultValue(@"KeyName.Escape", nil, [NSBundle mainBundle], @"Esc ⎋", @"Display name for the Escape key in a keystroke; keep the ⎋ symbol");
                        break;

                    case '\t':
                        aString = NSLocalizedStringWithDefaultValue(@"KeyName.Tab", nil, [NSBundle mainBundle], @"Tab ↦", @"Display name for the Tab key in a keystroke; keep the ↦ symbol");
                        break;

                    case 0x19:
                        // back-tab
                        aString = NSLocalizedStringWithDefaultValue(@"KeyName.BackTab", nil, [NSBundle mainBundle], @"Tab ↤", @"Display name for the back-tab (Shift-Tab) key in a keystroke; keep the ↤ symbol");
                        break;

                    default:
                        aString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyName.HexCode", nil, [NSBundle mainBundle], @"Hex Code 0x%x", @"Display name for an unnamed key shown as its hexadecimal character code; %x is the hex value"), character];
                        break;
                }
            }
            break;
    }
    if (isArrowPtr) {
        *isArrowPtr = isArrow;
    }
    return aString;
}


@end
