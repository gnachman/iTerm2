#import <Cocoa/Cocoa.h>
#import "CPKSliderView.h"

/**
 * A view that shows a rainbow of hue values and allows the user to select one.
 */
@interface CPKHueSliderView : CPKSliderView

/**
 * Initializes a hue slider.
 *
 * @param frame The initial frame.
 * @param hue The initial hue.
 * @param block The block to invoke when the user drags the hue indicator.
 *
 * @return An initialized instance.
 */
- (instancetype)initWithFrame:(NSRect)frame
                          hue:(CGFloat)hue
                        block:(void (^)(CGFloat))block;

@end
