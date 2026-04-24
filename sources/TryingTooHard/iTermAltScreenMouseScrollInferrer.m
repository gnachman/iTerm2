//
//  iTermAltScreenMouseScrollInferrer.m
//  iTerm2
//
//  Created by George Nachman on 3/9/16.
//
//

#import "iTermAltScreenMouseScrollInferrer.h"

#import "NSEvent+iTerm.h"

typedef NS_ENUM(NSInteger, iTermAltScreenMouseScrollInferrerState) {
    iTermAltScreenMouseScrollInferrerStateInitial,
    iTermAltScreenMouseScrollInferrerStateScrolledUp,
    iTermAltScreenMouseScrollInferrerStateScrolledDown,
    iTermAltScreenMouseScrollInferrerStateFrustration
};
@implementation iTermAltScreenMouseScrollInferrer {
    iTermAltScreenMouseScrollInferrerState _state;
    BOOL _haveInferred;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _state = iTermAltScreenMouseScrollInferrerStateInitial;
    }
    return self;
}

- (void)firstResponderDidChange {
    self.state = iTermAltScreenMouseScrollInferrerStateInitial;
}

- (unichar)arrowKeyInEvent:(NSEvent *)theEvent {
    if ([theEvent it_modifierFlags] & NSEventModifierFlagNumericPad) {
        NSString *theArrow = [theEvent charactersIgnoringModifiers];
        if ([theArrow length] == 1) {
            return [theArrow characterAtIndex:0];
        }
    }
    return 0;
}

- (void)keyDown:(NSEvent *)theEvent {
    switch (_state) {
        case iTermAltScreenMouseScrollInferrerStateFrustration: {
            unichar arrowKey = [self arrowKeyInEvent:theEvent];
            if (arrowKey != NSDownArrowFunctionKey && arrowKey != NSUpArrowFunctionKey) {
                self.state = iTermAltScreenMouseScrollInferrerStateInitial;
            }
            break;
        }

        case iTermAltScreenMouseScrollInferrerStateInitial:
            break;

        case iTermAltScreenMouseScrollInferrerStateScrolledDown: {
            unichar arrowKey = [self arrowKeyInEvent:theEvent];
            if (arrowKey == NSDownArrowFunctionKey || arrowKey == NSUpArrowFunctionKey) {
                // User may have scrolled down and then pressed down arrow, or scrolled up +
                // been annoyed + scrolled back down + pressed arrow key.
                self.state = iTermAltScreenMouseScrollInferrerStateFrustration;
            } else {
                self.state = iTermAltScreenMouseScrollInferrerStateInitial;
            }
            break;
        }

        case iTermAltScreenMouseScrollInferrerStateScrolledUp:
            if ([self arrowKeyInEvent:theEvent] == NSUpArrowFunctionKey) {
                // User scrolled up + was frustrated + pressed up arrow key.
                self.state = iTermAltScreenMouseScrollInferrerStateFrustration;
            } else {
                self.state = iTermAltScreenMouseScrollInferrerStateInitial;
            }
            break;
    }
}

- (void)nonScrollWheelEvent:(NSEvent *)event {
    self.state = iTermAltScreenMouseScrollInferrerStateInitial;
}

- (void)scrollWheel:(NSEvent *)event {
    if (_state != iTermAltScreenMouseScrollInferrerStateFrustration) {
        if (event.scrollingDeltaY > 0) {
            self.state = iTermAltScreenMouseScrollInferrerStateScrolledUp;
        } else if (event.scrollingDeltaY < 0) {
            self.state = iTermAltScreenMouseScrollInferrerStateScrolledDown;
        } else if (event.scrollingDeltaX != 0) {
            self.state = iTermAltScreenMouseScrollInferrerStateInitial;
        }
    }
}

- (void)setState:(iTermAltScreenMouseScrollInferrerState)newState {
    if (newState == _state) {
        return;
    }
    if (_state == iTermAltScreenMouseScrollInferrerStateFrustration) {
        // Exit frustration
        [_delegate altScreenMouseScrollInferrerDidInferScrollingIntent:NO];
    }
    if (newState == iTermAltScreenMouseScrollInferrerStateFrustration) {
        if (_haveInferred) {
            // Don't want to enter frustration state more than once because it'll cause extra
            // cancellations.
            return;
        }
        // Enter frustration
        _haveInferred = YES;
        [_delegate altScreenMouseScrollInferrerDidInferScrollingIntent:YES];
    }
    _state = newState;
}

@end
