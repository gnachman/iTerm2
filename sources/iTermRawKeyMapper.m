//
//  iTermRawKeyMapper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/6/19.
//

#import "iTermRawKeyMapper.h"

#import "NSEvent+iTerm.h"

@implementation iTermRawKeyMapper

- (NSString *)keyMapperStringForPreCocoaEvent:(NSEvent *)event {
    return [self rawKeyStringForEvent:event];
}

- (NSData *)keyMapperDataForPostCocoaEvent:(NSEvent *)event {
    return [[self rawKeyStringForEvent:event] dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)keyMapperDataForKeyUp:(NSEvent *)event {
    return [[self rawKeyStringForEvent:event] dataUsingEncoding:NSUTF8StringEncoding];
}

- (BOOL)keyMapperShouldBypassPreCocoaForEvent:(NSEvent *)event {
    return NO;
}

#pragma mark - Private
static BOOL HasBits(NSUInteger value, NSUInteger required) {
    return ((value & required) == required);
}

- (int)csiModifiersForEventModifiers:(NSEventModifierFlags)eventModifiers repeat:(BOOL)repeat {
    const int leftShiftMask = 1 << 0;
    const int rightShiftMask = 1 << 1;
    const int leftOptionMask = 1 << 2;
    const int rightOptionMask = 1 << 3;
    const int leftControlMask = 1 << 4;
    const int rightControlMask = 1 << 5;
    const int leftCommandMask = 1 << 6;
    const int rightCommandMask = 1 << 7;
    const int repeatMask = 1 << 8;
    struct {
        NSUInteger mask;
        NSUInteger right;
        int leftFlag;
        int rightFlag;
    } descriptors[] = {
        { NSEventModifierFlagShift, NX_DEVICERSHIFTKEYMASK, leftShiftMask, rightShiftMask },
        { NSEventModifierFlagOption, NX_DEVICERALTKEYMASK, leftOptionMask, rightOptionMask },
        { NSEventModifierFlagControl, NX_DEVICERCTLKEYMASK, leftControlMask, rightControlMask },
        { NSEventModifierFlagCommand, NX_DEVICERCMDKEYMASK, leftCommandMask, rightCommandMask },
    };
    int flags = 0;
    for (int i = 0; i < sizeof(descriptors) / sizeof(*descriptors); i++) {
        if (HasBits(eventModifiers, descriptors[i].mask)) {
            if (HasBits(eventModifiers, descriptors[i].right)) {
                flags |= descriptors[i].rightFlag;
            } else {
                flags |= descriptors[i].leftFlag;
            }
        }
    }
    if (repeat) {
        flags |= repeatMask;
    }
    return flags + 1;
}

- (NSString *)nameForEvent:(NSEvent *)event {
    switch (event.type) {
        case NSEventTypeKeyDown:
            return @"d";
        case NSEventTypeKeyUp:
            return @"u";
        case NSEventTypeFlagsChanged:
            return @"f";
        default:
            return nil;
    }
}

- (NSString *)hexForString:(NSString *)string {
    NSMutableString *result = [NSMutableString string];
    const unsigned char *utf8 = (const unsigned char *)[string UTF8String];
    for (int i = 0; utf8 && utf8[i]; i++) {
        [result appendFormat:@"%02x", (unsigned int)utf8[i]];
    }
    return result;
}


// esc ] 1337 ; f ; flags ^G
// esc ] 1337 ; u ; flags ; hex-string ; key-code ; hex-string-ignoring-modifiers-except-shift ^G
// esc ] 1337 ; d ; flags ; hex-string ; key-code ; hex-string-ignoring-modifiers-except-shift ^G
- (NSString *)rawKeyStringForFlagsChangedEvent:(NSEvent *)event {
    int flags = [self csiModifiersForEventModifiers:event.it_modifierFlags repeat:NO];
    return [NSString stringWithFormat:@"%c]1337;%@;%@%c",
            27,
            [self nameForEvent:event],
            @(flags),
            7];
}

- (NSString *)rawKeyStringForEvent:(NSEvent *)event {
    if (event.type == NSEventTypeFlagsChanged) {
        return [self rawKeyStringForFlagsChangedEvent:event];
    }

    NSString *const name = [self nameForEvent:event];
    if (!name) {
        return nil;
    }
    const int flags = [self csiModifiersForEventModifiers:event.it_modifierFlags repeat:event.isARepeat];
    const BOOL isFunctionKey = !!(event.it_modifierFlags & NSEventModifierFlagFunction);
    return [NSString stringWithFormat:@"%c]1337;%@;%@;%@;%@;%@%c",
            27,
            name,
            @(flags),
            isFunctionKey ? @"" : [self hexForString:event.characters],
            @(event.keyCode),
            isFunctionKey ? @"" : [self hexForString:event.charactersIgnoringModifiers],
            7];
}

@end
