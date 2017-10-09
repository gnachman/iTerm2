#import "iTermMetalCellRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermBackgroundColorRendererTransientState : iTermMetalCellRendererTransientState

- (void)setColorData:(NSData *)colorData
                 row:(int)row
               width:(int)width;

@end

@interface iTermBackgroundColorRenderer : NSObject<iTermMetalCellRenderer>

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
