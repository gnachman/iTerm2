//
//  NSEvent+iTerm.h
//  iTerm2
//
//  Created by George Nachman on 11/24/14.
//
//

#import <Cocoa/Cocoa.h>

@interface NSEvent (iTerm)

- (NSEvent *)mouseUpEventFromGesture;
- (NSEvent *)mouseDownEventFromGesture;

@end
