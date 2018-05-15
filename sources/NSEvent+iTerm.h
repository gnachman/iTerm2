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

@end
