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

// Returns a new event with the mouse button number set to `buttonNumber`, and
// other values the same as self.
- (NSEvent *)eventWithButtonNumber:(NSInteger)buttonNumber;

// Like NSEvent.modifierFlags but sets the numeric keypad bit correctly. This
// seems to have broken at some point. See issue 7780.
@property (nonatomic, readonly) NSEventModifierFlags it_modifierFlags;

@end
