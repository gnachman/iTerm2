#import <Cocoa/Cocoa.h>
#import "CPKSliderView.h"

typedef NS_ENUM(NSInteger, CPKColorComponentSliderType) {
    kCPKColorComponentSliderTypeHue,
    kCPKColorComponentSliderTypeSaturation,
    kCPKColorComponentSliderTypeBrightness,
    kCPKColorComponentSliderTypeRed,
    kCPKColorComponentSliderTypeGreen,
    kCPKColorComponentSliderTypeBlue,
};

/**
 * A view that shows a rainbow of color component (hue, saturation, brightness, red, green, or blue)
 * values and allows the user to select one.
 */
@interface CPKColorComponentSliderView : CPKSliderView

/** The selected color. Setting this sets the selectedValue and updates the gradient. */
@property(nonatomic) NSColor *color;

/** The slider type. */
@property(nonatomic) CPKColorComponentSliderType type;

/**
 * Initializes a color component slider.
 *
 * @param frame The initial frame.
 * @param color The current color.
 * @param type The initial slider type.
 * @param block The block to invoke when the user drags the value indicator.
 *
 * @return An initialized instance.
 */
- (instancetype)initWithFrame:(NSRect)frame
                        color:(NSColor *)color
                         type:(CPKColorComponentSliderType)type
                        block:(void (^)(CGFloat))block;

/** Changes the colors in the slider's gradient but does not update the selection. */
- (void)setGradientColor:(NSColor *)color;

@end
