//
//  iTermModifyOtherKeysMapper1.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/1/20.
//

#import "iTermModifyOtherKeysMapper1.h"

#import "DebugLogging.h"
#import "NSEvent+iTerm.h"
#import "iTermKeyboardHandler.h"

typedef enum {
    iTermModifyOtherKeysMapper1KeyTypeRegular,  // Letters, unrecognized symbols, etc.
    iTermModifyOtherKeysMapper1KeyTypeNumber,
    iTermModifyOtherKeysMapper1KeyTypeSymbol,
    iTermModifyOtherKeysMapper1KeyTypeFunction,
    iTermModifyOtherKeysMapper1KeyTypeTab,
    iTermModifyOtherKeysMapper1KeyTypeEsc,
    iTermModifyOtherKeysMapper1KeyTypeReturn
} iTermModifyOtherKeysMapper1KeyType;

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
        DLog(@"Passing to other");
        return [_modifyOther keyMapperWantsKeyEquivalent:event];
    } else {
        DLog(@"Passing to standard");
        return [_standard keyMapperWantsKeyEquivalent:event];
    }
}

- (NSDictionary *)keyMapperDictionaryValue {
    [_standard.delegate standardKeyMapperWillMapKey:_standard];
    return @{ @"standard": iTermStandardKeyMapperConfigurationDictionaryValue(_standard.configuration),
              @"modifyOther": iTermModifyOtherKeysMapperDictionary(_modifyOther, self.delegate) };
}

- (iTermModifyOtherKeysMapper1KeyType)keyTypeForEvent:(NSEvent *)event {
    if (event.modifierFlags & NSEventModifierFlagFunction) {
        return iTermModifyOtherKeysMapper1KeyTypeFunction;
    }
    if (event.charactersIgnoringModifiers.length == 0) {
        // I'm pretty sure this can't happen.
        return iTermModifyOtherKeysMapper1KeyTypeFunction;
    }
    const unichar c = [event.charactersIgnoringModifiers characterAtIndex:0];
    if (c >= '0' && c <= '9') {
        return iTermModifyOtherKeysMapper1KeyTypeNumber;
    }
    NSString *symbols = @",.;=-\\?|{}_+~!@#$%^&*()";
    if ([symbols rangeOfString:[NSString stringWithCharacters:&c length:1]].location != NSNotFound) {
        return iTermModifyOtherKeysMapper1KeyTypeSymbol;
    }
    switch (event.keyCode) {
        case kVK_Tab:
            return iTermModifyOtherKeysMapper1KeyTypeTab;
        case kVK_Escape:
            return iTermModifyOtherKeysMapper1KeyTypeEsc;
        case kVK_Return:
            return iTermModifyOtherKeysMapper1KeyTypeReturn;
    }
    return iTermModifyOtherKeysMapper1KeyTypeRegular;
}

- (NSString *)escapeString:(NSString *)string {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (int i = 0; i < string.length; i++) {
        unichar c = [string characterAtIndex:i];
        if (c >= ' ' && c <= 0x7e) {
            [parts addObject:[NSString stringWithCharacters:&c length:1]];
        } else {
            [parts addObject:[NSString stringWithFormat:@"\\u%04x", c]];
        }
    }
    return [parts componentsJoinedByString:@""];
}

- (NSString *)mods:(NSEventModifierFlags)flags {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (flags & NSEventModifierFlagFunction) {
        [parts addObject:@"F_"];
    }
    if (flags & NSEventModifierFlagControl) {
        [parts addObject:@"C_"];
    }
    if (flags & NSEventModifierFlagOption) {
        [parts addObject:@"M_"];
    }
    if (flags & NSEventModifierFlagShift) {
        [parts addObject:@"S_"];
    }
    return [parts componentsJoinedByString:@" | "];
}

