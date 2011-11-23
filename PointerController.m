//
//  PointerController.m
//  iTerm
//
//  Created by George Nachman on 11/7/11.
//  Copyright (c) 2011 George Nachman. All rights reserved.
//

#import "PointerController.h"
#import "PointerPrefsController.h"
#import "PreferencePanel.h"

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
    } else if ([action isEqualToString:kExtendSelectionPointerAction]) {
        [delegate_ extendSelectionWithEvent:event];
    }
}

- (BOOL)eventEmulatesRightClick:(NSEvent *)event
{
    return ![[PreferencePanel sharedInstance] passOnControlLeftClick] &&
           [event buttonNumber] == 0 &&
           [event clickCount] == 1 &&
           ([event modifierFlags] & (NSControlKeyMask | NSCommandKeyMask | NSAlternateKeyMask | NSShiftKeyMask)) == NSControlKeyMask;
}

- (NSString *)actionForEvent:(NSEvent *)event withTouches:(int)numTouches
{
    if ([self eventEmulatesRightClick:event]) {
        // Ctrl-click emulates right button
        return [PointerPrefsController actionWithButton:1 numClicks:1 modifiers:0];
    }
    if (numTouches <= 2) {
        return [PointerPrefsController actionWithButton:[event buttonNumber]
                                              numClicks:[event clickCount]
                                              modifiers:[event modifierFlags]];
    } else {
        return [PointerPrefsController actionForTapWithTouches:numTouches
                                                     modifiers:[event modifierFlags]];
    }
}

- (NSString *)argumentForEvent:(NSEvent *)event withTouches:(int)numTouches
{
    if ([self eventEmulatesRightClick:event]) {
        // Ctrl-click emulates right button
        return [PointerPrefsController argumentWithButton:1
                                                numClicks:1
                                                modifiers:0];
    }
    if (numTouches <= 2) {
        return [PointerPrefsController argumentWithButton:[event buttonNumber]
                                                numClicks:[event clickCount]
                                                modifiers:[event modifierFlags]];
    } else {
        return [PointerPrefsController argumentForTapWithTouches:numTouches
                                                       modifiers:[event modifierFlags]];
    }
}

- (BOOL)mouseDown:(NSEvent *)event withTouches:(int)numTouches
{
    mouseDownButton_ = [event buttonNumber];
    return [self actionForEvent:event withTouches:numTouches] != nil;
}

- (BOOL)mouseUp:(NSEvent *)event withTouches:(int)numTouches
{
    NSString *argument = [self argumentForEvent:event withTouches:numTouches];
    NSString *action = [self actionForEvent:event withTouches:numTouches];
    if (action) {
        [self performAction:action forEvent:event withArgument:argument];
        return YES;
    } else {
        return NO;
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
