#import "iTermTextRenderer.h"

extern "C" {
#import "DebugLogging.h"
}

#import "iTermMetalCellRenderer.h"
#import "iTermSubpixelModelBuilder.h"
#import "iTermTextureArray.h"
#import "iTermTextureMap.h"
#import "iTermTextureMap+CPP.h"
#import "NSDictionary+iTerm.h"
#import <unordered_map>
#include <vector>

typedef struct {
    iTermTextPIU *piu;
    int x;
    int y;
} iTermTextFixup;

@interface iTermTextRendererTransientState ()

@property (nonatomic, strong) iTermTextureMap *textureMap;
@property (nonatomic, readonly) NSInteger numberOfInstances;
@property (nonatomic, readonly) NSData *colorModels;
@property (nonatomic, readonly) NSData *piuData;
@end

// text color component, background color component
typedef std::pair<unsigned char, unsigned char> iTermColorComponentPair;

@implementation iTermTextRendererTransientState {
    iTermTextureMapStage *_stage;
    id<MTLCommandBuffer> _commandBuffer;
    std::vector<int> *_locks;

    // Data's bytes contains a C array of vector_float4 with background colors.
    NSMutableArray<NSData *> *_backgroundColorDataArray;

    // PIUs that need their background colors set. They belong to parts of glyphs that spilled out
    // of their bounds.
    std::vector<iTermTextFixup> *_fixups;

    // Color models for this frame. Only used when there's no intermediate texture.
    NSMutableData *_colorModels;

    // Key is text, background color component. Value is color model number (0 is 1st, 1 is 2nd, etc)
    // and you can multiply the color model number by 256 to get its starting point in _colorModels.
    // Only used when there's no intermediate texture.
    std::map<iTermColorComponentPair, int> *_colorModelIndexes;

    NSMutableData *_piuData;
}

- (instancetype)initWithConfiguration:(__kindof iTermRenderConfiguration *)configuration {
    self = [super initWithConfiguration:configuration];
    if (self) {
        _locks = new std::vector<int>();
        _backgroundColorDataArray = [NSMutableArray array];
        _fixups = new std::vector<iTermTextFixup>();

        iTermCellRenderConfiguration *cellConfiguration = configuration;
        if (!cellConfiguration.usingIntermediatePass) {
            _colorModels = [NSMutableData data];
            _colorModelIndexes = new std::map<iTermColorComponentPair, int>();
        }
    }
    return self;
}

- (void)dealloc {
    delete _locks;
    delete _fixups;
    if (_colorModelIndexes) {
        delete _colorModelIndexes;
    }
}

- (void)willDrawWithDefaultBackgroundColor:(vector_float4)defaultBackgroundColor {
    // Fix up the background color of parts of glyphs that are drawn outside their cell.
    const int numRows = _backgroundColorDataArray.count;
    const int width = [_backgroundColorDataArray.firstObject length] / sizeof(iTermBackgroundColorPIU);
    for (auto &fixup : *_fixups) {
        if (fixup.y >= 0 && fixup.y < numRows && fixup.x >= 0 && fixup.x < width) {
            NSData *data = _backgroundColorDataArray[fixup.y];
            const vector_float4 *backgroundColors = (vector_float4 *)data.bytes;
            fixup.piu->backgroundColor = backgroundColors[fixup.x];
            if (_colorModels) {
                fixup.piu->colorModelIndex = [self colorModelIndexForPIU:fixup.piu];
            }
        } else {
            // Offscreen
            fixup.piu->backgroundColor = defaultBackgroundColor;
        }
    }
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
    // Reserve enough space for each cell to take 9 spots (cell plus all 8 neighbors)
    return sizeof(iTermTextPIU) * self.cellConfiguration.gridSize.width * self.cellConfiguration.gridSize.height * 9;
}

- (iTermTextPIU *)piuDataBytes {
    if (_piuData == nil) {
        _piuData = [NSMutableData dataWithLength:self.sizeOfNewPIUBuffer];
    }
    return (iTermTextPIU *)_piuData.mutableBytes;
}

