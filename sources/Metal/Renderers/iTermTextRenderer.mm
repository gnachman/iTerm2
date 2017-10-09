#import "iTermTextRenderer.h"

extern "C" {
#import "DebugLogging.h"
}

#import "iTermMetalCellRenderer.h"
#import "iTermSubpixelModelBuilder.h"
#import "iTermTextureArray.h"
#import "iTermTextureMap.h"
#import <unordered_map>

@interface iTermTextRendererTransientState ()

@property (nonatomic, readonly) NSIndexSet *indexes;
@property (nonatomic, strong) NSData *subpixelModelData;
@property (nonatomic, weak) iTermTextureMap *textureMap;
- (void)addIndex:(NSInteger)index;

@end

@implementation iTermTextRendererTransientState {
    iTermTextureMapStage *_stage;
    NSMutableIndexSet *_indexes;
    NSMutableArray<iTermSubpixelModel *> *_models;
    std::unordered_map<NSUInteger, NSUInteger> *_modelMap;  // Maps a 48 bit fg/bg color to an index into _models.
    dispatch_group_t _group;
    id<MTLCommandBuffer> _commandBuffer;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _indexes = [NSMutableIndexSet indexSet];
        _models = [NSMutableArray array];
        _modelMap = new std::unordered_map<NSUInteger, NSUInteger>();
        _group = dispatch_group_create();
    }
    return self;
}

- (void)dealloc {
    delete _modelMap;
}

- (void)willDraw {
    self.subpixelModelData = [self newSubpixelModelData];
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

- (void)setGlyphKeysData:(NSData *)glyphKeysData
          attributesData:(NSData *)attributesData
                     row:(int)row
                creation:(NSImage *(NS_NOESCAPE ^)(int x))creation {
    const int width = self.gridSize.width;
    const iTermMetalGlyphKey *glyphKeys = (iTermMetalGlyphKey *)glyphKeysData.bytes;
    const iTermMetalGlyphAttributes *attributes = (iTermMetalGlyphAttributes *)attributesData.bytes;
    const float w = 1.0 / _textureMap.array.atlasSize.width;
    const float h = 1.0 / _textureMap.array.atlasSize.height;
    iTermTextureArray *array = _textureMap.array;
    iTermTextPIU *pius = [self textPIUs];

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
            // Update the PIU with the session index. It may not be a legit value yet.
            const size_t i = x + row * self.gridSize.width;
            iTermTextPIU *piu = &pius[i];
            MTLOrigin origin = [array offsetForIndex:index];
            piu->textureOffset = (vector_float2){ origin.x * w, origin.y * h };
            piu->colorModelIndex = [self colorModelIndexForAttributes:&attributes[x]];
            [self addIndex:index];
        }
        lastIndex = index;
    }
}

- (void)didComplete {
    [_textureMap returnStage:_stage];
    _stage = nil;
}

- (iTermTextPIU *)textPIUs {
    return (iTermTextPIU *)self.modelData.mutableBytes;
}

- (nonnull NSMutableData *)modelData  {
    if (_modelData == nil) {
        _modelData = [[NSMutableData alloc] initWithLength:sizeof(iTermTextPIU) * self.gridSize.width * self.gridSize.height];
    }
    return _modelData;
}

- (void)initializePIUData {
    iTermTextPIU *pius = self.textPIUs;
    NSInteger i = 0;
    for (NSInteger y = 0; y < self.gridSize.height; y++) {
        for (NSInteger x = 0; x < self.gridSize.width; x++) {
            const iTermTextPIU uniform = {
                .offset = {
                    static_cast<float>(x * self.cellSize.width),
                    static_cast<float>((self.gridSize.height - y - 1) * self.cellSize.height)
                },
                .textureOffset = { 0, 0 }
            };
            memcpy(&pius[i++], &uniform, sizeof(uniform));
        }
    }
}

- (void)addIndex:(NSInteger)index {
    [_indexes addIndex:index];
}

