#import "iTermTextRenderer.h"

extern "C" {
#import "DebugLogging.h"
}

#import "iTermMetalCellRenderer.h"
#import "iTermSubpixelModelBuilder.h"
#import "iTermTextureArray.h"
#import "iTermTextureMap.h"
#import "NSDictionary+iTerm.h"
#import <unordered_map>

@interface iTermTextRendererTransientState ()

@property (nonatomic, readonly) NSIndexSet *indexes;
@property (nonatomic, weak) iTermTextureMap *textureMap;
- (void)addIndex:(NSInteger)index;

@end

@implementation iTermTextRendererTransientState {
    iTermTextureMapStage *_stage;
    NSMutableIndexSet *_indexes;
    dispatch_group_t _group;
    id<MTLCommandBuffer> _commandBuffer;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _indexes = [NSMutableIndexSet indexSet];
        _group = dispatch_group_create();
    }
    return self;
}

- (void)willDraw {
    [_stage blitNewTexturesFromStagingAreaWithCommandBuffer:_commandBuffer];
}

- (void)prepareForDrawWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                             completion:(void (^)(void))completion {
    _commandBuffer = commandBuffer;
    [_textureMap requestStage:^(iTermTextureMapStage *stage) {
        _stage = stage;
        completion();
    }];
}

- (NSUInteger)sizeOfNewPIUBuffer {
    return sizeof(iTermTextPIU) * self.cellConfiguration.gridSize.width * self.cellConfiguration.gridSize.height;
}


- (void)setGlyphKeysData:(NSData *)glyphKeysData
          attributesData:(NSData *)attributesData
                     row:(int)row
                creation:(NSImage *(NS_NOESCAPE ^)(int x))creation {
    const int width = self.cellConfiguration.gridSize.width;
    const iTermMetalGlyphKey *glyphKeys = (iTermMetalGlyphKey *)glyphKeysData.bytes;
    const iTermMetalGlyphAttributes *attributes = (iTermMetalGlyphAttributes *)attributesData.bytes;
    const float w = 1.0 / _textureMap.array.atlasSize.width;
    const float h = 1.0 / _textureMap.array.atlasSize.height;
    iTermTextureArray *array = _textureMap.array;
    iTermTextPIU *pius = (iTermTextPIU *)self.pius.contents;

    NSInteger lastIndex = 0;
    for (int x = 0; x < width; x++) {
        NSInteger index;
        if (x > 0 && !memcmp(&glyphKeys[x], &glyphKeys[x-1], sizeof(*glyphKeys))) {
            index = lastIndex;
        } else {
            index = [_stage findOrAllocateIndexOfLockedTextureWithKey:&glyphKeys[x]
                                                               column:x
                                                             creation:creation];
        }
        if (index >= 0) {
            const size_t i = x + row * self.cellConfiguration.gridSize.width;
            iTermTextPIU *piu = &pius[i];
            MTLOrigin origin = [array offsetForIndex:index];
            piu->textureOffset = (vector_float2){ origin.x * w, origin.y * h };
            piu->textColor = attributes[x].foregroundColor;
            piu->backgroundColor = attributes[x].backgroundColor;
            [self addIndex:index];
        }
        lastIndex = index;
    }
}

- (void)didComplete {
    [_textureMap returnStage:_stage];
    _stage = nil;
}

- (nonnull NSMutableData *)modelData  {
    if (_modelData == nil) {
        _modelData = [[NSMutableData alloc] initWithLength:sizeof(iTermTextPIU) * self.cellConfiguration.gridSize.width * self.cellConfiguration.gridSize.height];
    }
    return _modelData;
}

- (void)initializePIUBytes:(void *)bytes {
    iTermTextPIU *pius = (iTermTextPIU *)bytes;
    NSInteger i = 0;
    #warning TODO: There is no reason to do this unless the grid size changes.
    for (NSInteger y = 0; y < self.cellConfiguration.gridSize.height; y++) {
        const float yOffset = (self.cellConfiguration.gridSize.height - y - 1) * self.cellConfiguration.cellSize.height;
        for (NSInteger x = 0; x < self.cellConfiguration.gridSize.width; x++) {
            pius[i++].offset = simd_make_float2(x * self.cellConfiguration.cellSize.width,
                                                yOffset);
        }
    }
}

- (void)addIndex:(NSInteger)index {
    [_indexes addIndex:index];
}

#pragma mark - Debugging

- (iTermTextPIU *)piuArray {
    return (iTermTextPIU *)self.pius.contents;
}

- (iTermVertex *)vertexArray {
    return (iTermVertex *)self.vertexBuffer.contents;
}

@end

@implementation iTermTextRenderer {
    iTermMetalCellRenderer *_cellRenderer;
    iTermTextureMap *_textureMap;
    id<MTLBuffer> _models;
}

