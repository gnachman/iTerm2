//
//  iTermMouseReportingFrustrationDetector.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/19/20.
//

#import "iTermMouseReportingFrustrationDetector.h"

#import "DebugLogging.h"

typedef NS_ENUM(NSUInteger, iTermMouseReportingFrustrationDetectorState) {
    iTermMouseReportingFrustrationDetectorStateGround,
    iTermMouseReportingFrustrationDetectorStateMouseDown,
    iTermMouseReportingFrustrationDetectorStateMouseDownMultiple,
    iTermMouseReportingFrustrationDetectorStateMouseDragged,
    iTermMouseReportingFrustrationDetectorStatePrimed,
    iTermMouseReportingFrustrationDetectorStatePrimedMultiple  // mouse up following multi-click mouse down
};

@implementation iTermMouseReportingFrustrationDetector {
    iTermMouseReportingFrustrationDetectorState _state;
}

- (void)setState:(iTermMouseReportingFrustrationDetectorState)state {
    if (state == _state) {
        return;
    }
    DLog(@"Enter state %@", @(state));
    DLog(@"%@", [NSThread callStackSymbols]);
    _state = state;
}

- (void)mouseDown:(NSEvent *)event reported:(BOOL)reported {
    switch (_state) {
        case iTermMouseReportingFrustrationDetectorStateGround:
        case iTermMouseReportingFrustrationDetectorStateMouseDown:
        case iTermMouseReportingFrustrationDetectorStateMouseDownMultiple:
        case iTermMouseReportingFrustrationDetectorStatePrimedMultiple:
            if (event.clickCount > 0 && reported) {
                if (event.clickCount == 1) {
                    self.state = iTermMouseReportingFrustrationDetectorStateMouseDown;
                } else {
                    self.state = iTermMouseReportingFrustrationDetectorStateMouseDownMultiple;
                }
                return;
            }
            // Fall through
        case iTermMouseReportingFrustrationDetectorStateMouseDragged:
        case iTermMouseReportingFrustrationDetectorStatePrimed:
            self.state = iTermMouseReportingFrustrationDetectorStateGround;
            break;
    }
}

- (void)mouseDragged:(NSEvent *)event reported:(BOOL)reported {
    switch (_state) {
        case iTermMouseReportingFrustrationDetectorStateMouseDown:
        case iTermMouseReportingFrustrationDetectorStateMouseDownMultiple:
        case iTermMouseReportingFrustrationDetectorStateMouseDragged:
        case iTermMouseReportingFrustrationDetectorStatePrimedMultiple:
            if (reported) {
                self.state = iTermMouseReportingFrustrationDetectorStateMouseDragged;
                return;
            }
            // Fall through
        case iTermMouseReportingFrustrationDetectorStateGround:
        case iTermMouseReportingFrustrationDetectorStatePrimed:
            self.state = iTermMouseReportingFrustrationDetectorStateGround;
            break;
    }
}

- (void)mouseUp:(NSEvent *)event reported:(BOOL)reported {
    switch (_state) {
        case iTermMouseReportingFrustrationDetectorStateMouseDownMultiple:
        case iTermMouseReportingFrustrationDetectorStatePrimedMultiple:
            if (reported) {
                self.state = iTermMouseReportingFrustrationDetectorStatePrimedMultiple;
                return;
            }
            self.state = iTermMouseReportingFrustrationDetectorStateGround;
            return;

        case iTermMouseReportingFrustrationDetectorStateMouseDragged:
            if (event.clickCount == 0 && reported) {
                self.state = iTermMouseReportingFrustrationDetectorStatePrimed;
                return;
            }
            // Fall through
        case iTermMouseReportingFrustrationDetectorStateGround:
        case iTermMouseReportingFrustrationDetectorStatePrimed:
        case iTermMouseReportingFrustrationDetectorStateMouseDown:
            self.state = iTermMouseReportingFrustrationDetectorStateGround;
            break;
    }
}

- (void)keyDown:(NSEvent *)event {
    const NSEventModifierFlags mask = (NSEventModifierFlagCommand |
                                       NSEventModifierFlagShift |
                                       NSEventModifierFlagOption |
                                       NSEventModifierFlagControl);
    if ((event.modifierFlags & mask) == NSEventModifierFlagCommand &&
        [event.charactersIgnoringModifiers isEqualToString:@"c"]) {
        [self cmdC];
        return;
    }
    self.state = iTermMouseReportingFrustrationDetectorStateGround;
}

- (void)otherMouseEvent {
    self.state = iTermMouseReportingFrustrationDetectorStateGround;
}

- (void)cmdC {
    switch (_state) {
        case iTermMouseReportingFrustrationDetectorStatePrimed:
        case iTermMouseReportingFrustrationDetectorStatePrimedMultiple:
        case iTermMouseReportingFrustrationDetectorStateMouseDownMultiple:
        case iTermMouseReportingFrustrationDetectorStateMouseDragged:
            [self.delegate mouseReportingFrustrationDetectorDidDetectFrustration:self];
            self.state = iTermMouseReportingFrustrationDetectorStateGround;
            return;

        case iTermMouseReportingFrustrationDetectorStateGround:
        case iTermMouseReportingFrustrationDetectorStateMouseDown:
            self.state = iTermMouseReportingFrustrationDetectorStateGround;
            break;
    }
}

- (void)didCopyToPasteboardWithControlSequence {
    switch (_state) {
        case iTermMouseReportingFrustrationDetectorStatePrimed:
        case iTermMouseReportingFrustrationDetectorStatePrimedMultiple:
        case iTermMouseReportingFrustrationDetectorStateMouseDownMultiple:
        case iTermMouseReportingFrustrationDetectorStateMouseDragged:
            self.state = iTermMouseReportingFrustrationDetectorStateGround;
            return;

        case iTermMouseReportingFrustrationDetectorStateGround:
        case iTermMouseReportingFrustrationDetectorStateMouseDown:
            break;
    }
}

@end
