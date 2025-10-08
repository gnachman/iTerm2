#import <Cocoa/Cocoa.h>

/**
 * A window that follows the mouse around showing a zoomed-in view of what is under the cursor.
 * When the user clicks, the color under the cursor is returned.
 */
@interface CPKEyedropperWindow : NSWindow

/**
 * Shows the window, waits for the user to click, and then returns the color under the cursor
 * in its native colorspace (mapped to one of the supported colorspaces: P3, sRGB, or Device).
 *
 * @param completion A block that receives the selected color and its colorspace, or nil/nil if
 *   the pick is aborted (e.g., by another application becoming active).
 */
+ (void)pickColorWithCompletion:(void (^)(NSColor *color, NSColorSpace *colorSpace))completion;

@end
