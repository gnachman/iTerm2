//
//  iTermAltScreenMouseScrollInferer.m
//  iTerm2
//
//  Created by George Nachman on 3/9/16.
//
//

#import "iTermAltScreenMouseScrollInferer.h"

typedef NS_ENUM(NSInteger, iTermAltScreenMouseScrollInfererState) {
    iTermAltScreenMouseScrollInfererStateInitial,
    iTermAltScreenMouseScrollInfererStateScrolledUp,
    iTermAltScreenMouseScrollInfererStateScrolledDown,
    iTermAltScreenMouseScrollInfererStateFrustration
};
@implementation iTermAltScreenMouseScrollInferer {
    iTermAltScreenMouseScrollInfererState _state;
    BOOL _haveInferred;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _state = iTermAltScreenMouseScrollInfererStateInitial;
    }
    return self;
}

- (void)firstResponderDidChange {
    self.state = iTermAltScreenMouseScrollInfererStateInitial;
}

- (unichar)arrowKeyInEvent:(NSEvent *)theEvent {
    if ([theEvent modifierFlags] & NSNumericPadKeyMask) {
        NSString *theArrow = [theEvent charactersIgnoringModifiers];
        if ([theArrow length] == 1) {
            return [theArrow characterAtIndex:0];
        }
    }
    return 0;
}

- (void)keyDown:(NSEvent *)theEvent {
    switch (_state) {
        case iTermAltScreenMouseScrollInfererStateFrustration: {
            unichar arrowKey = [self arrowKeyInEvent:theEvent];
            if (arrowKey != NSDownArrowFunctionKey && arrowKey != NSUpArrowFunctionKey) {
                self.state = iTermAltScreenMouseScrollInfererStateInitial;
            }
            break;
        }

        case iTermAltScreenMouseScrollInfererStateInitial:
            break;
            
        case iTermAltScreenMouseScrollInfererStateScrolledDown: {
            unichar arrowKey = [self arrowKeyInEvent:theEvent];
            if (arrowKey == NSDownArrowFunctionKey || arrowKey == NSUpArrowFunctionKey) {
                // User may have scrolled down and then pressed down arrow, or scrolled up +
                // been annoyed + scrolled back down + pressed arrow key.
                self.state = iTermAltScreenMouseScrollInfererStateFrustration;
            } else {
                self.state = iTermAltScreenMouseScrollInfererStateInitial;
            }
            break;
        }
            
        case iTermAltScreenMouseScrollInfererStateScrolledUp:
            if ([self arrowKeyInEvent:theEvent] == NSUpArrowFunctionKey) {
                // User scrolled up + was frustrated + pressed up arrow key.
                self.state = iTermAltScreenMouseScrollInfererStateFrustration;
            } else {
                self.state = iTermAltScreenMouseScrollInfererStateInitial;
            }
            break;
    }
}

- (void)nonScrollWheelEvent:(NSEvent *)event {
    self.state = iTermAltScreenMouseScrollInfererStateInitial;
}

- (void)scrollWheel:(NSEvent *)event {
    if (_state != iTermAltScreenMouseScrollInfererStateFrustration) {
        if (event.scrollingDeltaY > 0) {
            self.state = iTermAltScreenMouseScrollInfererStateScrolledUp;
        } else if (event.scrollingDeltaY < 0) {
            self.state = iTermAltScreenMouseScrollInfererStateScrolledDown;
        } else if (event.scrollingDeltaX != 0) {
            self.state = iTermAltScreenMouseScrollInfererStateInitial;
        }
    }
}

- (void)setState:(iTermAltScreenMouseScrollInfererState)newState {
    if (newState == _state) {
        return;
    }
    if (_state == iTermAltScreenMouseScrollInfererStateFrustration) {
        // Exit frustration
        [_delegate altScreenMouseScrollInfererDidInferScrollingIntent:NO];
    }
    if (newState == iTermAltScreenMouseScrollInfererStateFrustration) {
        if (_haveInferred) {
            // Don't want to enter frustration state more than once because it'll cause extra
            // cancellations.
            return;
        }
        // Enter frustration
        _haveInferred = YES;
        [_delegate altScreenMouseScrollInfererDidInferScrollingIntent:YES];
    }
    _state = newState;
}

@end
