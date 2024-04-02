#import "iTermMetalCellRenderer.h"

#import "iTermTextRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermBackgroundColorRendererTransientState : iTermMetalCellRendererTransientState

// Alpha value gives the value from iTermAlphaValueForTopView.
@property (nonatomic) vector_float4 defaultBackgroundColor;

// Only draw default background color in this many bottom points. This includes the
// bottom margin. When nonzero this also draws the margin area there with
// default bg.
@property (nonatomic) CGFloat suppressedBottomHeight;

- (void)setColorRLEs:(const iTermMetalBackgroundColorRLE *)rles
               count:(size_t)count
                 row:(int)row
       repeatingRows:(int)repeatingRows;

@end

@interface iTermBackgroundColorRenderer : NSObject<iTermMetalCellRenderer>

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
