//
//  NSView+iTerm.h
//  iTerm
//
//  Created by George Nachman on 3/15/14.
//
//

#import <Cocoa/Cocoa.h>
#import "NSObject+iTerm.h"

@protocol iTermViewScreenNotificationHandling<NSObject>
- (void)enclosingWindowDidMoveToScreen:(NSScreen *)screen;
@end

@interface NSView (iTerm)

+ (BOOL)iterm_takingSnapshot;
+ (NSView *)viewAtScreenCoordinate:(NSPoint)point;

// Returns an image representation of the view's current appearance.
- (NSImage *)snapshot;
// Rect is in the coordinate frame of self, so self.bounds would be the whole thing.
- (NSImage *)snapshotOfRect:(NSRect)rect;
- (void)insertSubview:(NSView *)subview atIndex:(NSInteger)index;
- (void)swapSubview:(NSView *)subview1 withSubview:(NSView *)subview2;

// Schedules a cancelable animation. It is only cancelable during |delay|.
// See NSObject+iTerm.h for how cancellation of delayed performs works. The
// completion block is always run; the finished argument is set to NO if it was
// canceled and the animations block was not run. Unlike iOS, there is no magic
// in the animations block; you're expected to do "view.animator.foo = whatever".
//
// Remember to retain self until completion finishes if your animations or completions block
// use self.
+ (iTermDelayedPerform *)animateWithDuration:(NSTimeInterval)duration
                                       delay:(NSTimeInterval)delay
                                  animations:(void (^)(void))animations
                                  completion:(void (^)(BOOL finished))completion;

// A non-cancelable version of animateWithDuration:delay:animations:completion:.
// Remember to retain self until completion runs if you use it.
+ (void)animateWithDuration:(NSTimeInterval)duration
                 animations:(void (NS_NOESCAPE ^)(void))animations
                 completion:(void (^)(BOOL finished))completion;

- (void)enumerateHierarchy:(void (NS_NOESCAPE ^)(NSView *))block;
- (CGFloat)retinaRound:(CGFloat)value;
- (CGFloat)retinaRoundUp:(CGFloat)value;
- (CGRect)retinaRoundRect:(CGRect)rect;
- (BOOL)containsDescendant:(NSView *)possibleDescendant;
- (NSColor *)it_backgroundColorOfEnclosingTerminalIfBackgroundColorViewHidden;

- (void)it_showWarning:(NSString *)text;
- (void)it_removeWarning;

// Accessibility APIs use y=0 at the top of the screen instead of the bottom. <3
- (NSPoint)viewPointFromAccessibilityScreenPoint:(NSPoint)screenPoint;

@end
