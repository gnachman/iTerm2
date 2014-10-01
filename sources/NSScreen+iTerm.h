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

// Returns the visible frame modified to not include the 4 pixel boundary given to a hidden dock.
// Kind of a gross hack since the magic 4 pixel number could change in the future.
- (NSRect)visibleFrameIgnoringHiddenDock;

@end
