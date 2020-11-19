#import "iTermMetalCellRenderer.h"

#import "iTermTextRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermBackgroundColorRendererTransientState : iTermMetalCellRendererTransientState

// Alpha value gives the value from iTermAlphaValueForTopView.
@property (nonatomic) vector_float4 defaultBackgroundColor;

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
