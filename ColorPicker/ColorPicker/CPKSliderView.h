#import <Cocoa/Cocoa.h>

/**
 * A view that shows a range of values and allows the user to select one.
 */
@interface CPKSliderView : NSView

/** The current value. Assign to this to move the slider. */
@property(nonatomic) CGFloat selectedValue;

/**
 * Initializes a slider.
 *
 * @param frame The initial frame.
 * @param value The initial value.
 * @param block The block to invoke when the user drags the indicator.
 *
 * @return An initialized instance.
 */
- (instancetype)initWithFrame:(NSRect)frame
                        value:(CGFloat)value
                        block:(void (^)(CGFloat))block;

- (NSBezierPath *)boundingPath;

@end
