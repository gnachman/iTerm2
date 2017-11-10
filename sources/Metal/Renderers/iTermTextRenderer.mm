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

@end

@implementation iTermTextRendererTransientState {
    iTermTextureMapStage *_stage;
    id<MTLCommandBuffer> _commandBuffer;
    std::vector<int> *_locks;
    NSMutableArray<NSData *> *_backgroundColorDataArray;
    std::vector<iTermTextFixup> *_fixups;
}

- (instancetype)initWithConfiguration:(iTermRenderConfiguration *)configuration {
    self = [super initWithConfiguration:configuration];
    if (self) {
        _locks = new std::vector<int>();
        _backgroundColorDataArray = [NSMutableArray array];
        _fixups = new std::vector<iTermTextFixup>();
    }
    return self;
}

- (void)dealloc {
    delete _locks;
    delete _fixups;
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
        } else {
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
    iTermTextPIU *pius = (iTermTextPIU *)self.pius.contents;
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
            [self addIndex:index retained:retained];
        }
        lastIndex = index;
        lastRelations = relations;
        lastEmoji = emoji;
    }
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
    tState.pius = [_cellRenderer.device newBufferWithLength:tState.sizeOfNewPIUBuffer
                                                    options:MTLResourceStorageModeShared];

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
                             numberOfPIUs:tState.numberOfInstances
                            vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer,
                                             @(iTermVertexInputIndexPerInstanceUniforms): tState.pius,
                                             @(iTermVertexInputIndexOffset): tState.offsetBuffer }
                          fragmentBuffers:@{ @(iTermFragmentBufferIndexColorModels): self.subpixelModels }
                                 textures:textures];
}

@end
