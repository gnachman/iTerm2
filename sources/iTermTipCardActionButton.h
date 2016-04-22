//
//  iTermWelcomeCardActionButton.h
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, iTermTipCardActionButtonAnimationState) {
    kTipCardButtonNotAnimating,  // Staying put
    kTipCardButtonAnimatingIn,  // Staged to become visible
    kTipCardButtonAnimatingOut,  // Staged to hide
    kTipCardButtonAnimatingOutCurrently  // Moving
};

// A button in the tip-of-the-day card.
@interface iTermTipCardActionButton : NSControl

// Block called on click.
@property(nonatomic, copy) void (^block)(id);

// Used by card to perform layout on buttons that are coming or going.
@property(nonatomic, assign) iTermTipCardActionButtonAnimationState animationState;

// What the frame will be when animation is done.
@property(nonatomic, assign) NSRect postAnimationFrame;

// Is this button hidden?
@property(nonatomic, assign, getter=isCollapsed) BOOL collapsed;

// Label
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *shortcut;

// 22x22pt icon
@property(nonatomic, retain) NSImage *icon;

// If many buttons share one row, this gives the button's index in the row.
@property(nonatomic, assign) int indexInRow;

// If many buttons share one row, this gives the number of buttons in the row.
@property(nonatomic, assign) int numberOfButtonsInRow;

// Important buttons get really loud colors.
@property(nonatomic, assign) BOOL important;

// Rotate icon 90 degrees? Animates on change.
- (void)setIconFlipped:(BOOL)isFlipped;

@end
