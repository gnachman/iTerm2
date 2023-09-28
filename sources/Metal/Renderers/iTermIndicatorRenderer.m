//
//  iTermIndicatorRenderer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/30/17.
//

#import "iTermIndicatorRenderer.h"

#import "NSArray+iTerm.h"
#import "NSImage+iTerm.h"
#import "iTermSharedImageStore.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermIndicatorDescriptor()
@property (nonatomic, strong) id<MTLTexture> texture;
@end

@implementation iTermIndicatorDescriptor
@end

@interface iTermIndicatorRendererTransientState()
@property (nonatomic, strong) NSArray<iTermIndicatorDescriptor *> *indicatorDescriptors;
@end

@implementation iTermIndicatorRendererTransientState

- (void)writeDebugInfoToFolder:(NSURL *)folder {
    [super writeDebugInfoToFolder:folder];

    NSString *descriptors = [[_indicatorDescriptors mapWithBlock:^id(iTermIndicatorDescriptor *descriptor) {
        return descriptor.texture.label;
    }] componentsJoinedByString:@", "];
    [[NSString stringWithFormat:@"descriptors=%@", descriptors] writeToURL:[folder URLByAppendingPathComponent:@"state.txt"]
                                                                atomically:NO
                                                                  encoding:NSUTF8StringEncoding
                                                                     error:NULL];
}

@end

@implementation iTermIndicatorRenderer {
    iTermMetalRenderer *_metalRenderer;
    NSMutableArray<iTermIndicatorDescriptor *> *_indicatorDescriptors;
    NSMutableDictionary<NSString *, id<MTLTexture>> *_identifierToTextureMap;
    iTermMetalBufferPool *_alphaBufferPool;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _metalRenderer = [[iTermMetalRenderer alloc] initWithDevice:device
                                                 vertexFunctionName:@"iTermIndicatorVertexShader"
                                               fragmentFunctionName:@"iTermIndicatorFragmentShader"
                                                           blending:[iTermMetalBlending premultipliedCompositing]
                                                transientStateClass:[iTermIndicatorRendererTransientState class]];
        _indicatorDescriptors = [NSMutableArray array];
        _identifierToTextureMap = [NSMutableDictionary dictionary];
        _alphaBufferPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(float)];
    }
    return self;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (nullable __kindof iTermMetalRendererTransientState *)createTransientStateForConfiguration:(iTermRenderConfiguration *)configuration
                                                                               commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    __kindof iTermMetalRendererTransientState * _Nonnull transientState =
        [_metalRenderer createTransientStateForConfiguration:configuration
                                               commandBuffer:commandBuffer];
    [self initializeTransientState:transientState];
    return transientState;
}

- (void)initializeTransientState:(iTermIndicatorRendererTransientState *)tState {
    tState.indicatorDescriptors = [_indicatorDescriptors copy];
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateIndicatorsTS;
}

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalRendererTransientState *)transientState {
    iTermIndicatorRendererTransientState *tState = transientState;
    [tState.indicatorDescriptors enumerateObjectsUsingBlock:^(iTermIndicatorDescriptor * _Nonnull descriptor, NSUInteger idx, BOOL * _Nonnull stop) {
        [self drawDescriptor:descriptor
           withRenderEncoder:frameData.renderEncoder
              transientState:tState];
    }];
}

