#import <Cocoa/Cocoa.h>

// User defaults key with BOOL value.
extern NSString *const kCPKUseSystemColorPicker;

/**
 * Draws a row of controls: add favorite, remove favorite, pick color, and swatch.
 */
@interface CPKControlsView : NSView

/** Should the "Remove Favorite" button be enabled? */
@property(nonatomic) BOOL removeEnabled;

/** Block called when you clicks on "No Color". */
@property(nonatomic, copy) void (^selectNoColorBlock)(void);

/** Block called when user clicks on "Add Favorite". */
@property(nonatomic, copy) void (^addFavoriteBlock)(void);

/** Block called when user clicks on "Remove Favorite". */
@property(nonatomic, copy) void (^removeFavoriteBlock)(void);

/** Block called when user clicks on the eyedropper. */
@property(nonatomic, copy) void (^startPickingBlock)(void);

/** Replace popover with native color picker. */
@property(nonatomic, copy) void (^useNativeColorPicker)(void);

/**
 * Use the system color picker? Setting this to YES opens the picker and adjusts the icon to
 * indicate it's active.
 */
@property(nonatomic) BOOL useSystemColorPicker;

/** Reports this view's nominal height */
+ (CGFloat)desiredHeight;

/**
 * Designated initializer.
 *
 * @param frameRect Initial frame
 * @param noColorAllowed If set, a control to set "no color" will be added.
 *
 * @return Initialized instance.
 */
- (instancetype)initWithFrame:(NSRect)frameRect noColorAllowed:(BOOL)noColorAllowed NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

/** Updates the swatch color. */
- (void)setSwatchColor:(NSColor *)color;

/** Call this when the color panel closes. */
- (void)colorPanelDidClose;

@end
