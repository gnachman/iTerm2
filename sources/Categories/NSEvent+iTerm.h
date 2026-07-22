//
//  NSEvent+iTerm.h
//  iTerm2
//
//  Created by George Nachman on 11/24/14.
//
//

#import <Cocoa/Cocoa.h>

@interface NSEvent (iTerm)

@property(nonatomic, readonly) NSEvent *mouseUpEventFromGesture;
@property(nonatomic, readonly) NSEvent *mouseDownEventFromGesture;
@property(nonatomic, readonly) BOOL it_isNumericKeypadKey;
@property(nonatomic, readonly) BOOL it_isVerticalScroll;
@property(nonatomic) BOOL it_functionModifierPressed;
@property(nonatomic) BOOL it_functionModifierPreviouslyPressed;

+ (NSString *)stringForKeyWithKeycode:(CGKeyCode)virtualKeyCode
                            modifiers:(UInt32)carbonModifiers;

// Returns a new event with the mouse button number set to `buttonNumber`, and
// other values the same as self.
- (NSEvent *)eventWithButtonNumber:(NSInteger)buttonNumber;

// Like NSEvent.modifierFlags but sets the numeric keypad bit correctly. This
// seems to have broken at some point. See issue 7780.
@property (nonatomic, readonly) NSEventModifierFlags it_modifierFlags;

- (NSEvent *)eventByRoundingScrollWheelClicksAwayFromZero;
- (BOOL)it_eventGetsSpecialHandlingForAPINotifications;
+ (BOOL)it_keycodeShouldHaveNumericKeypadFlag:(unsigned short)keycode;

// Like -description but with typed characters removed. -[NSEvent description]
// for key events includes chars="…" and unmodchars="…", i.e. the literal
// keystrokes (which for a password prompt is the password). Use this instead of
// the event itself in any log that could reach the always-on retrospective ring
// (RLog). See DebugLogging.h. Keycode and modifier flags are retained because
// they carry the routing information logs actually need.
@property (nonatomic, readonly) NSString *it_redactedDescription;

@end

// Conform to this protocol to be notified that control-tab was key-down'ed when you are first responder.
// macOS doesn't route this to keyDown normally because it's used for accessibility, but most people
// have that feature turned off.
@protocol iTermSpecialHandlerForAPIKeyDownNotifications<NSObject>
- (void)handleSpecialKeyDown:(NSEvent *)event;
@end

