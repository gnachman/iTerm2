#import "iTermBackgroundImageRenderer.h"

#import "iTermShaderTypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermTexturePool : NSObject
- (nullable id<MTLTexture>)requestTextureOfSize:(vector_uint2)size;
- (void)returnTexture:(id<MTLTexture>)texture;
@end

@implementation iTermTexturePool {
    NSMutableArray<id<MTLTexture>> *_textures;
    vector_uint2 _size;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _textures = [NSMutableArray array];
    }
    return self;
}

- (nullable id<MTLTexture>)requestTextureOfSize:(vector_uint2)size {
    _size = size;
    [_textures removeObjectsAtIndexes:[_textures indexesOfObjectsPassingTest:^BOOL(id<MTLTexture>  _Nonnull texture, NSUInteger idx, BOOL * _Nonnull stop) {
        return (texture.width != _size.x || texture.height != _size.y);
    }]];
    if (_textures.count) {
        id<MTLTexture> result = _textures.firstObject;
        [_textures removeObjectAtIndex:0];
        return result;
    } else {
        return nil;
    }
}

- (void)returnTexture:(id<MTLTexture>)texture {
    if (texture.width == _size.x && texture.height == _size.y) {
        [_textures addObject:texture];
    }
}

@end

@interface iTermBackgroundImageRendererTransientState ()
@property (nonatomic, strong) id<MTLTexture> texture;
@property (nonatomic) BOOL tiled;
@property (nonatomic) MTLRenderPassDescriptor *intermediateRenderPassDescriptor;
@end

@implementation iTermBackgroundImageRendererTransientState

- (BOOL)skipRenderer {
    return _texture == nil;
}

@end

@implementation iTermBackgroundImageRenderer {
    iTermMetalRenderer *_metalRenderer;

    BOOL _tiled;
    NSImage *_image;
    iTermTexturePool *_texturePool;
    id<MTLTexture> _texture;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _texturePool = [[iTermTexturePool alloc] init];
        _metalRenderer = [[iTermMetalRenderer alloc] initWithDevice:device
                                                 vertexFunctionName:@"iTermBackgroundImageVertexShader"
                                               fragmentFunctionName:@"iTermBackgroundImageFragmentShader"
                                                           blending:NO
                                                transientStateClass:[iTermBackgroundImageRendererTransientState class]];
    }
    return self;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateBackgroundImageTS;
}

- (void)setImage:(NSImage *)image tiled:(BOOL)tiled context:(nullable iTermMetalBufferPoolContext *)context {
    if (image != _image) {
        _texture = image ? [_metalRenderer textureFromImage:image context:context] : nil;
    }
    _image = image;
    _tiled = tiled;
}

- (void)drawWithRenderEncoder:(nonnull id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(nonnull __kindof iTermMetalRendererTransientState *)transientState {
    iTermBackgroundImageRendererTransientState *tState = transientState;
    [_metalRenderer drawWithTransientState:tState
                             renderEncoder:renderEncoder
                          numberOfVertices:6
                              numberOfPIUs:0
                             vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer }
                           fragmentBuffers:@{}
                                  textures:@{ @(iTermTextureIndexPrimary): tState.texture }];
}

- (__kindof iTermMetalRendererTransientState * _Nonnull)createTransientStateForConfiguration:(iTermRenderConfiguration *)configuration
                               commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    if (_image == nil) {
        return nil;
    }
    iTermBackgroundImageRendererTransientState * _Nonnull tState =
        [_metalRenderer createTransientStateForConfiguration:configuration
                                               commandBuffer:commandBuffer];

    [self initializeTransientState:tState];

    return tState;
}

- (void)didFinishWithTransientState:(iTermBackgroundImageRendererTransientState *)tState {
    [_texturePool returnTexture:tState.intermediateRenderPassDescriptor.colorAttachments[0].texture];
}

- (void)initializeColorAttachmentOfSize:(vector_uint2)size inRenderPassDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor {
    MTLRenderPassColorAttachmentDescriptor *colorAttachment = renderPassDescriptor.colorAttachments[0];
    colorAttachment.storeAction = MTLStoreActionStore;
    colorAttachment.texture = [_texturePool requestTextureOfSize:size];
    if (!colorAttachment.texture) {
        // Allocate a new texture.
        MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                                     width:size.x
                                                                                                    height:size.y
                                                                                                 mipmapped:NO];
        textureDescriptor.usage = (MTLTextureUsageShaderRead |
                                   MTLTextureUsageShaderWrite |
                                   MTLTextureUsageRenderTarget |
                                   MTLTextureUsagePixelFormatView);
        colorAttachment.texture = [_metalRenderer.device newTextureWithDescriptor:textureDescriptor];
        colorAttachment.texture.label = @"Intermediate Texture";
    }
}

- (void)initializeTransientState:(iTermBackgroundImageRendererTransientState *)tState {
    tState.texture = _texture;
    tState.tiled = _tiled;

//    NSImageRep *rep = _image.representations.firstObject;
//    const CGSize nativeTextureSize = NSMakeSize(rep.pixelsWide, rep.pixelsHigh);
    const CGSize nativeTextureSize = NSMakeSize(_image.size.width * tState.configuration.scale,
                                                _image.size.height * tState.configuration.scale);
    const CGSize size = CGSizeMake(tState.configuration.viewportSize.x,
                                   tState.configuration.viewportSize.y);
    CGSize textureSize;
    if (_tiled) {
        textureSize = CGSizeMake(size.width / nativeTextureSize.width,
                                 size.height / nativeTextureSize.height);
    } else {
        textureSize = CGSizeMake(1, 1);
    }
    const iTermVertex vertices[] = {
        // Pixel Positions             Texture Coordinates
        { { size.width,           0 }, { textureSize.width,                  0 } },
        { {          0,           0 }, {                 0,                  0 } },
        { {          0, size.height }, {                 0, textureSize.height } },

        { { size.width,           0 }, { textureSize.width,                  0 } },
        { {          0, size.height }, {                 0, textureSize.height } },
        { { size.width, size.height }, { textureSize.width, textureSize.height } },
    };
    tState.vertexBuffer = [_metalRenderer.verticesPool requestBufferFromContext:tState.poolContext
                                                                      withBytes:vertices
                                                                 checkIfChanged:YES];

    tState.texture = _texture;

    if (!tState.skipRenderer) {
        tState.intermediateRenderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
        [self initializeColorAttachmentOfSize:tState.configuration.viewportSize
                       inRenderPassDescriptor:tState.intermediateRenderPassDescriptor];
    }
}

@end

NS_ASSUME_NONNULL_END
