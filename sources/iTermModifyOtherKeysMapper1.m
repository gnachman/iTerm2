//
//  iTermModifyOtherKeysMapper1.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/1/20.
//

#import "iTermModifyOtherKeysMapper1.h"

#import "NSEvent+iTerm.h"
#import "iTermKeyboardHandler.h"

@implementation iTermModifyOtherKeysMapper1 {
    iTermStandardKeyMapper *_standard;
    iTermModifyOtherKeysMapper *_modifyOther;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _standard = [[iTermStandardKeyMapper alloc] init];
        _modifyOther = [[iTermModifyOtherKeysMapper alloc] init];
    }
    return self;
}

- (void)setDelegate:(id)delegate {
    _delegate = delegate;
    _standard.delegate = delegate;
    _modifyOther.delegate = delegate;
}

- (nullable NSString *)keyMapperStringForPreCocoaEvent:(NSEvent *)originalEvent {
    NSEvent *event = originalEvent;
    if ([self shouldModifyOtherKeysForEvent:event modifiedEvent:&event]) {
        return [_modifyOther keyMapperStringForPreCocoaEvent:event];
    } else {
        return [_standard keyMapperStringForPreCocoaEvent:event];
    }
}

- (nullable NSData *)keyMapperDataForPostCocoaEvent:(NSEvent *)originalEvent {
    NSEvent *event = originalEvent;
    if ([self shouldModifyOtherKeysForEvent:event modifiedEvent:&event]) {
        return [_modifyOther keyMapperDataForPostCocoaEvent:event];
    } else {
        return [_standard keyMapperDataForPostCocoaEvent:event];
    }
}

- (nullable NSData *)keyMapperDataForKeyUp:(NSEvent *)originalEvent {
    NSEvent *event = originalEvent;
    if ([self shouldModifyOtherKeysForEvent:event modifiedEvent:&event]) {
        return [_modifyOther keyMapperDataForKeyUp:event];
    } else {
        return [_standard keyMapperDataForKeyUp:event];
    }
}

- (BOOL)keyMapperShouldBypassPreCocoaForEvent:(NSEvent *)originalEvent {
    NSEvent *event = originalEvent;
    if ([self shouldModifyOtherKeysForEvent:event modifiedEvent:&event]) {
        return [_modifyOther keyMapperShouldBypassPreCocoaForEvent:event];
    } else {
        return [_standard keyMapperShouldBypassPreCocoaForEvent:event];
    }
}

- (void)keyMapperSetEvent:(NSEvent *)originalEvent {
    NSEvent *event = originalEvent;
    if ([self shouldModifyOtherKeysForEvent:event modifiedEvent:&event]) {
        [_modifyOther keyMapperSetEvent:event];
    } else {
         [_standard keyMapperSetEvent:event];
    }
}

// When a keystroke is routed to performKeyEquivalent instead of keyDown, this is called to check
// if the key mapper is interested in it.
- (BOOL)keyMapperWantsKeyEquivalent:(NSEvent *)originalEvent {
    NSEvent *event = originalEvent;
    if ([self shouldModifyOtherKeysForEvent:event modifiedEvent:&event]) {
        return [_modifyOther keyMapperWantsKeyEquivalent:event];
    } else {
        return [_standard keyMapperWantsKeyEquivalent:event];
    }
}

- (BOOL)optionSendsEscPlusForEvent:(NSEvent *)event {
    const NSEventModifierFlags modflag = event.it_modifierFlags;
    const BOOL rightAltPressed = (modflag & NSRightAlternateKeyMask) == NSRightAlternateKeyMask;
    const BOOL leftAltPressed = (modflag & NSEventModifierFlagOption) == NSEventModifierFlagOption && !rightAltPressed;
    if (!leftAltPressed && !rightAltPressed) {
        return NO;
    }
    iTermOptionKeyBehavior left;
    iTermOptionKeyBehavior right;
    [self.delegate modifyOtherKeys:_modifyOther getOptionKeyBehaviorLeft:&left right:&right];
    if (leftAltPressed) {
        return left == OPT_ESC;
    }
    if (rightAltPressed) {
        return right == OPT_ESC;
    }
    assert(NO);
    return NO;
}

