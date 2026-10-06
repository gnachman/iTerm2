//
//  iTermFlexibleView.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/2/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// Every tab's view: it holds the tab's root split view, and later its floating panes.
//
// In a native tab the root fills the container. In a tmux tab the root can be smaller than the
// container, which fills the space around it with `color`. A nil color draws nothing.
@interface iTermFlexibleView : NSView
@property(nonatomic, retain, nullable) NSColor *color;

// The tab's root split view. Only its frame is left unpainted.
@property(nonatomic, weak, nullable) NSView *rootView;

// When YES, the root is laid out to fill the bounds whenever the container resizes.
@property(nonatomic) BOOL rootFillsBounds;

// Called after the container's size changes, with the old size.
@property(nonatomic, copy, nullable) void (^sizeDidChange)(NSSize oldSize);

- (instancetype)initWithFrame:(NSRect)frame color:(nullable NSColor*)color;
- (void)setFlipped:(BOOL)value;

// With rootFillsBounds, makes the root's frame equal the bounds.
- (void)layoutRootIfNeeded;

@end

NS_ASSUME_NONNULL_END
