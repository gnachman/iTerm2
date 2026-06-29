#import "iTermMetalCellRenderer.h"

#import "iTermShaderTypes.h"
#import "iTermTextRenderer.h"

NS_ASSUME_NONNULL_BEGIN

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
