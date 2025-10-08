#import <Cocoa/Cocoa.h>

@class CPKColor; 
@protocol CPKSelectionViewDelegate <NSObject>
- (void)selectionViewContentSizeDidChange;
@end

/**
 * A collection of views to facilitate selecting a color. Shows a 2-D gradient, a slider, a hex RGB
 * text field, and separate red, green, and blue text fields.
 */
@interface CPKSelectionView : NSView

/** Assign to this to programatically change the color. Will invoke the callback block. */
@property(nonatomic) CPKColor *selectedColor;
@property(nonatomic) NSColorSpace *colorSpace;

/** Called when the color space changes. */
@property(nonatomic, copy) void (^colorSpaceDidChangeBlock)(NSColorSpace *);

/**
 * Initializes a new selection view.
 *
 * @param frameRect The initial frame
 * @param block Invoked whenever self.selectedColor changes
 * @param color The initial selected color
 */
- (instancetype)initWithFrame:(NSRect)frameRect
                        block:(void (^)(CPKColor *))block
                        color:(CPKColor *)color
                   colorSpace:(NSColorSpace *)colorSpace
                 alphaAllowed:(BOOL)alphaAllowed;

@property(nonatomic, weak) id<CPKSelectionViewDelegate> delegate;

/** Adjusts the frame's size to fit its contents exactly. */
- (void)sizeToFit;

@end
