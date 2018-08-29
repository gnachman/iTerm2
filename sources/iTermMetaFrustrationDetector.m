//
//  iTermMetaFrustrationDetector.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/23/18.
//

#import "iTermMetaFrustrationDetector.h"

#import "DebugLogging.h"
#import <Carbon/Carbon.h>

#define NSLeftAlternateKeyMask  (0x000020 | NSEventModifierFlagOption)
#define NSRightAlternateKeyMask (0x000040 | NSEventModifierFlagOption)

typedef NS_ENUM(NSUInteger, iTermMetaFrustrationDetectorState) {
    iTermMetaFrustrationDetectorReady,
    iTermMetaFrustrationDetectorWaitingForBackspace,
    iTermMetaFrustrationDetectorWaitingForEsc,
    iTermMetaFrustrationDetectorTriggered,
};

@implementation iTermMetaFrustrationDetector {
    NSTimeInterval _lastTime;
    iTermMetaFrustrationDetectorState _state;
    BOOL _lastWasLeft;
}

- (void)didSendKeyEvent:(NSEvent *)event {
    switch (_state) {
        case iTermMetaFrustrationDetectorTriggered:
            break;

        case iTermMetaFrustrationDetectorReady:
            if ([self eventIsCandidate:event]) {
                _lastTime = [NSDate timeIntervalSinceReferenceDate];
                _lastWasLeft = (event.modifierFlags & NSLeftAlternateKeyMask) == NSLeftAlternateKeyMask;
                self.state = iTermMetaFrustrationDetectorWaitingForBackspace;
            }
            break;

        case iTermMetaFrustrationDetectorWaitingForBackspace:
            if ([self eventIsBackspace:event]) {
                const NSTimeInterval threshold = 1.5;
                if ([NSDate timeIntervalSinceReferenceDate] - _lastTime < threshold) {
                    _lastTime = [NSDate timeIntervalSinceReferenceDate];
                    self.state = iTermMetaFrustrationDetectorWaitingForEsc;
                } else {
                    self.state = iTermMetaFrustrationDetectorReady;
                }
            } else {
                self.state = iTermMetaFrustrationDetectorReady;
            }
            break;

        case iTermMetaFrustrationDetectorWaitingForEsc:
            if ([self eventIsEsc:event]) {
                const NSTimeInterval threshold = 3;
                if ([NSDate timeIntervalSinceReferenceDate] - _lastTime < threshold) {
                    if (_lastWasLeft) {
                        [self.delegate metaFrustrationDetectorDidDetectFrustrationForLeftOption];
                    } else {
                        [self.delegate metaFrustrationDetectorDidDetectFrustrationForRightOption];
                    }
                    self.state = iTermMetaFrustrationDetectorTriggered;
                } else {
                    self.state = iTermMetaFrustrationDetectorReady;
                }
            }
            break;
    }
}

#pragma mark - Private

- (void)setState:(iTermMetaFrustrationDetectorState)newState {
    NSString *(^name)(iTermMetaFrustrationDetectorState) = ^NSString *(iTermMetaFrustrationDetectorState state) {
        switch (state) {
            case iTermMetaFrustrationDetectorWaitingForEsc:
                return @"waiting-for-esc";
            case iTermMetaFrustrationDetectorTriggered:
                return @"triggered";
            case iTermMetaFrustrationDetectorReady:
                return @"ready";
            case iTermMetaFrustrationDetectorWaitingForBackspace:
                return @"waiting-for-backspace";
        }
        return @"bogus";
    };
    DLog(@"%@ -> %@", name(_state), name(newState));
    _state = newState;
}

- (BOOL)eventIsCandidate:(NSEvent *)event {
    const NSEventModifierFlags mask = (NSEventModifierFlagOption |
                                       NSEventModifierFlagShift |
                                       NSEventModifierFlagControl |
                                       NSEventModifierFlagFunction |
                                       NSEventModifierFlagCommand);
    if ((event.modifierFlags & mask) != NSEventModifierFlagOption) {
        return NO;
    }
    static NSSet<NSNumber *> *alphabeticKeyCodes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        alphabeticKeyCodes = [NSSet setWithArray:@[@(kVK_ANSI_A), @(kVK_ANSI_B),
                                                   @(kVK_ANSI_C), @(kVK_ANSI_D),
                                                   @(kVK_ANSI_E), @(kVK_ANSI_F),
                                                   @(kVK_ANSI_G), @(kVK_ANSI_H),
                                                   @(kVK_ANSI_I), @(kVK_ANSI_J),
                                                   @(kVK_ANSI_K), @(kVK_ANSI_L),
                                                   @(kVK_ANSI_M), @(kVK_ANSI_N),
                                                   @(kVK_ANSI_O), @(kVK_ANSI_P),
                                                   @(kVK_ANSI_Q), @(kVK_ANSI_R),
                                                   @(kVK_ANSI_S), @(kVK_ANSI_T),
                                                   @(kVK_ANSI_U), @(kVK_ANSI_V),
                                                   @(kVK_ANSI_W), @(kVK_ANSI_X),
                                                   @(kVK_ANSI_Y), @(kVK_ANSI_Z)] ];
    });
    return ([alphabeticKeyCodes containsObject:@(event.keyCode)]);
}

- (BOOL)eventIsBackspace:(NSEvent *)event {
    const NSEventModifierFlags mask = (NSEventModifierFlagOption |
                                       NSEventModifierFlagShift |
                                       NSEventModifierFlagControl |
                                       NSEventModifierFlagFunction |
                                       NSEventModifierFlagCommand);
    if ((event.modifierFlags & mask) == 0 && event.keyCode == kVK_Delete) {
        return YES;
    }
    if ((event.modifierFlags & mask) == NSEventModifierFlagControl && event.keyCode == kVK_ANSI_H) {
        return YES;
    }
    return NO;
}

- (BOOL)eventIsEsc:(NSEvent *)event {
    const NSEventModifierFlags mask = (NSEventModifierFlagOption |
                                       NSEventModifierFlagShift |
                                       NSEventModifierFlagControl |
                                       NSEventModifierFlagFunction |
                                       NSEventModifierFlagCommand);
    return (event.modifierFlags & mask) == 0 && event.keyCode == kVK_Escape;
}

@end
