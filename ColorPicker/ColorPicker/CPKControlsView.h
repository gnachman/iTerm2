#import <Cocoa/Cocoa.h>

/**
 * Draws a row of controls: add favorite, remove favorite, pick color, and swatch.
 */
@interface CPKControlsView : NSView

/** Should the "Remove Favorite" button be enabled? */
@property(nonatomic) BOOL removeEnabled;

/** Block called when user clicks on "Add Favorite". */
@property(nonatomic, copy) void (^addFavoriteBlock)();

/** Block called when user clicks on "Remove Favorite". */
@property(nonatomic, copy) void (^removeFavoriteBlock)();

/** Block called when user clicks on the eyedropper. */
@property(nonatomic, copy) void (^startPickingBlock)();

/** Reports this view's nominal height */
+ (CGFloat)desiredHeight;

/** Updates the swatch color. */
- (void)setSwatchColor:(NSColor *)color;

@end
