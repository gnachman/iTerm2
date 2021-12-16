#import <Cocoa/Cocoa.h>

/**
 * A view that draws a zoomed-in grid of pixels.
 */
@interface CPKEyedropperView : NSView

/** An array of arrays. The inner arrays have NSColor. This defines a grid to draw. */
@property(nonatomic) NSArray *colors;

/** The color space to return values in. */
@property(nonatomic, readonly) NSColorSpace *colorSpace;

/** Called on click. */
@property(nonatomic, copy) void (^click)(void);

/** Called when a key is pressed to cancel picking. */
@property(nonatomic, copy) void (^cancel)(void);

- (instancetype)initWithFrame:(NSRect)frame colorSpace:(NSColorSpace *)colorSpace NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frame NS_UNAVAILABLE;

@end
