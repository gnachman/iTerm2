#import "iTermMetalCellRenderer.h"

#import "iTermTextRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermBackgroundColorRendererTransientState : iTermMetalCellRendererTransientState
@property (nonatomic, strong) id<MTLBuffer> colorsBuffer;  // iTermCellColors, to be populated by iTermColorComputer
@end

@interface iTermBackgroundColorRenderer : NSObject<iTermMetalCellRenderer>

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
