//
//  PointerController.m
//  iTerm
//
//  Created by George Nachman on 11/7/11.
//  Copyright (c) 2011 George Nachman. All rights reserved.
//

#import "PointerController.h"
#import "iTermApplicationDelegate.h"
#import "PointerPrefsController.h"
#import "PreferencePanel.h"

@implementation PointerController {
    int mouseDownButton_;
    int clicks_;

    // If the mouse-down occurred while xterm mouse reporting was on, then when
    // the mouse-up is received, act as though the option key was not pressed.
    BOOL ignoreOption_;

    // Last-seen force touch stage.
    NSInteger _previousStage;
}

@synthesize delegate = delegate_;

- (void)performAction:(NSString *)action
             forEvent:(NSEvent *)event
         withArgument:(NSString *)argument
{
    DLog(@"Perform action %@", action);
    if ([action isEqualToString:kPasteFromClipboardPointerAction]) {
        [delegate_ pasteFromClipboardWithEvent:event];
    } else if ([action isEqualToString:kPasteFromSelectionPointerAction]) {
        [delegate_ pasteFromSelectionWithEvent:event];
    } else if ([action isEqualToString:kOpenTargetPointerAction]) {
        [delegate_ openTargetWithEvent:event];
    } else if ([action isEqualToString:kSmartSelectionPointerAction]) {
        [delegate_ smartSelectAndMaybeCopyWithEvent:event
                                   ignoringNewlines:NO];
    } else if ([action isEqualToString:kSmartSelectionIgnoringNewlinesPointerAction]) {
        [delegate_ smartSelectAndMaybeCopyWithEvent:event
                                   ignoringNewlines:YES];
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
    } else if ([action isEqualToString:kQuickLookAction]) {
        [delegate_ quickLookWithEvent:event];
    }
}

- (BOOL)viewShouldTrackTouches
{
    return [iTermPreferences boolForKey:kPreferenceKeyThreeFingerEmulatesMiddle] ||
           [PointerPrefsController haveThreeFingerTapEvents];
}

// Caller is responsible to check that it's a single click
- (BOOL)eventEmulatesRightClick:(NSEvent *)event
{
    return ![iTermPreferences boolForKey:kPreferenceKeyControlLeftClickBypassesContextMenu] &&
           [event buttonNumber] == 0 &&
           ([event modifierFlags] & (NSControlKeyMask | NSCommandKeyMask | NSAlternateKeyMask | NSShiftKeyMask)) == NSControlKeyMask;
}

- (NSString *)actionForEvent:(NSEvent *)event
                      clicks:(int)clicks
                 withTouches:(int)numTouches
{
    NSUInteger modifierFlags = [event modifierFlags];
    if (ignoreOption_) {
        modifierFlags &= ~NSAlternateKeyMask;
    }

    DLog(@"actionForEvent:%@ cicks:%d withTouches:%d", event, clicks, numTouches);
    if (clicks == 1 && [self eventEmulatesRightClick:event]) {
        // Ctrl-click emulates right button
        DLog(@"Look up action for an emulated right-click");
        return [PointerPrefsController actionWithButton:1 numClicks:1 modifiers:0];
    }
    if (numTouches <= 2) {
        DLog(@"Look up action for a two or one-finger touch click");
        return [PointerPrefsController actionWithButton:[event buttonNumber]
                                              numClicks:clicks
                                              modifiers:modifierFlags];
    } else {
        DLog(@"Look up action for a three-or-more finger tap");
        return [PointerPrefsController actionForTapWithTouches:numTouches
                                                     modifiers:modifierFlags];
    }
}

- (NSString *)argumentForEvent:(NSEvent *)event
                        clicks:(int)clicks
                   withTouches:(int)numTouches
{
    if (clicks == 1 && [self eventEmulatesRightClick:event]) {
        // Ctrl-click emulates right button
        return [PointerPrefsController argumentWithButton:1
                                                numClicks:1
                                                modifiers:0];
    }
    if (numTouches <= 2) {
        return [PointerPrefsController argumentWithButton:[event buttonNumber]
                                                numClicks:clicks
                                                modifiers:[event modifierFlags]];
    } else {
        return [PointerPrefsController argumentForTapWithTouches:numTouches
                                                       modifiers:[event modifierFlags]];
    }
}

- (void)notifyLeftMouseDown
{
    mouseDownButton_ = 0;
}

- (BOOL)mouseDown:(NSEvent *)event withTouches:(int)numTouches ignoreOption:(BOOL)ignoreOption {
    // A double left click plus an immediate right click reports a triple right
    // click! So we keep our own click count and use the lower of the OS's
    // value and ours. Theirs is lower when the time between clicks is long.
    if ([event buttonNumber] != mouseDownButton_) {
        clicks_ = 1;
    } else {
        clicks_++;
    }
    clicks_ = MIN(clicks_, [event clickCount]);
    ignoreOption_ = ignoreOption;
    mouseDownButton_ = [event buttonNumber];
    return [self actionForEvent:event
                         clicks:clicks_
                    withTouches:numTouches] != nil;
}

- (BOOL)mouseUp:(NSEvent *)event withTouches:(int)numTouches {
    _previousStage = 0;
    NSString *argument = [self argumentForEvent:event
                                         clicks:clicks_
                                    withTouches:numTouches];
    NSString *action = [self actionForEvent:event
                                     clicks:clicks_
                                withTouches:numTouches];
    DLog(@"mouseUp action=%@", action);
    if (action) {
        [self performAction:action forEvent:event withArgument:argument];
        return YES;
    } else {
        return NO;
    }
}

- (BOOL)pressureChangeWithEvent:(NSEvent *)event {
    if ([event respondsToSelector:@selector(stage)]) {
        NSInteger previousStage = _previousStage;
        _previousStage = event.stage;
        if (event.stage == 2 && previousStage < 2) {
            NSString *action = [PointerPrefsController actionForGesture:kForceTouchSingleClick
                                                              modifiers:[event modifierFlags]];
            NSString *argument = [PointerPrefsController argumentForGesture:kForceTouchSingleClick
                                                                  modifiers:[event modifierFlags]];
            if (action) {
                [self performAction:action forEvent:event withArgument:argument];
                return YES;
            } else {
                [self performAction:kQuickLookAction forEvent:event withArgument:nil];
            }
        }
    }
    return NO;
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
