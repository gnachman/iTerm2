//
//  NSEvent+iTerm.m
//  iTerm2
//
//  Created by George Nachman on 11/24/14.
//
//

#import "NSEvent+iTerm.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"

#import <Carbon/Carbon.h>

@implementation NSEvent (iTerm)

- (NSEvent *)eventWithEventType:(CGEventType)eventType {
    CGEventRef cgEvent = [self CGEvent];
    CGPoint globalCoord = CGEventGetLocation(cgEvent);
    // Because the fakeEvent will have a nil window, adjust the coordinate to report a proper
    // locationInWindow. Not quite sure what's going on here, but this works :/.
    NSPoint windowOrigin = self.window.frame.origin;
    globalCoord.x -= windowOrigin.x;
    globalCoord.y -= self.window.screen.frame.origin.y;
    globalCoord.y += windowOrigin.y;

    CGEventRef fakeCgEvent = CGEventCreateMouseEvent(NULL,
                                                     eventType,
                                                     globalCoord,
                                                     2);
    int64_t clickCount = 1;
    if (self.type == NSEventTypeLeftMouseDown || self.type == NSEventTypeLeftMouseUp ||
        self.type == NSEventTypeRightMouseDown || self.type == NSEventTypeRightMouseUp ||
        self.type == NSEventTypeOtherMouseDown || self.type == NSEventTypeOtherMouseUp) {
        clickCount = [self clickCount];
    }
    CGEventSetIntegerValueField(fakeCgEvent, kCGMouseEventClickState, clickCount);
    CGEventSetFlags(fakeCgEvent, CGEventGetFlags(cgEvent));
    NSEvent *fakeEvent = [NSEvent eventWithCGEvent:fakeCgEvent];
    CFRelease(fakeCgEvent);
    return fakeEvent;
}

- (NSEvent *)mouseUpEventFromGesture {
    return [self eventWithEventType:kCGEventLeftMouseUp];
}

- (NSEvent *)mouseDownEventFromGesture {
    return [self eventWithEventType:kCGEventLeftMouseDown];
}

- (NSEvent *)eventWithButtonNumber:(NSInteger)buttonNumber {
    NSEvent *original = [NSEvent mouseEventWithType:NSEventTypeOtherMouseDown
                                           location:self.locationInWindow
                                      modifierFlags:self.modifierFlags
                                          timestamp:self.timestamp
                                       windowNumber:self.windowNumber
                                            context:[NSGraphicsContext currentContext]
                                        eventNumber:self.eventNumber
                                         clickCount:self.clickCount
                                           pressure:self.pressure];
    CGEventRef cgEvent = [original CGEvent];
    CGEventRef modifiedCGEvent = CGEventCreateCopy(cgEvent);
    CGEventSetIntegerValueField(modifiedCGEvent, kCGMouseEventButtonNumber, buttonNumber);
    NSEvent *fakeEvent = [NSEvent eventWithCGEvent:modifiedCGEvent];
    CFRelease(modifiedCGEvent);
    return fakeEvent;
}

- (NSEventModifierFlags)it_modifierFlags {
    if (![iTermAdvancedSettingsModel workAroundNumericKeypadBug]) {
        return self.modifierFlags;
    }
    
    switch (self.type) {
        case NSEventTypeKeyUp:
        case NSEventTypeKeyDown:
            break;
        default:
            return self.modifierFlags;
    }

    switch (self.keyCode) {
        case kVK_ANSI_KeypadEquals:
            return self.modifierFlags | NSEventModifierFlagNumericPad;
            
        default:
            return self.modifierFlags;
    }
}

- (NSEvent *)eventByRoundingScrollWheelClicksAwayFromZero {
    if (self.type != NSEventTypeScrollWheel) {
        return self;
    }
    if (self.phase != NSEventPhaseNone) {
        return self;
    }
    if (self.momentumPhase != NSEventPhaseNone) {
        return self;
    }

    // Mouse wheel
    CGEventRef cgEvent = self.CGEvent;
    const double originalDeltaY = CGEventGetDoubleValueField(cgEvent,
                                                             kCGScrollWheelEventFixedPtDeltaAxis1);
    if (round(originalDeltaY) != 0) {
        return self;
    }
    if (fabs(originalDeltaY) < 0.01) {
        return self;
    }
    // It looks like mouse wheel movements on mice with clicky wheels give you a step of
    // 0.1 per click. I'd like those to scroll by a whole line, so rewrite the event
    // to do that. All this stuff was done by trial and error.
    // Note that this makes it compatible with the behavior in
    // -[iTermScrollAccumulator accumulateDeltaYForMouseWheelEvent:] and nobody has
    // complained about that.
    CGEventSetDoubleValueField(cgEvent,
                               kCGScrollWheelEventFixedPtDeltaAxis1,
                               originalDeltaY > 0 ? 1 : -1);
    return [NSEvent eventWithCGEvent:cgEvent];
}

- (BOOL)it_eventGetsSpecialHandlingForAPINotifications {
    if (![self.charactersIgnoringModifiers isEqualToString:@"\t"] &&
        ![self.charactersIgnoringModifiers isEqualToString:@"\x19"]) {  // control-shift-tab sends 0x19
        return NO;
    }
    const NSEventModifierFlags mask = (NSEventModifierFlagControl |
                                       NSEventModifierFlagOption |
                                       NSEventModifierFlagCommand);
    if ((self.modifierFlags & mask) != NSEventModifierFlagControl) {
        return NO;
    }

    return YES;
}

- (BOOL)it_isNumericKeypadKey {
    // macOS says these are numeric keypad keys but for our purposes they are not.t
    switch (self.keyCode) {
        case kVK_UpArrow:
        case kVK_DownArrow:
        case kVK_LeftArrow:
        case kVK_RightArrow:
        case kVK_Home:
        case kVK_End:
        case kVK_PageUp:
        case kVK_PageDown:
        case kVK_ForwardDelete:
            return NO;
    }
    NSEventModifierFlags mutableModifiers = self.it_modifierFlags;

    // Enter key is on numeric keypad, but not marked as such
    const unichar character = self.characters.length > 0 ? [self.characters characterAtIndex:0] : 0;
    NSString *const charactersIgnoringModifiers = [self charactersIgnoringModifiers];
    const unichar characterIgnoringModifier = [charactersIgnoringModifiers length] > 0 ? [charactersIgnoringModifiers characterAtIndex:0] : 0;
    if (character == NSEnterCharacter && characterIgnoringModifier == NSEnterCharacter) {
        mutableModifiers |= NSEventModifierFlagNumericPad;
    }
    const BOOL isNumericKeypadKey = !!(mutableModifiers & NSEventModifierFlagNumericPad);
    return (isNumericKeypadKey || [NSEvent it_keycodeShouldHaveNumericKeypadFlag:self.keyCode]);
}

+ (BOOL)it_keycodeShouldHaveNumericKeypadFlag:(unsigned short)keycode {
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

- (BOOL)it_isVerticalScroll {
    return fabs(self.scrollingDeltaX) < fabs(self.scrollingDeltaY);
}

@end
