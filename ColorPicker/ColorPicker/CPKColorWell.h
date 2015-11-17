#import <Cocoa/Cocoa.h>
#import "CPKSwatchView.h"

/**
 * Shows a color well. When clicked, it opens a popover with a color picker attached to it.
 * TODO(georgen): Use an NSCell subclass. Currently this control doesn't do a lot of what you'd
 * expect a control to do because it doesn't have a cell.
 */
@interface CPKColorWell : NSControl

@property(nonatomic, retain) NSColor *color;
@property(nonatomic, assign) BOOL alphaAllowed;
@property(nonatomic, assign) BOOL noColorAllowed;

// Called just before popover opens.
@property(nonatomic, copy) void (^willOpenPopover)();

// Called just before popover closes.
@property(nonatomic, copy) void (^willClosePopover)();

// Override these methods to customize how the popover is presented. Normally it is presented from
// the color well's frame.
- (NSRect)presentationRect;
- (NSView *)presentingView;

@end