- (void)setGlyphKeysData:(NSData *)glyphKeysData
                   count:(int)count
          attributesData:(NSData *)attributesData
                     row:(int)row
     backgroundColorData:(nonnull NSData *)backgroundColorData
                creation:(NSDictionary<NSNumber *, NSImage *> *(NS_NOESCAPE ^)(int x, BOOL *emoji))creation {
    assert(row == _backgroundColorDataArray.count);
    [_backgroundColorDataArray addObject:backgroundColorData];
    const int width = self.cellConfiguration.gridSize.width;
    assert(count <= width);
    const iTermMetalGlyphKey *glyphKeys = (iTermMetalGlyphKey *)glyphKeysData.bytes;
    const iTermMetalGlyphAttributes *attributes = (iTermMetalGlyphAttributes *)attributesData.bytes;
    const float w = 1.0 / _textureMap.array.atlasSize.width;
    const float h = 1.0 / _textureMap.array.atlasSize.height;
    iTermTextureArray *array = _textureMap.array;
    iTermTextPIU *pius = (iTermTextPIU *)self.piuDataBytes;
    const float cellHeight = self.cellConfiguration.cellSize.height;
    const float cellWidth = self.cellConfiguration.cellSize.width;
    const float yOffset = (self.cellConfiguration.gridSize.height - row - 1) * cellHeight;

    NSInteger lastIndex = 0;
    std::map<int, int> lastRelations;
    BOOL lastEmoji = NO;
    for (int x = 0; x < count; x++) {
        if (!glyphKeys[x].drawable) {
            continue;
        }
        std::map<int, int> relations;
        NSInteger index;
        BOOL retained;
        BOOL emoji;
        if (x > 0 && !memcmp(&glyphKeys[x], &glyphKeys[x-1], sizeof(*glyphKeys))) {
            index = lastIndex;
            relations = lastRelations;
            emoji = lastEmoji;
            // When the glyphKey is repeated there's no need to acquire another lock.
            // If we get here, both this and the preceding glyphKey are drawable.
            retained = NO;
        } else {
            index = [_stage findOrAllocateIndexOfLockedTextureWithKey:&glyphKeys[x]
                                                               column:x
                                                            relations:&relations
                                                                emoji:&emoji
                                                             creation:creation];
            retained = YES;
        }
        static int dxs[] = { -1, 0, 1, -1, 0, 1, -1, 0, 1 };
        static int dys[] = { -1, -1, -1, 0, 0, 0, 1, 1, 1 };
        if (relations.size() > 1) {
            for (auto &kvp : relations) {
                const int part = kvp.first;
                const int index = kvp.second;
                iTermTextPIU *piu = &pius[_numberOfInstances];
                piu->offset = simd_make_float2((x + dxs[part]) * cellWidth,
                                                dys[part] * cellHeight + yOffset);
                MTLOrigin origin = [array offsetForIndex:index];
                piu->textureOffset = (vector_float2){ origin.x * w, origin.y * h };
                piu->textColor = attributes[x].foregroundColor;
                piu->remapColors = !emoji;
                if (part == 4) {
                    piu->backgroundColor = attributes[x].backgroundColor;
                    if (_colorModels) {
                        piu->colorModelIndex = [self colorModelIndexForPIU:piu];
                    }
                } else {
                    iTermTextFixup fixup = {
                        .piu = piu,
                        .x = x + dxs[part],
                        .y = row - dys[part]
                    };
                    _fixups->push_back(fixup);
                }
                [self addIndex:index retained:retained];
            }
        } else if (index >= 0) {
            iTermTextPIU *piu = &pius[_numberOfInstances];
            piu->offset = simd_make_float2(x * self.cellConfiguration.cellSize.width,
                                            yOffset);
            MTLOrigin origin = [array offsetForIndex:index];
            piu->textureOffset = (vector_float2){ origin.x * w, origin.y * h };
            piu->textColor = attributes[x].foregroundColor;
            piu->backgroundColor = attributes[x].backgroundColor;
            piu->remapColors = !emoji;
            if (_colorModels) {
                piu->colorModelIndex = [self colorModelIndexForPIU:piu];
            }
            [self addIndex:index retained:retained];
        }
        lastIndex = index;
        lastRelations = relations;
        lastEmoji = emoji;
    }
}

- (vector_int3)colorModelIndexForPIU:(iTermTextPIU *)piu {
    iTermColorComponentPair redPair = std::make_pair(piu->textColor.x * 255,
                                                     piu->backgroundColor.x * 255);
    iTermColorComponentPair greenPair = std::make_pair(piu->textColor.y * 255,
                                                       piu->backgroundColor.y * 255);
    iTermColorComponentPair bluePair = std::make_pair(piu->textColor.z * 255,
                                                      piu->backgroundColor.z * 255);
    vector_int3 result;
    auto it = _colorModelIndexes->find(redPair);
    if (it == _colorModelIndexes->end()) {
        result.x = [self allocateColorModelForColorPair:redPair];
    } else {
        result.x = it->second;
    }
    it = _colorModelIndexes->find(greenPair);
    if (it == _colorModelIndexes->end()) {
        result.y = [self allocateColorModelForColorPair:greenPair];
    } else {
        result.y = it->second;
    }
    it = _colorModelIndexes->find(bluePair);
    if (it == _colorModelIndexes->end()) {
        result.z = [self allocateColorModelForColorPair:bluePair];
    } else {
        result.z = it->second;
    }
    return result;
}

