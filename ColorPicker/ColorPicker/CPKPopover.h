#import <Cocoa/Cocoa.h>

/**
 * A popover that houses a color picker.
 */
@interface CPKPopover : NSPopover

/** Reflects the final selected color. */
@property(nonatomic, readonly) NSColor *selectedColor;

/**
 * Shows the color picker in a popover. Returns the semitransient popover.
 *
 * @param positioningRect The frame to position the popover on
 * @param positioningView The view whose coordinate system the |positioningRect| is in
 * @param color The starting color for the color picker
 * @param alphaAllowed User may adjust alpha value
 * @param block Invoked when the user changes the color
 *
 * @return A new popover that's being displayed.
 */
+ (instancetype)presentRelativeToRect:(NSRect)positioningRect
                               ofView:(NSView *)positioningView
                        preferredEdge:(NSRectEdge)preferredEdge
                         initialColor:(NSColor *)color
                         alphaAllowed:(BOOL)alphaAllowed
                selectionDidChange:(void (^)(NSColor *))block;

@end
