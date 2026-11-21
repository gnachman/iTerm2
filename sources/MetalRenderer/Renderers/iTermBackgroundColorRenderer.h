#import "iTermMetalCellRenderer.h"

#import "iTermShaderTypes.h"
#import "iTermTextRenderer.h"

NS_ASSUME_NONNULL_BEGIN

// The height in pixels of the quad that fills the suppressed region at the
// bottom with the default background color. When the top margin is larger
// than the scaled suppressed height the difference is negative, and the
// result is 0: converting a negative value to NSUInteger is undefined (0 on
// arm64, near 2^64 on x86_64).
NS_INLINE NSUInteger iTermBackgroundColorRendererSuppressedBottomPixels(CGFloat suppressedBottomHeight,
                                                                        CGFloat scale,
                                                                        CGFloat topMargin) {
    const CGFloat pixels = suppressedBottomHeight * scale - topMargin;
    return pixels > 0 ? (NSUInteger)pixels : 0;
}

@interface iTermBackgroundColorRendererTransientState : iTermMetalCellRendererTransientState

// Alpha value gives the value from iTermAlphaValueForTopView.
@property (nonatomic) vector_float4 defaultBackgroundColor;

// Shifts draws up by this many pixels.
@property (nonatomic) float verticalOffset;

// omitClear: When true, don't draw runs with alpha=0. Those do get drawn
// otherwise because the specified color is combined with the default
// background color.
- (void)setColorRLEs:(const iTermMetalBackgroundColorRLE *)rles
               count:(size_t)count
                 row:(int)row
       repeatingRows:(int)repeatingRows
           omitClear:(BOOL)omitClear;

@end

@interface iTermBackgroundColorRenderer : NSObject<iTermMetalCellRenderer>

@property (nonatomic) iTermBackgroundColorRendererMode mode;

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface iTermOffscreenCommandLineBackgroundColorRenderer : iTermBackgroundColorRenderer
@end

NS_ASSUME_NONNULL_END
