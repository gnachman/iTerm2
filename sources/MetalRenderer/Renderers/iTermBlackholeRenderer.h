#import "iTermMetalCellRenderer.h"
#import "iTermShaderTypes.h"

@interface iTermBlackholeRendererTransientState : iTermMetalRendererTransientState
@property(nonatomic) iTermBlackholeUniforms uniforms;
@property(nonatomic, strong) id<MTLTexture> sourceTexture;
@end

@interface iTermBlackholeRenderer : NSObject<iTermMetalRenderer>

- (instancetype)initWithDevice:(id<MTLDevice>)device;
- (void)drawWithFrameData:(iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalRendererTransientState *)transientState;

@end
