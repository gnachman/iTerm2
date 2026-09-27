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

// What the recorded shortcut will be used for. Drives the confirmation shown for likely-accidental
// keypresses; a complete localized sentence is built per case rather than injecting a translated
// clause. iTermShortcutInputViewPurposeNone disables that confirmation.
typedef NS_ENUM(NSInteger, iTermShortcutInputViewPurpose) {
    iTermShortcutInputViewPurposeNone = 0,
    iTermShortcutInputViewPurposeHotkey,
    iTermShortcutInputViewPurposeLeader,
    iTermShortcutInputViewPurposeOpenQuicklyHotkey,
};

@protocol iTermShortcutInputViewDelegate <NSObject>

- (void)shortcutInputView:(iTermShortcutInputView *)view didReceiveKeyPressEvent:(NSEvent *)event;

@end

// Use this class for text fields that take a shortcut as input. Any keydown
// event will be sent to -handleShortcutEvent: while this field's NSTextView is
// the first responder. Events are immediately passed to the shortcutDelegate.
// You can assign the shortcutDelegate in IB as it is an IBOutlet.
//
// IMPORTANT: The window (or sheet) that hosts this view MUST be able to become
// the key window. Recording relies on -[iTermApplication routeEventToShortcutInputView:],
// which finds the field via the app's key window; if the field's window can't
// become key, keystrokes are never delivered here and recording silently does
// nothing. A common trap is an NSPanel declared as a "utility" window in a xib
// without the "titled" style bit: -canBecomeKeyWindow then returns NO, and when
// such a panel is presented as a sheet it never becomes key (the key window
// stays on some unrelated window, typically a terminal). Always give panels that
// contain this view the "titled" style mask (in addition to "utility"), or
// otherwise ensure -canBecomeKeyWindow returns YES.
@interface iTermShortcutInputView : NSView

@property(nonatomic, weak) IBOutlet id<iTermShortcutInputViewDelegate> shortcutDelegate;
@property(nonatomic, assign) BOOL disableKeyRemapping;
@property(nonatomic, assign, getter=isEnabled) BOOL enabled;
@property(nonatomic, copy) NSString *stringValue;
@property(nonatomic, assign) NSBackgroundStyle backgroundStyle;
@property(nonatomic, retain) iTermShortcut *shortcut;
@property(nonatomic) BOOL leaderAllowed;
// Set this to something other than None and the user will need to confirm likely-accidental keypresses.
@property(nonatomic) iTermShortcutInputViewPurpose purpose;

- (void)handleShortcutEvent:(NSEvent *)event;

- (void)setShortcut:(iTermShortcut *)shortcut;

- (NSString *)identifierForCode:(NSUInteger)code
                      modifiers:(NSEventModifierFlags)modifiers
                      character:(NSUInteger)character;

// You can call this during shortcutInputView:didReceiveKeyPressEvent: if you don't want to accept it.
- (void)revert;

@end
