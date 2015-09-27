#import <Cocoa/Cocoa.h>

/** 
 * A view showing a 2-d gradient with saturation across the X axis and brightness across the Y
 * axis.
 */
@interface CPKHSBGradientView : NSView

/** Set this to move the selected color indicator. When the user drags it, this updates. */
@property(nonatomic) NSColor *selectedColor;

/** To change the hue without affecting saturation or brightness, assign to this. */
@property(nonatomic) CGFloat hue;

/**
 * Initializes a new gradient view with a callback.
 *
 * @param frameRect The initial frame
 * @param block The block to call when the user changes the color
 *
 * @return An initialized instance or nil.
 */
- (instancetype)initWithFrame:(NSRect)frameRect block:(void (^)(NSColor *))block;

@end
