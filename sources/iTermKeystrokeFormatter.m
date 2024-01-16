//
//  iTermKeystrokeFormatter.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/21/20.
//

#import "iTermKeystrokeFormatter.h"

#import "iTermKeystroke.h"
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
        [result appendString: @"num-"];
    }
    [result appendString:charactersAsString];
    return result;
}

+ (NSString *)stringForKeyCode:(CGKeyCode)virtualKeyCode
                    hasKeyCode:(BOOL)hasKeyCode
                     character:(unichar)character
                       isArrow:(BOOL *)isArrow {
    TISInputSourceRef inputSource = NULL;
    NSString *result = nil;

    if (hasKeyCode) {
        inputSource = TISCopyCurrentKeyboardInputSource();
        if (inputSource == NULL) {
            goto exit;
        }

        CFDataRef keyLayoutData = TISGetInputSourceProperty(inputSource,
                                                            kTISPropertyUnicodeKeyLayoutData);
        if (keyLayoutData == NULL) {
            goto exit;
        }

        const UCKeyboardLayout *keyLayoutPtr = (const UCKeyboardLayout *)CFDataGetBytePtr(keyLayoutData);
        if (keyLayoutPtr == NULL) {
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
            goto exit;
        }

        if (actualStringLength == 0) {
            goto exit;
        }

        if (unicodeString[0] <= ' ' || unicodeString[0] == 127) {
            goto exit;
        }

        result = [NSString stringWithCharacters:unicodeString length:actualStringLength];
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
            aString = NSLocalizedStringFromTableInBundle(@"Del→",
                                                         @"iTerm",
                                                         [NSBundle bundleForClass:[self class]],
                                                         @"Key Names");
            break;
        case 0x7f:
            aString = NSLocalizedStringFromTableInBundle(@"←Delete",
                                                         @"iTerm",
                                                         [NSBundle bundleForClass:[self class]],
                                                         @"Key Names");
            break;
        case NSEndFunctionKey:
            aString = NSLocalizedStringFromTableInBundle(@"End",
                                                         @"iTerm",
                                                         [NSBundle bundleForClass:[self class]],
                                                         @"Key Names");
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
            aString = NSLocalizedStringFromTableInBundle(@"Help",
                                                         @"iTerm",
                                                         [NSBundle bundleForClass:[self class]],
                                                         @"Key Names");
            break;
        case NSHomeFunctionKey:
            aString = NSLocalizedStringFromTableInBundle(@"Home",
                                                         @"iTerm",
                                                         [NSBundle bundleForClass:[self class]],
                                                         @"Key Names");
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
            aString = @"Numlock";
            break;
        case NSPageDownFunctionKey:
            aString = @"Page Down";
            break;
        case NSPageUpFunctionKey:
            aString = @"Page Up";
            break;
        case 0x3: // 'enter' on numeric key pad
            aString = @"↩";
            break;
        case NSInsertFunctionKey:  // Fall through
        case NSInsertCharFunctionKey:
            aString = @"Insert";
            break;

        default:
            if (character > ' ' && (character < 0xe800 || character > 0xfdff) && character < 0xffff) {
                aString = [NSString stringWithFormat:@"%C", (unichar)character];
            } else {
                switch (character) {
                    case ' ':
                        aString = @"Space";
                        break;

                    case '\r':
                        aString = @"Return ↩";
                        break;

                    case 27:
                        aString = @"Esc ⎋";
                        break;

                    case '\t':
                        aString = @"Tab ↦";
                        break;

                    case 0x19:
                        // back-tab
                        aString = @"Tab ↤";
                        break;

                    default:
                        aString = [NSString stringWithFormat: @"Hex Code 0x%x", character];
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