// This is an attempt to port ModifyOtherKeys() from xterm's input.c in the case that
// keyboard->modify_now.other_keys == 1. It's probably wrong because xlib's documentation is
// aggressively vague.
//
// escPlus means that option is pressed and should send esc+.
- (BOOL)shouldModifyOtherKeysForEvent:(NSEvent *)event
                        modifiedEvent:(out NSEvent **)modifiedEvent {
    DLog(@"%@", event);
    if (modifiedEvent) {
        *modifiedEvent = event;
    }
    if (event.type != NSEventTypeKeyDown) {
        DLog(@"Not key down");
        return NO;
    }
    if (event.it_modifierFlags & NSEventModifierFlagFunction) {
        DLog(@"Is a function key");
        return NO;
    }
    if (event.it_modifierFlags & NSEventModifierFlagNumericPad) {
        DLog(@"Is numeric keypad");
        return NO;
    }
    const NSEventModifierFlags mask = (NSEventModifierFlagOption |
                                       NSEventModifierFlagShift |
                                       NSEventModifierFlagControl);
    if ((event.it_modifierFlags & mask) == 0) {
        DLog(@"No modifier pressed");
        return NO;
    }

    switch ([self keyTypeForEvent:event]) {
        case iTermModifyOtherKeysMapper1KeyTypeRegular:
            return [self shouldModifyOtherKeysForRegularEvent:event modifiedEvent:modifiedEvent];
        case iTermModifyOtherKeysMapper1KeyTypeNumber:
            return [self shouldModifyOtherKeysForNumberEvent:event modifiedEvent:modifiedEvent];
        case iTermModifyOtherKeysMapper1KeyTypeSymbol:
            return [self shouldModifyOtherKeysForSymbolEvent:event modifiedEvent:modifiedEvent];
        case iTermModifyOtherKeysMapper1KeyTypeFunction:
            return [self shouldModifyOtherKeysForFunctionEvent:event modifiedEvent:modifiedEvent];
        case iTermModifyOtherKeysMapper1KeyTypeTab:
            return [self shouldModifyOtherKeysForTabEvent:event modifiedEvent:modifiedEvent];
        case iTermModifyOtherKeysMapper1KeyTypeEsc:
            return [self shouldModifyOtherKeysForEscEvent:event modifiedEvent:modifiedEvent];
        case iTermModifyOtherKeysMapper1KeyTypeReturn:
            return [self shouldModifyOtherKeysForReturnEvent:event modifiedEvent:modifiedEvent];
    }
}

- (BOOL)shouldModifyOtherKeysForRegularEvent:(NSEvent *)event
                               modifiedEvent:(out NSEvent **)modifiedEvent {
    DLog(@"Regular event");
    return NO;
}

- (BOOL)shouldModifyOtherKeysForNumberEvent:(NSEvent *)event
                              modifiedEvent:(out NSEvent **)modifiedEvent {
    DLog(@"Number event");
    const NSEventModifierFlags mask = (NSEventModifierFlagOption |
                                       NSEventModifierFlagShift |
                                       NSEventModifierFlagControl);
    const NSEventModifierFlags flags = event.it_modifierFlags & mask;
    const BOOL control = !!(flags & NSEventModifierFlagControl);
    const BOOL meta = !!(flags & NSEventModifierFlagOption);
    const BOOL shift = !!(flags & NSEventModifierFlagShift);
    const int digit = [event.charactersIgnoringModifiers characterAtIndex:0] - '0';
    DLog(@"control=%@ meta=%@ shirt=%@ digit=%@", @(control), @(meta), @(shift), @(digit));
    if ((control && meta && shift) ||
        (control && !meta && shift)) {
        switch (digit) {
            case 2:
            case 6:
                return NO;

            case 1:
            case 3:
            case 4:
            case 5:
            case 7:
            case 8:
            case 9:
            case 0:
                break;
        }
        return YES;
    }
    if ((control && meta) ||
        (control && !meta && !shift)) {
        switch (digit) {
            case 2:
            case 3:
            case 4:
            case 5:
            case 6:
            case 7:
            case 8:
                return NO;

            case 1:
            case 9:
            case 0:
                break;
        }
        return YES;
    }
    return NO;
}