- (NSData *)newSubpixelModelData {
    const size_t tableSize = _models.firstObject.table.length;
    NSMutableData *data = [NSMutableData dataWithLength:_models.count * tableSize];
    unsigned char *output = (unsigned char *)data.mutableBytes;
    [_models enumerateObjectsUsingBlock:^(iTermSubpixelModel * _Nonnull model, NSUInteger idx, BOOL * _Nonnull stop) {
        const size_t offset = idx * tableSize;
        memcpy(output + offset, model.table.bytes, tableSize);
    }];
    return data;
}

- (int)colorModelIndexForAttributes:(const iTermMetalGlyphAttributes *)attributes {
    NSUInteger key = [iTermSubpixelModel keyForForegroundColor:attributes->foregroundColor
                                               backgroundColor:attributes->backgroundColor];
    auto it = _modelMap->find(key);
    if (it == _modelMap->end()) {
        // TODO: Expire old models
        const NSUInteger index = _models.count;
        iTermSubpixelModel *model = [[iTermSubpixelModelBuilder sharedInstance] modelForForegoundColor:attributes->foregroundColor
                                                                                       backgroundColor:attributes->backgroundColor];
        [_models addObject:model];
        (*_modelMap)[model.key] = index;
        DLog(@"Assign model %@ to index %@", model, @(index));
        return index;
    } else {
        return it->second;
    }
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

- (void)createTransientStateForViewportSize:(vector_uint2)viewportSize
                                   cellSize:(CGSize)cellSize
                                   gridSize:(VT100GridSize)gridSize
                              commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                 completion:(void (^)(__kindof iTermMetalCellRendererTransientState * _Nonnull))completion {
    [_cellRenderer createTransientStateForViewportSize:viewportSize
                                              cellSize:cellSize
                                              gridSize:gridSize
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
    const NSInteger capacity = tState.gridSize.width * tState.gridSize.height * 2;
    if (_textureMap == nil ||
        !CGSizeEqualToSize(_textureMap.cellSize, tState.cellSize) ||
        _textureMap.capacity != capacity) {
        _textureMap = [[iTermTextureMap alloc] initWithDevice:_cellRenderer.device
                                                     cellSize:tState.cellSize
                                                     capacity:capacity];
        _textureMap.label = [NSString stringWithFormat:@"[texture map for %p]", self];
        _textureMap.array.texture.label = @"Texture grid for session";
    }
    tState.textureMap = _textureMap;

    // The vertex buffer's texture coordinates depend on the texture map's atlas size so it must
    // be initialized after the texture map.
    tState.vertexBuffer = [self newQuadOfSize:tState.cellSize];
    [tState initializePIUData];

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
    tState.pius = [_cellRenderer.device newBufferWithBytes:tState.modelData.mutableBytes
                                                           length:tState.modelData.length
                                                          options:MTLResourceStorageModeShared];
    tState.vertexBuffer.label = @"text vertex buffer";
    tState.pius.label = @"text PIUs";
    tState.offsetBuffer.label = @"text offset";

    id<MTLBuffer> subpixelModels = [_cellRenderer.device newBufferWithBytes:tState.subpixelModelData.bytes
                                                                     length:tState.subpixelModelData.length
                                                                     options:MTLResourceStorageModeShared];
    [_cellRenderer drawWithTransientState:tState
                            renderEncoder:renderEncoder
                         numberOfVertices:6
                             numberOfPIUs:tState.gridSize.width * tState.gridSize.height
                            vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer,
                                             @(iTermVertexInputIndexPerInstanceUniforms): tState.pius,
                                             @(iTermVertexInputIndexOffset): tState.offsetBuffer }
                          fragmentBuffers:@{ @(iTermFragmentBufferIndexColorModels): subpixelModels }
                                 textures:@{ @(iTermTextureIndexPrimary): tState.textureMap.array.texture }];
}

@end
