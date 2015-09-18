#import <Cocoa/Cocoa.h>
#import "CPKSwatchView.h"

/**
 * Shows a color well. When clicked, it opens a popover with a color picker attached to it.
 */
@interface CPKColorWell : CPKSwatchView

/** Block invoked when the user changes the color. */
@property(nonatomic, copy) void (^colorDidChange)(NSColor *);

/** User can adjust alpha value. */
@property(nonatomic, assign) BOOL alphaAllowed;

/** Color well is disabled? */
@property(nonatomic, assign) BOOL disabled;

@end