- (int)allocateColorModelForColorPair:(iTermColorComponentPair)colorPair {
    int i = _colorModelIndexes->size();
    iTermSubpixelModel *model = [[iTermSubpixelModelBuilder sharedInstance] modelForForegoundColor:colorPair.first / 255.0
                                                                                   backgroundColor:colorPair.second / 255.0];
    [_colorModels appendData:model.table];
    (*_colorModelIndexes)[colorPair] = i;
    return i;
}

- (void)didComplete {
    assert(_locks);
    assert(_stage);

    [_textureMap returnStage:_stage];
    [_textureMap unlockIndexes:*_locks];
    _stage = nil;
    delete _locks;
    _locks = nil;
}

- (nonnull NSMutableData *)modelData  {
    if (_modelData == nil) {
        _modelData = [[NSMutableData alloc] initWithLength:sizeof(iTermTextPIU) * self.cellConfiguration.gridSize.width * self.cellConfiguration.gridSize.height];
    }
    return _modelData;
}

- (void)addIndex:(NSInteger)index retained:(BOOL)retained {
    if (retained) {
        _locks->push_back(index);
    }
    _numberOfInstances++;
}

@end

@implementation iTermTextRenderer {
    iTermMetalCellRenderer *_cellRenderer;
    iTermTextureMap *_textureMap;
    id<MTLBuffer> _models;
}

- (id<MTLBuffer>)subpixelModelsForState:(iTermTextRendererTransientState *)tState {
    if (tState.colorModels) {
        if (tState.colorModels.length == 0) {
            // Blank screen, emoji-only screen, etc. The buffer won't get accessed but it can't be nil.
            return [_cellRenderer.device newBufferWithBytes:""
                                                     length:1
                                                    options:MTLResourceStorageModeShared];
        }
        return [_cellRenderer.device newBufferWithBytes:tState.colorModels.bytes
                                                 length:tState.colorModels.length
                                                options:MTLResourceStorageModeShared];
    }

    if (_models == nil) {
        NSMutableData *data = [NSMutableData data];
        // The fragment function assumes we use the value 17 here. It's
        // convenient that 17 evenly divides 255 (17 * 15 = 255).
        float stride = 255.0/17.0;
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
    // NOTE: Any time a glyph overflows its bounds into a neighboring cell it's possible the strokes will intersect.
    // I haven't thought of a way to make that look good yet without having to do one draw pass per overflow glyph that
    // blends using the output of the preceding passes.
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
    // Allocate enough space for every glyph to touch the cell plus eight adjacent cells.
    // If I run out of texture memory this is the first place to cut.
#warning It's easy for the texture to exceed Metal's limit of 16384*16384. I will need multiple textures to handle this case.
    const NSInteger capacity = tState.cellConfiguration.gridSize.width * tState.cellConfiguration.gridSize.height * 9;
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
    tState.pius = [_cellRenderer.device newBufferWithBytes:tState.piuData.bytes
                                                    length:tState.piuData.length
                                                   options:MTLResourceStorageModeShared];
    tState.pius.label = @"text PIUs";
    tState.offsetBuffer.label = @"text offset";

    NSDictionary *textures = @{ @(iTermTextureIndexPrimary): tState.textureMap.array.texture };
    if (tState.cellConfiguration.usingIntermediatePass) {
        textures = [textures dictionaryBySettingObject:tState.backgroundTexture forKey:@(iTermTextureIndexBackground)];
    }
    [_cellRenderer drawWithTransientState:tState
                            renderEncoder:renderEncoder
                         numberOfVertices:6
                             numberOfPIUs:tState.numberOfInstances
                            vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer,
                                             @(iTermVertexInputIndexPerInstanceUniforms): tState.pius,
                                             @(iTermVertexInputIndexOffset): tState.offsetBuffer }
                          fragmentBuffers:@{ @(iTermFragmentBufferIndexColorModels): [self subpixelModelsForState:tState] }
                                 textures:textures];
}

@end
