#import <Cocoa/Cocoa.h>

/**
 * A window that follows the mouse around showing a zoomed-in view of what is under the cursor.
 * When the user clicks, the color under the cursor is returned.
 */
@interface CPKEyedropperWindow : NSWindow

/**
 * Shows the window, waits for the user to click, and then returns the color under the cursor.
 *
 * @return The selected color, or nil if the pick is aborted (e.g., by another application becoming
 *   active).
 */
+ (void)pickColorWithCompletion:(void (^)(NSColor *color))completion;

@end
