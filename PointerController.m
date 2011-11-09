//
//  PointerController.m
//  iTerm
//
//  Created by George Nachman on 11/7/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "PointerController.h"
#import "PointerPrefsController.h"

@implementation PointerController

@synthesize delegate = delegate_;

- (void)performAction:(NSString *)action forEvent:(NSEvent *)event
{
    if ([action isEqualToString:kPasteFromClipboardPointerAction]) {
        [delegate_ pasteFromClipboardWithEvent:event];
    } else if ([action isEqualToString:kPasteFromSelectionPointerAction]) {
        [delegate_ pasteFromSelectionWithEvent:event];
    } else if ([action isEqualToString:kOpenTargetPointerAction]) {
        [delegate_ openTargetWithEvent:event];
    } else if ([action isEqualToString:kSmartSelectionPointerAction]) {
        [delegate_ smartSelectWithEvent:event];
    } else if ([action isEqualToString:kContextMenuPointerAction]) {
        [delegate_ openContextMenuWithEvent:event];
    } else if ([action isEqualToString:kNextTabPointerAction]) {
        [delegate_ nextTabWithEvent:event];
    } else if ([action isEqualToString:kPrevTabPointerAction]) {
        [delegate_ previousTabWithEvent:event];
    } else if ([action isEqualToString:kNextWindowPointerAction]) {
        [delegate_ nextWindowWithEvent:event];
    } else if ([action isEqualToString:kPrevWindowPointerAction]) {
        [delegate_ previousWindowWithEvent:event];
    } else if ([action isEqualToString:kMovePanePointerAction]) {
        [delegate_ movePaneWithEvent:event];
    }
}

- (void)mouseDown:(NSEvent *)event withTouches:(int)numTouches
{
    mouseDownButton_ = [event buttonNumber];
}

- (void)mouseUp:(NSEvent *)event withTouches:(int)numTouches
{
    NSString *action = nil;
    if (numTouches <= 2) {
        action = [PointerPrefsController actionWithButton:[event buttonNumber]
                                                numClicks:[event clickCount]
                                                modifiers:[event modifierFlags]];
    } else {
        action = [PointerPrefsController actionForTapWithTouches:numTouches
                                                       modifiers:[event modifierFlags]];
    }
    if (action) {
        [self performAction:action forEvent:event];
    }
}

- (void)swipeWithEvent:(NSEvent *)event
{
    NSString *gesture = nil;
    if ([event deltaX] < 0) {
        gesture = kThreeFingerSwipeLeft;
    } else if ([event deltaX] > 0) {
        gesture = kThreeFingerSwipeRight;
    }
    if ([event deltaY] < 0) {
        gesture = kThreeFingerSwipeUp;
    } else if ([event deltaY] > 0) {
        gesture = kThreeFingerSwipeDown;
    }
    NSString *action = [PointerPrefsController actionForGesture:gesture
                                                      modifiers:[event modifierFlags]];
    if (action) {
        [self performAction:action forEvent:event];
    }
}

@end
