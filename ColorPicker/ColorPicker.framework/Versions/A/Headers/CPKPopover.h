#import <Cocoa/Cocoa.h>
#import "CPKMainViewController.h"

/**
 * A popover that houses a color picker.
 * NOTE: Do not set the delegate of CPKPopover. It is its own delegate because
 * NSPopover uses an unsafe delegate pointer. This causes problems if the
 * delegate gets dealloced. Instead, use the willClose block.
 */
@interface CPKPopover : NSPopover

/** Reflects the final selected color. Setter changes color in open popover. */
@property(nonatomic, strong) NSColor *selectedColor;

/** Called before popover closes. */
@property(nonatomic, copy) void (^willClose)(void);

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
                selectionDidChange:(void (^)(NSColor *))block DEPRECATED_ATTRIBUTE;

+ (instancetype)presentRelativeToRect:(NSRect)positioningRect
                               ofView:(NSView *)positioningView
                        preferredEdge:(NSRectEdge)preferredEdge
                         initialColor:(NSColor *)color
                              options:(CPKMainViewControllerOptions)options
                   selectionDidChange:(void (^)(NSColor *))block
                 useSystemColorPicker:(void (^)(void))useSystemColorPicker;

@end
