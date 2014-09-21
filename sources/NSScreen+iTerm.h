//
//  NSScreen+iTerm.h
//  iTerm
//
//  Created by George Nachman on 6/28/14.
//
//

#import <Cocoa/Cocoa.h>

@interface NSScreen (iTerm)

// Returns the screen that includes the mouse pointer.
+ (NSScreen *)screenWithCursor;

@end
