//
//  NSView+iTerm.h
//  iTerm
//
//  Created by George Nachman on 3/15/14.
//
//

#import <Cocoa/Cocoa.h>

@interface NSView (iTerm)

// Returns an image representation of the view's current appearance.
- (NSImage *)snapshot;
- (void)insertSubview:(NSView *)subview atIndex:(NSInteger)index;
- (void)swapSubview:(NSView *)subview1 withSubview:(NSView *)subview2;

@end