// This is an attempt to port ModifyOtherKeys() from xterm's input.c in the case that
// keyboard->modify_now.other_keys == 1. It's probably wrong because xlib's documentation is
// aggressively vague.
//
// escPlus means that option is pressed and should send esc+.
- (BOOL)shouldModifyOtherKeysForEvent:(NSEvent *)event
                        modifiedEvent:(out NSEvent **)modifiedEvent {
    if (modifiedEvent) {
        *modifiedEvent = event;
    }
    if (event.type != NSEventTypeKeyDown) {
        return NO;
    }
    const BOOL escPlus = [self optionSendsEscPlusForEvent:event];
    if (event.it_modifierFlags & NSEventModifierFlagFunction) {
        // TOOD: Make sure this covers delete, F keys, arrow keys, page up, page down, home, and end.
        // If so delete the next if statement.
        return NO;
    }
    if (event.it_modifierFlags & NSEventModifierFlagNumericPad) {
        return NO;
    }
    const NSEventModifierFlags mask = (NSEventModifierFlagOption |
                                       NSEventModifierFlagShift |
                                       NSEventModifierFlagControl);
    if ((event.it_modifierFlags & mask) == 0) {
        return NO;
    }

    NSEventModifierFlags effectiveModifiers = event.it_modifierFlags & mask;
    unsigned short effectiveKeyCode = event.keyCode;
    NSString *effectiveCharacters = event.characters;
    if ((event.it_modifierFlags & NSEventModifierFlagControl) != 0 &&
        event.keyCode == kVK_Delete) {
        effectiveModifiers &= ~NSEventModifierFlagControl;
        effectiveKeyCode = kVK_ForwardDelete;
        unichar c[1] = { NSDeleteFunctionKey };
        effectiveCharacters = [NSString stringWithCharacters:c length:1];
        if (modifiedEvent) {
            *modifiedEvent = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                              location:event.locationInWindow
                                         modifierFlags:effectiveModifiers | (event.it_modifierFlags & (~mask)) | NSEventModifierFlagFunction
                                             timestamp:event.timestamp
                                          windowNumber:event.windowNumber
                                               context:nil
                                            characters:effectiveCharacters
                           charactersIgnoringModifiers:effectiveCharacters
                                             isARepeat:NO
                                               keyCode:effectiveKeyCode];
        }
    }

    const unichar character = event.characters.length > 0 ? [event.characters characterAtIndex:0] : 0;
    NSString *charactersIgnoringModifiers = event.charactersIgnoringModifiers;
    const unichar characterIgnoringModifiers = [charactersIgnoringModifiers length] > 0 ? [charactersIgnoringModifiers characterAtIndex:0] : 0;

    const BOOL shiftPressed = !!(effectiveModifiers & NSEventModifierFlagShift);
    unichar specialCode = 0xffff;
    if ((effectiveModifiers & NSEventModifierFlagControl) != 0) {
        specialCode = [iTermStandardKeyMapper codeForSpecialControlCharacter:character
                                                  characterIgnoringModifiers:characterIgnoringModifiers
                                                                shiftPressed:shiftPressed];
    }
    if (specialCode != 0xffff) {
        return NO;
    }
    if (effectiveKeyCode == kVK_Delete) {
        return NO;
    }

    if (effectiveKeyCode == kVK_Delete ||
        effectiveKeyCode == kVK_Escape) {
        if (escPlus) {
            effectiveModifiers &= ~NSEventModifierFlagOption;
        } else if ((event.it_modifierFlags & mask) == NSEventModifierFlagOption) {
            effectiveModifiers &= ~NSEventModifierFlagOption;
        }
    }

    if (effectiveModifiers == 0) {
        return NO;
    }

    if (effectiveKeyCode == kVK_Return ||
        effectiveKeyCode == kVK_Tab) {
        return YES;
    }

    if (character < 32) {
        if ((effectiveModifiers & mask) == NSEventModifierFlagControl) {
            return NO;
        }
        return YES;
    }

    if ((effectiveModifiers & mask) == NSEventModifierFlagShift) {
        return NO;
    }
    if ((effectiveModifiers & NSEventModifierFlagControl) != 0) {
        return YES;
    }
    return NO;
}

@end
