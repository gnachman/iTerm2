//
//  iTermInputHandler.h
//  iTerm2
//
//  Created by George Nachman on 7/11/15.
//
//

#import <Cocoa/Cocoa.h>

@class VT100Output;

@protocol iTermInputHandlerDelegate<NSObject>

// Was there marked text (i.e., is the input method editor in use?)
- (BOOL)inputHandlerHasMarkedText;

// Is key repeat allowed? It can be turned off by an escape sequence (DECRESET 8)
- (BOOL)inputHandlerShouldAutoRepeat;

// Is the session dead? No sense writing to it, etc.
- (BOOL)inputHandlerSessionHasExited;

// Pass an array of NSEvent*s to interpretKeyEvents.
- (void)inputHandlerInterpretEvents:(NSArray *)array;

// Write to the master side of the PTY.
- (void)inputHandlerWriteData:(NSData *)data;

// Run a bound action.
- (BOOL)inputHandlerExecuteBoundActionForEvent:(NSEvent *)event;

// Returns the output generator for this session.
- (VT100Output *)inputHandlerOutputGenerator;

// Returns the encoding used by this session.
- (NSStringEncoding)inputHandlerEncoding;

// Indicates if a keymapping exists for this event.
- (BOOL)inputHandlerHasActionableKeyMappingForEvent:(NSEvent *)event;

// Returns OPT_NORMAL, OPT_META, or OPT_ESC.
- (int)inputHandlerLeftOptionKeyBehavior;
- (int)inputHandlerRightOptionKeyBehavior;

// Indicates if a call to inputHandlerInterpretEvents resulted in
// -insertText:replacementRange: getting called, implying that the input method
// editor used the input.
- (BOOL)inputHandlerDidInsertText;

@end

// This helper contains the key-handling logic for PTYSession.
@interface iTermInputHandler : NSObject

@property(nonatomic, assign) id<iTermInputHandlerDelegate> delegate;

// Was the last pressed key a "repeat" where the key is held down?
@property(nonatomic, readonly) BOOL lastKeyPressWasRepeating;

// Process the event.
- (void)handleKeyDownEvent:(NSEvent *)event;

@end