- (void)drawDescriptor:(iTermIndicatorDescriptor *)descriptor
     withRenderEncoder:(nonnull id<MTLRenderCommandEncoder>)renderEncoder
        transientState:(__kindof iTermMetalRendererTransientState *)tState {
    id<MTLBuffer> vertexBuffer = [self vertexBufferForFrame:descriptor.frame
                                                      scale:tState.configuration.scale
                                               viewportSize:tState.configuration.viewportSize
                                                   topInset:tState.configuration.extraMargins.top
                                                    context:tState.poolContext];

    float alpha = descriptor.alpha;
    id<MTLBuffer> alphaBuffer = [_alphaBufferPool requestBufferFromContext:tState.poolContext
                                                                 withBytes:&alpha
                                                            checkIfChanged:YES];

    [_metalRenderer drawWithTransientState:tState
                             renderEncoder:renderEncoder
                          numberOfVertices:6
                              numberOfPIUs:0
                             vertexBuffers:@{ @(iTermVertexInputIndexVertices): vertexBuffer }
                           fragmentBuffers:@{ @(iTermFragmentBufferIndexIndicatorAlpha): alphaBuffer }
                                  textures:@{ @(iTermTextureIndexPrimary): descriptor.texture }];
}

- (id<MTLBuffer>)vertexBufferForFrame:(NSRect)frame
                                scale:(CGFloat)scale
                         viewportSize:(vector_uint2)viewportSize
                             topInset:(CGFloat)topInset
                              context:(iTermMetalBufferPoolContext *)context {
    CGRect textureFrame = CGRectMake(0, 0, 1, 1);
    // Note this is *not* flipped, yet. y=0 is the top (visually).
    CGRect quad = CGRectMake(CGRectGetMinX(frame) * scale,
                             topInset + scale * CGRectGetMinY(frame),
                             CGRectGetWidth(frame) * scale,
                             CGRectGetHeight(frame) * scale);
    quad.origin.y = viewportSize.y - quad.origin.y - quad.size.height;
    const iTermVertex vertices[] = {
        // Pixel Positions             Texture Coordinates
        { { CGRectGetMaxX(quad), CGRectGetMinY(quad) }, { CGRectGetMaxX(textureFrame), CGRectGetMinY(textureFrame) } },
        { { CGRectGetMinX(quad), CGRectGetMinY(quad) }, { CGRectGetMinX(textureFrame), CGRectGetMinY(textureFrame) } },
        { { CGRectGetMinX(quad), CGRectGetMaxY(quad) }, { CGRectGetMinX(textureFrame), CGRectGetMaxY(textureFrame) } },

        { { CGRectGetMaxX(quad), CGRectGetMinY(quad) }, { CGRectGetMaxX(textureFrame), CGRectGetMinY(textureFrame) } },
        { { CGRectGetMinX(quad), CGRectGetMaxY(quad) }, { CGRectGetMinX(textureFrame), CGRectGetMaxY(textureFrame) } },
        { { CGRectGetMaxX(quad), CGRectGetMaxY(quad) }, { CGRectGetMaxX(textureFrame), CGRectGetMaxY(textureFrame) } },
    };
    return [_metalRenderer.verticesPool requestBufferFromContext:context
                                                       withBytes:vertices
                                                  checkIfChanged:YES];
}

- (void)reset {
    [_indicatorDescriptors removeAllObjects];
}

- (void)addIndicator:(iTermIndicatorDescriptor *)indicator
          colorSpace:(NSColorSpace *)colorSpace
             context:(iTermMetalBufferPoolContext *)context {
    indicator.texture = [self textureForIdentifier:indicator.identifier
                                             image:indicator.image
                                           context:context
                                        colorSpace:colorSpace];
    [_indicatorDescriptors addObject:indicator];
    indicator.texture.label = indicator.identifier;
}

- (id<MTLTexture>)textureForIdentifier:(NSString *)identifier
                                 image:(NSImage *)image
                               context:(iTermMetalBufferPoolContext *)context
                            colorSpace:(NSColorSpace *)colorSpace {
    NSString *key = [NSString stringWithFormat:@"%@:%@", identifier, colorSpace.localizedName];
    id<MTLTexture> texture = _identifierToTextureMap[key];
    if (!texture) {
        texture = [_metalRenderer textureFromImage:[iTermImageWrapper withImage:image.it_verticallyFlippedImage]
                                           context:context
                                        colorSpace:colorSpace];
        _identifierToTextureMap[key] = texture;
    }
    return texture;
}

@end

NS_ASSUME_NONNULL_END
