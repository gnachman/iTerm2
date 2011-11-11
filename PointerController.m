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

- (void)performAction:(NSString *)action
             forEvent:(NSEvent *)event
         withArgument:(NSString *)argument
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
    } else if ([action isEqualToString:kSendEscapeSequencePointerAction]) {
        [delegate_ sendEscapeSequence:argument withEvent:event];
    } else if ([action isEqualToString:kSendHexCodePointerAction]) {
        [delegate_ sendHexCode:argument withEvent:event];
    } else if ([action isEqualToString:kSendTextPointerAction]) {
        [delegate_ sendText:argument withEvent:event];
    } else if ([action isEqualToString:kSelectPaneLeftPointerAction]) {
        [delegate_ selectPaneLeftWithEvent:event];
    } else if ([action isEqualToString:kSelectPaneRightPointerAction]) {
        [delegate_ selectPaneRightWithEvent:event];
    } else if ([action isEqualToString:kSelectPaneAbovePointerAction]) {
        [delegate_ selectPaneAboveWithEvent:event];
    } else if ([action isEqualToString:kSelectPaneBelowPointerAction]) {
        [delegate_ selectPaneBelowWithEvent:event];
    } else if ([action isEqualToString:kNewWindowWithProfilePointerAction]) {
        [delegate_ newWindowWithProfile:argument withEvent:event];
    } else if ([action isEqualToString:kNewTabWithProfilePointerAction]) {
        [delegate_ newTabWithProfile:argument withEvent:event];
    } else if ([action isEqualToString:kNewVerticalSplitWithProfilePointerAction]) {
        [delegate_ newVerticalSplitWithProfile:argument withEvent:event];
    } else if ([action isEqualToString:kNewHorizontalSplitWithProfilePointerAction]) {
        [delegate_ newHorizontalSplitWithProfile:argument withEvent:event];
    } else if ([action isEqualToString:kSelectNextPanePointerAction]) {
        [delegate_ selectNextPaneWithEvent:event];
    } else if ([action isEqualToString:kSelectPreviousPanePointerAction]) {
        [delegate_ selectPreviousPaneWithEvent:event];
    }
}

- (void)mouseDown:(NSEvent *)event withTouches:(int)numTouches
{
    mouseDownButton_ = [event buttonNumber];
}

- (void)mouseUp:(NSEvent *)event withTouches:(int)numTouches
{
    NSString *action = nil;
    NSString *argument = nil;
    if (numTouches <= 2) {
        action = [PointerPrefsController actionWithButton:[event buttonNumber]
                                                numClicks:[event clickCount]
                                                modifiers:[event modifierFlags]];
        argument = [PointerPrefsController argumentWithButton:[event buttonNumber]
                                                    numClicks:[event clickCount]
                                                    modifiers:[event modifierFlags]];
    } else {
        action = [PointerPrefsController actionForTapWithTouches:numTouches
                                                       modifiers:[event modifierFlags]];
        argument = [PointerPrefsController argumentForTapWithTouches:numTouches
                                                           modifiers:[event modifierFlags]];
    }
    if (action) {
        [self performAction:action forEvent:event withArgument:argument];
    }
}

- (void)swipeWithEvent:(NSEvent *)event
{
    NSString *gesture = nil;
    if ([event deltaX] > 0) {
        gesture = kThreeFingerSwipeLeft;
    } else if ([event deltaX] < 0) {
        gesture = kThreeFingerSwipeRight;
    }
    if ([event deltaY] > 0) {
        gesture = kThreeFingerSwipeUp;
    } else if ([event deltaY] < 0) {
        gesture = kThreeFingerSwipeDown;
    }
    NSString *action = [PointerPrefsController actionForGesture:gesture
                                                      modifiers:[event modifierFlags]];
    NSString *argument = [PointerPrefsController argumentForGesture:gesture
                                                          modifiers:[event modifierFlags]];
    if (action) {
        [self performAction:action forEvent:event withArgument:argument];
    }
}

@end
