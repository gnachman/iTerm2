#import <Foundation/Foundation.h>

#import "iTermMetalCellRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermHighlightRowRendererTransientState : iTermMetalCellRendererTransientState
- (void)setOpacity:(CGFloat)opacity
             color:(vector_float3)color
               row:(int)row;
@end

@interface iTermHighlightRowRenderer : NSObject<iTermMetalCellRenderer>
- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
