#import <Cocoa/Cocoa.h>

@interface CPKSwatchView : NSView

/** The color to display. When the color is changed by the color picker this value gets updated. */
@property(nonatomic, retain) NSColor *color;

/** Defaults to 3 */
@property(nonatomic) NSInteger cornerRadius;

/** Defaults to gray */
@property(nonatomic, retain) NSColor *borderColor;

@end