- (id<MTLBuffer>)subpixelModels {
    if (_models == nil) {
        NSMutableData *data = [NSMutableData data];
        // The fragment function assumes we use the value 17 here. It's
        // convenient that 17 evenly divides 255 (17 * 15 = 255).
        float stride = 255.0/17.0;
        int i = 0;
        for (float textColor = 0; textColor < 256; textColor += stride) {
            for (float backgroundColor = 0; backgroundColor < 256; backgroundColor += stride) {
                iTermSubpixelModel *model = [[iTermSubpixelModelBuilder sharedInstance] modelForForegoundColor:MIN(MAX(0, textColor / 255.0), 1)
                                                                                               backgroundColor:MIN(MAX(0, backgroundColor / 255.0), 1)];
                [data appendData:model.table];
            }
        }
#warning TODO: Only create one per device
        _models = [_cellRenderer.device newBufferWithBytes:data.bytes
                                                    length:data.length
                                                   options:MTLResourceStorageModeShared];
    }
    return _models;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _cellRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                    vertexFunctionName:@"iTermTextVertexShader"
                                                  fragmentFunctionName:@"iTermTextFragmentShader"
                                                              blending:YES
                                                        piuElementSize:sizeof(iTermTextPIU)
                                                   transientStateClass:[iTermTextRendererTransientState class]];
    }
    return self;
}

- (BOOL)canRenderImmediately {
    return _textureMap.haveStageAvailable;
}

- (void)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                      completion:(void (^)(__kindof iTermMetalRendererTransientState * _Nonnull))completion {
    _cellRenderer.fragmentFunctionName = configuration.usingIntermediatePass ? @"iTermTextFragmentShaderWithBlending" : @"iTermTextFragmentShaderSolidBackground";
    [_cellRenderer createTransientStateForCellConfiguration:configuration
                                              commandBuffer:commandBuffer
                                                 completion:^(__kindof iTermMetalCellRendererTransientState * _Nonnull transientState) {
                                                     [self initializeTransientState:transientState
                                                                      commandBuffer:commandBuffer
                                                                         completion:completion];
                                                 }];
}

- (void)initializeTransientState:(iTermTextRendererTransientState *)tState
                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                      completion:(void (^)(__kindof iTermMetalCellRendererTransientState * _Nonnull))completion {
    const NSInteger capacity = tState.cellConfiguration.gridSize.width * tState.cellConfiguration.gridSize.height * 2;
    if (_textureMap == nil ||
        !CGSizeEqualToSize(_textureMap.cellSize, tState.cellConfiguration.cellSize) ||
        _textureMap.capacity != capacity) {
        _textureMap = [[iTermTextureMap alloc] initWithDevice:_cellRenderer.device
                                                     cellSize:tState.cellConfiguration.cellSize
                                                     capacity:capacity];
        _textureMap.label = [NSString stringWithFormat:@"[texture map for %p]", self];
        _textureMap.array.texture.label = @"Texture grid for session";
    }
    tState.textureMap = _textureMap;

    // The vertex buffer's texture coordinates depend on the texture map's atlas size so it must
    // be initialized after the texture map.
    tState.vertexBuffer = [self newQuadOfSize:tState.cellConfiguration.cellSize];
    tState.pius = [_cellRenderer.device newBufferWithLength:tState.sizeOfNewPIUBuffer
                                                    options:MTLResourceStorageModeShared];
    [tState initializePIUBytes:tState.pius.contents];

    [tState prepareForDrawWithCommandBuffer:commandBuffer completion:^{
        completion(tState);
    }];
}

- (id<MTLBuffer>)newQuadOfSize:(CGSize)size {
    const float vw = static_cast<float>(size.width);
    const float vh = static_cast<float>(size.height);

    const float w = size.width / _textureMap.array.atlasSize.width;
    const float h = size.height / _textureMap.array.atlasSize.height;

    const iTermVertex vertices[] = {
        // Pixel Positions, Texture Coordinates
        { { vw,  0 }, { w, 0 } },
        { { 0,   0 }, { 0, 0 } },
        { { 0,  vh }, { 0, h } },

        { { vw,  0 }, { w, 0 } },
        { { 0,  vh }, { 0, h } },
        { { vw, vh }, { w, h } },
    };
    return [_cellRenderer.device newBufferWithBytes:vertices
                                             length:sizeof(vertices)
                                            options:MTLResourceStorageModeShared];
}

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(__kindof iTermMetalCellRendererTransientState *)transientState {
    iTermTextRendererTransientState *tState = transientState;
    tState.vertexBuffer.label = @"text vertex buffer";
    tState.pius.label = @"text PIUs";
    tState.offsetBuffer.label = @"text offset";

    NSDictionary *textures = @{ @(iTermTextureIndexPrimary): tState.textureMap.array.texture };
    if (tState.cellConfiguration.usingIntermediatePass) {
        textures = [textures dictionaryBySettingObject:tState.backgroundTexture forKey:@(iTermTextureIndexBackground)];
    }
    [_cellRenderer drawWithTransientState:tState
                            renderEncoder:renderEncoder
                         numberOfVertices:6
                             numberOfPIUs:tState.cellConfiguration.gridSize.width * tState.cellConfiguration.gridSize.height
                            vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer,
                                             @(iTermVertexInputIndexPerInstanceUniforms): tState.pius,
                                             @(iTermVertexInputIndexOffset): tState.offsetBuffer }
                          fragmentBuffers:@{ @(iTermFragmentBufferIndexColorModels): self.subpixelModels }
                                 textures:textures];
}

@end
