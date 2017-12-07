#import <Foundation/Foundation.h>
#import "iTermMetalRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermBackgroundImageRendererTransientState : iTermMetalRendererTransientState
@property (nonatomic, readonly) MTLRenderPassDescriptor *intermediateRenderPassDescriptor;
@end

@interface iTermBackgroundImageRenderer : NSObject<iTermMetalRenderer>

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Call this before creating transient state.
- (void)setImage:(NSImage *)image blending:(CGFloat)blending tiled:(BOOL)tiled;

- (void)didFinishWithTransientState:(iTermBackgroundImageRendererTransientState *)tState;

@end

NS_ASSUME_NONNULL_END