- (BOOL)shouldModifyOtherKeysForSymbolEvent:(NSEvent *)event
                              modifiedEvent:(out NSEvent **)modifiedEvent {
    const NSEventModifierFlags mask = (NSEventModifierFlagOption |
                                       NSEventModifierFlagShift |
                                       NSEventModifierFlagControl);
    const NSEventModifierFlags flags = event.it_modifierFlags & mask;
    const BOOL control = !!(flags & NSEventModifierFlagControl);
    const BOOL meta = !!(flags & NSEventModifierFlagOption);
    const BOOL shift = !!(flags & NSEventModifierFlagShift);
    DLog(@"control=%@ meta=%@ shirt=%@ charactersIgnoringModifiers=%@", @(control), @(meta), @(shift), event.charactersIgnoringModifiers);

    if (control && !meta && !shift) {
        return ![@"{}[]\\`'" containsString:event.charactersIgnoringModifiers];
    }
    if (control && !meta && shift) {
        return ![@"@^{}[]\\-_`'/" containsString:event.charactersIgnoringModifiers];
    }
    if (control && meta && !shift) {
        return ![@"{}[]\\`'" containsString:event.charactersIgnoringModifiers];
    }
    if (control && meta && shift) {
        return ![@"@^{}[]\\-_`'/" containsString:event.charactersIgnoringModifiers];
    }
    return NO;
}

- (BOOL)shouldModifyOtherKeysForFunctionEvent:(NSEvent *)event
                                modifiedEvent:(out NSEvent **)modifiedEvent {
    DLog(@"function event");
    return NO;
}

- (BOOL)shouldModifyOtherKeysForTabEvent:(NSEvent *)event
                           modifiedEvent:(out NSEvent **)modifiedEvent {
    const NSEventModifierFlags mask = (NSEventModifierFlagOption |
                                       NSEventModifierFlagShift |
                                       NSEventModifierFlagControl);
    const NSEventModifierFlags flags = event.it_modifierFlags & mask;
    const BOOL control = !!(flags & NSEventModifierFlagControl);
    const BOOL meta = !!(flags & NSEventModifierFlagOption);
    const BOOL shift = !!(flags & NSEventModifierFlagShift);
    DLog(@"control=%@ meta=%@ shift=%@", @(control), @(meta), @(shift));

    if (control && !meta && !shift) {
        return YES;
    }
    return NO;
}

- (BOOL)shouldModifyOtherKeysForEscEvent:(NSEvent *)event
                        modifiedEvent:(out NSEvent **)modifiedEvent {
    const NSEventModifierFlags mask = (NSEventModifierFlagOption |
                                       NSEventModifierFlagShift |
                                       NSEventModifierFlagControl);
    const NSEventModifierFlags flags = event.it_modifierFlags & mask;
    const BOOL control = !!(flags & NSEventModifierFlagControl);
    const BOOL meta = !!(flags & NSEventModifierFlagOption);
    const BOOL shift = !!(flags & NSEventModifierFlagShift);
    DLog(@"control=%@ meta=%@ shift=%@", @(control), @(meta), @(shift));
    if ((control && meta) ||
        (!control && meta && shift)) {
        return YES;
    }
    return NO;
}

- (BOOL)shouldModifyOtherKeysForReturnEvent:(NSEvent *)event
                              modifiedEvent:(out NSEvent **)modifiedEvent {
    const NSEventModifierFlags mask = (NSEventModifierFlagOption |
                                       NSEventModifierFlagShift |
                                       NSEventModifierFlagControl);
    const NSEventModifierFlags flags = event.it_modifierFlags & mask;
    const BOOL control = !!(flags & NSEventModifierFlagControl);
    const BOOL meta = !!(flags & NSEventModifierFlagOption);
    const BOOL shift = !!(flags & NSEventModifierFlagShift);
    DLog(@"control=%@ meta=%@ shift=%@", @(control), @(meta), @(shift));
    if (control || shift || meta) {
        return YES;
    }
    return NO;
}

@end
