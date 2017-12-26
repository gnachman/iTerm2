#import <Foundation/Foundation.h>
#import "iTermMetalRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermBackgroundImageRendererTransientState : iTermMetalRendererTransientState
@property (nonatomic, readonly) MTLRenderPassDescriptor *intermediateRenderPassDescriptor;
@end

@interface iTermBackgroundImageRenderer : NSObject<iTermMetalRenderer>

@property (nonatomic, readonly) NSImage *image;

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Call this before creating transient state.
- (void)setImage:(NSImage *)image
           tiled:(BOOL)tiled
         context:(nullable iTermMetalBufferPoolContext *)context;

- (void)didFinishWithTransientState:(iTermBackgroundImageRendererTransientState *)tState;

@end

NS_ASSUME_NONNULL_END
