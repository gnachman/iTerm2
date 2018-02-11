#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, CPKGradientViewType) {
    kCPKGradientViewTypeSaturationBrightness,
    kCPKGradientViewTypeBrightnessHue,
    kCPKGradientViewTypeHueSaturation,
    kCPKGradientViewTypeRedGreen,
    kCPKGradientViewTypeGreenBlue,
    kCPKGradientViewTypeBlueRed,
};

/**
 * A view showing a 2-d gradient with saturation across the X axis and brightness across the Y
 * axis.
 */
@interface CPKGradientView : NSView

/** Set this to move the selected color indicator. When the user drags it, this updates. */
@property(nonatomic) NSColor *selectedColor;

/** To change the hue without affecting other components, assign to this. */
@property(nonatomic) CGFloat hue;

/** To change the saturation without affecting other components, assign to this. */
@property(nonatomic) CGFloat saturation;

/** To change the brightness without affecting other components, assign to this. */
@property(nonatomic) CGFloat brightness;

/** To change the red without affecting other components, assign to this. */
@property(nonatomic) CGFloat red;

/** To change the green without affecting other components, assign to this. */
@property(nonatomic) CGFloat green;

/** To change the blue without affecting other components, assign to this. */
@property(nonatomic) CGFloat blue;

/** Determines the type of gradient. */
@property(nonatomic) CPKGradientViewType type;

/**
 * Initializes a new gradient view with a callback.
 *
 * @param frameRect The initial frame
 * @param block The block to call when the user changes the color
 *
 * @return An initialized instance or nil.
 */
- (instancetype)initWithFrame:(NSRect)frameRect
                         type:(CPKGradientViewType)type
                        block:(void (^)(NSColor *))block;

@end
