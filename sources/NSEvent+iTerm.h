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

@end
