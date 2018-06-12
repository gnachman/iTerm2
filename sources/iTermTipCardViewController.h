//
//  iTermWelcomeCardViewController.h
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import <Cocoa/Cocoa.h>

@class iTermTipCardActionButton;

// A tip of the day card with a title, body text, and buttons.
@interface iTermTipCardViewController : NSViewController

// Buttons ordered from top to bottom.
@property(nonatomic, readonly) NSArray *actionButtons;

// Frame after animation completes. Updated on layout.
@property(nonatomic, readonly) NSRect postAnimationFrame;

// View that contains all subviews.
@property(nonatomic, readonly) NSView *containerView;

@property (nonatomic, readonly) iTermTipCardActionButton *currentlySelectedButton;

// Update the card title.
- (void)setTitleString:(NSString *)titleString;

// Update the background color of the card title.
- (void)setColor:(NSColor *)color;

// Update the card's body text.
- (void)setBodyText:(NSString *)bodyText;

// Re-layout the card.
- (void)layoutWithWidth:(CGFloat)width
                 origin:(NSPoint)newOrigin;

// Add an action button. |image| should be 22x22pt. |block| is called on click.
- (iTermTipCardActionButton *)addActionWithTitle:(NSString *)title
                                            icon:(NSImage *)image
                                           block:(void (^)(id card))block;

// The shortcut is merely an indicator. It's up to the caller to register a hotkey and handle it.
- (iTermTipCardActionButton *)addActionWithTitle:(NSString *)title
                                        shortcut:(NSString *)shortcut
                                            icon:(NSImage *)image
                                           block:(void (^)(id card))block;

// Returns the action button with |title| or nil.
- (iTermTipCardActionButton *)actionWithTitle:(NSString *)title;

// Remove the action button with |title| if one exists.
- (void)removeActionWithTitle:(NSString *)title;

// Returns the size that fits the passed-in size. Really only looks at the width.
- (NSSize)sizeThatFits:(NSSize)size;

// Creates Core Animation animations for a change of card height.
// |block| is responsible for animating the window or superview's frame and is called in the
// completion block.
- (void)animateCardWithDuration:(CGFloat)duration
                   heightChange:(CGFloat)heightChange
              originalCardFrame:(NSRect)originalCardFrame
             postAnimationFrame:(NSRect)postAnimationFrame
                 superviewWidth:(CGFloat)superviewWidth
                          block:(void (^)(void))block;

// Make two buttons share a row. Currently, this assumes a row has either 1 or
// 2 buttons, and both titles must be for existing buttons.
- (void)combineActionWithTitle:(NSString *)leftTitle andTitle:(NSString *)rightTitle;

@end
