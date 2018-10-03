#import <Cocoa/Cocoa.h>

typedef NS_OPTIONS(NSInteger, CPKMainViewControllerOptions) {
    CPKMainViewControllerOptionsAlpha = (1 << 0),  // Show opacity control
    CPKMainViewControllerOptionsNoColor = (1 << 1),  // Allow selection of "no color"
};

/**
 * The view controller for the color picker. This can go inside a popover, or something else if
 * you like.
 */
@interface CPKMainViewController : NSViewController

/** How large we want our view to be. */
@property(nonatomic, readonly) NSSize desiredSize;

/** The currently selected color. */
@property(nonatomic, readonly) NSColor *selectedColor;

/**
 * Initializes a main view controller.
 *
 * @param block The block to call when the user changes the color.
 * @param color The initial color.
 * @param alphaAllowed Can alpha be adjusted?
 *
 * @return An initialized instance.
 */
- (instancetype)initWithBlock:(void (^)(NSColor *))block
                        color:(NSColor *)color
                 alphaAllowed:(BOOL)alphaAllowed DEPRECATED_ATTRIBUTE;

- (instancetype)initWithBlock:(void (^)(NSColor *))block
         useSystemColorPicker:(void (^)(void))useSystemColorPickerBlock
                        color:(NSColor *)color
                      options:(CPKMainViewControllerOptions)options;


// Changes the selected color.
- (void)selectColor:(NSColor *)color;

@end
