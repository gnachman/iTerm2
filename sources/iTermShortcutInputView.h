//
//  iTermShortcutInputView.h
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import <Cocoa/Cocoa.h>
#import "iTermShortcut.h"

@class iTermShortcutInputView;

@protocol iTermShortcutInputViewDelegate <NSObject>

- (void)shortcutInputView:(iTermShortcutInputView *)view didReceiveKeyPressEvent:(NSEvent *)event;

@end

// Use this class for text fields that take a shortcut as input. Any keydown
// event will be sent to -handleShortcutEvent: while this field's NSTextView is
// the first responder. Events are immediately passed to the shortcutDelegate.
// You can assign the shortcutDelegate in IB as it is an IBOutlet.
@interface iTermShortcutInputView : NSView

@property(nonatomic, weak) IBOutlet id<iTermShortcutInputViewDelegate> shortcutDelegate;
@property(nonatomic, assign) BOOL disableKeyRemapping;
@property(nonatomic, assign, getter=isEnabled) BOOL enabled;
@property(nonatomic, copy) NSString *stringValue;
@property(nonatomic, assign) NSBackgroundStyle backgroundStyle;
@property(nonatomic, retain) iTermShortcut *shortcut;
@property(nonatomic) BOOL leaderAllowed;
@property(nonatomic, copy) NSString *purpose;  // if you set this then the user will need to confirm likely-accidental keypresses. It should be a phrase like "as a hotkey".

- (void)handleShortcutEvent:(NSEvent *)event;

- (void)setShortcut:(iTermShortcut *)shortcut;

- (NSString *)identifierForCode:(NSUInteger)code
                      modifiers:(NSEventModifierFlags)modifiers
                      character:(NSUInteger)character;

// You can call this during shortcutInputView:didReceiveKeyPressEvent: if you don't want to accept it.
- (void)revert;

@end
