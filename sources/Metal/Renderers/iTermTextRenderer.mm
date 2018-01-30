#import "iTermTextRenderer.h"

extern "C" {
#import "DebugLogging.h"
#import "iTermPreciseTimer.h"
}

#import "iTermMetalCellRenderer.h"

#import "GlyphKey.h"
#import "iTermASCIITexture.h"
#import "iTermCharacterParts.h"
#import "iTermGlyphEntry.h"
#import "iTermMetalBufferPool.h"
#import "iTermMetalDebugInfo.h"
#import "iTermPIUArray.h"
#import "iTermTexturePageCollection.h"
#import "iTermSubpixelModelBuilder.h"
#import "iTermTextRendererTransientState.h"
#import "iTermTextRendererTransientState+Private.h"
#import "iTermTextureArray.h"
#import "iTermTexturePage.h"
#import "iTermTexturePageCollection.h"
#import "NSArray+iTerm.h"
#import "NSMutableData+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"
#import <map>
#import <set>
#import <unordered_map>
#import <vector>

static const NSInteger iTermTextAtlasCapacity = 16;

// This seems like a good number 🤷. It lets you draw this many * iTermTextAtlasCapacity distinct
// non-ascii characters at one time without having to constantly prune and redraw glyphs. That's
// 64k chars under the current values of 16 and 4096.
static const int iTermTextRendererMaximumNumberOfTexturePages = 4096;

@interface iTermTextRendererCachedQuad : NSObject
@property (nonatomic, strong) id<MTLBuffer> quad;
@property (nonatomic) CGSize textureSize;
@property (nonatomic) CGSize cellSize;
@end

@implementation iTermTextRendererCachedQuad

- (BOOL)isEqual:(id)object {
    iTermTextRendererCachedQuad *other = [iTermTextRendererCachedQuad castFrom:object];
    if (!other) {
        return NO;
    }

    return (CGSizeEqualToSize(_textureSize, other->_textureSize) &&
            CGSizeEqualToSize(_cellSize, other->_cellSize));
}

@end

@interface iTermTextRenderer() <iTermMetalDebugInfoFormatter>
@end

@implementation iTermTextRenderer {
    iTermMetalCellRenderer *_cellRenderer;
    id<MTLBuffer> _models;
    iTermASCIITextureGroup *_asciiTextureGroup;

    iTermTexturePageCollectionSharedPointer *_texturePageCollectionSharedPointer;
    NSMutableArray<iTermTextRendererCachedQuad *> *_quadCache;
    CGSize _cellSizeForQuadCache;

    iTermMetalBufferPool *_emptyBuffers;
    iTermMetalBufferPool *_verticesPool;
    iTermMetalBufferPool *_dimensionsPool;
    iTermMetalMixedSizeBufferPool *_piuPool;
    iTermMetalMixedSizeBufferPool *_subpixelModelPool;
}

+ (NSData *)subpixelModelData {
    static NSData *subpixelModelData;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
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
        subpixelModelData = data;
    });
    return subpixelModelData;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateTextTS;
}

- (id<MTLBuffer>)subpixelModelsForState:(iTermTextRendererTransientState *)tState {
    if (tState.colorModels) {
        if (tState.colorModels.length == 0) {
            // Blank screen, emoji-only screen, etc. The buffer won't get accessed but it can't be nil.
            return [_emptyBuffers requestBufferFromContext:tState.poolContext];
        }
        // Return a color model with exactly the fg/bg combos on screen.
        return [_subpixelModelPool requestBufferFromContext:tState.poolContext
                                                       size:tState.colorModels.length
                                                      bytes:tState.colorModels.bytes];
    }

    // Use a generic color model for blending. No need to use a buffer pool here because this is only
    // created once.
    if (_models == nil) {
        NSData *subpixelModelData = [iTermTextRenderer subpixelModelData];
        _models = [_cellRenderer.device newBufferWithBytes:subpixelModelData.bytes
                                                    length:subpixelModelData.length
                                                   options:MTLResourceStorageModeManaged];
        _models.label = @"Subpixel models";
    }
    return _models;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _cellRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                    vertexFunctionName:@"iTermTextVertexShader"
                                                  fragmentFunctionName:@"iTermTextFragmentShader"
                                                              blending:[[iTermMetalBlending alloc] init]
                                                        piuElementSize:sizeof(iTermTextPIU)
                                                   transientStateClass:[iTermTextRendererTransientState class]];
        _cellRenderer.formatterDelegate = self;

        _quadCache = [NSMutableArray array];
        _emptyBuffers = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:1];
        _verticesPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermVertex) * 6];
        _dimensionsPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermTextureDimensions)];

        // Allow the pool to reserve up to this many bytes. Work backward to find the largest number
        // of buffers we are OK with keeping permanently allocated. By having enough characters on
        // screen you could easily go over this, which will cost a major performance penalty because
        // vertex buffers are slow to create.
        const NSInteger memoryBudget = 1024 * 1024 * 100;
        const NSInteger maxInstances = memoryBudget / sizeof(iTermTextPIU);
        const size_t capacity = iTerm2::PIUArray<iTermTextPIU>::DEFAULT_CAPACITY;
        _piuPool = [[iTermMetalMixedSizeBufferPool alloc] initWithDevice:device
                                                                capacity:(maxInstances / capacity) * iTermMetalDriverMaximumNumberOfFramesInFlight
                                                                    name:@"text PIU"];

        _subpixelModelPool = [[iTermMetalMixedSizeBufferPool alloc] initWithDevice:device
                                                                          capacity:512
                                                                              name:@"subpixel PIU"];
    }
    return self;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (__kindof iTermMetalRendererTransientState * _Nonnull)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    if (!CGSizeEqualToSize(configuration.cellSize, _cellSizeForQuadCache)) {
        // All quads depend on cell size. No point keeping usesless entries in the cache.
        [_quadCache removeAllObjects];
        _cellSizeForQuadCache = configuration.cellSize;
    }
    // NOTE: Any time a glyph overflows its bounds into a neighboring cell it's possible the strokes will intersect.
    // I haven't thought of a way to make that look good yet without having to do one draw pass per overflow glyph that
    // blends using the output of the preceding passes.
    _cellRenderer.fragmentFunctionName = configuration.usingIntermediatePass ? @"iTermTextFragmentShaderWithBlending" : @"iTermTextFragmentShaderSolidBackground";
    __kindof iTermMetalCellRendererTransientState * _Nonnull transientState =
        [_cellRenderer createTransientStateForCellConfiguration:configuration
                                              commandBuffer:commandBuffer];
    [self initializeTransientState:transientState
                     commandBuffer:commandBuffer];
    return transientState;

}

- (void)initializeTransientState:(iTermTextRendererTransientState *)tState
                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    if (_texturePageCollectionSharedPointer != NULL) {
        const vector_uint2 &oldSize = _texturePageCollectionSharedPointer.object->get_cell_size();
        CGSize newSize = tState.cellConfiguration.cellSize;
        if (oldSize.x != newSize.width || oldSize.y != newSize.height) {
            _texturePageCollectionSharedPointer = nil;
        }
    }
    if (!_texturePageCollectionSharedPointer) {
        iTerm2::TexturePageCollection *collection = new iTerm2::TexturePageCollection(_cellRenderer.device,
                                                                                      simd_make_uint2(tState.cellConfiguration.cellSize.width,
                                                                                                      tState.cellConfiguration.cellSize.height),
                                                                                      iTermTextAtlasCapacity,
                                                                                      iTermTextRendererMaximumNumberOfTexturePages);
        _texturePageCollectionSharedPointer = [[iTermTexturePageCollectionSharedPointer alloc] initWithObject:collection];
    }

    tState.device = _cellRenderer.device;
    tState.asciiTextureGroup = _asciiTextureGroup;
    tState.texturePageCollectionSharedPointer = _texturePageCollectionSharedPointer;
    tState.numberOfCells = tState.cellConfiguration.gridSize.width * tState.cellConfiguration.gridSize.height;
}

- (id<MTLBuffer>)quadOfSize:(CGSize)size
                textureSize:(CGSize)textureSize
                poolContext:(iTermMetalBufferPoolContext *)poolContext {
    iTermTextRendererCachedQuad *entry = [[iTermTextRendererCachedQuad alloc] init];
    entry.cellSize = size;
    entry.textureSize = textureSize;
    NSInteger index = [_quadCache indexOfObject:entry];
    if (index != NSNotFound) {
        id<MTLBuffer> quad = _quadCache[index].quad;
        return quad;
    }

    const float vw = static_cast<float>(size.width);
    const float vh = static_cast<float>(size.height);

    const float w = size.width / textureSize.width;
    const float h = size.height / textureSize.height;

    const iTermVertex vertices[] = {
        // Pixel Positions, Texture Coordinates
        { { vw,  0 }, { w, 0 } },
        { { 0,   0 }, { 0, 0 } },
        { { 0,  vh }, { 0, h } },

        { { vw,  0 }, { w, 0 } },
        { { 0,  vh }, { 0, h } },
        { { vw, vh }, { w, h } },
    };
    entry.quad = [_verticesPool requestBufferFromContext:poolContext
                                               withBytes:vertices
                                          checkIfChanged:YES];
    entry.quad.label = @"Text Quad";
    // I cache quads myself, so I don't want them returned to the pool where they could change
    // out from under my cache.
    [poolContext relinquishOwnershipOfBuffer:entry.quad];
    [_quadCache addObject:entry];
    // It's useful to hold a quad for ascii and one for non-ascii.
    if (_quadCache.count > 2) {
        [_quadCache removeObjectAtIndex:0];
    }

    return entry.quad;
}

- (id<MTLBuffer>)piuBufferForPIUs:(const iTermTextPIU *)pius
                           tState:(__kindof iTermTextRendererTransientState *)tState
                        instances:(NSInteger)instances {
    id<MTLBuffer> piuBuffer;
    piuBuffer = [_piuPool requestBufferFromContext:tState.poolContext
                                              size:sizeof(iTermTextPIU) * instances
                                             bytes:pius];
    piuBuffer.label = @"Text PIUs";
    ITDebugAssert(piuBuffer);
    return piuBuffer;
}

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(__kindof iTermMetalCellRendererTransientState *)transientState {
    iTermTextRendererTransientState *tState = transientState;
    tState.vertexBuffer.label = @"Text vertex buffer";
    tState.offsetBuffer.label = @"Offset";
    const float scale = tState.cellConfiguration.scale;

    // The vertex buffer's texture coordinates depend on the texture map's atlas size so it must
    // be initialized after the texture map.
    __block NSInteger totalInstances = 0;
    __block iTermTextureDimensions previousTextureDimensions;
    __block id<MTLBuffer> previousTextureDimensionsBuffer = nil;

    __block id<MTLBuffer> subpixelModelsBuffer;
    [tState measureTimeForStat:iTermTextRendererStatSubpixelModel ofBlock:^{
        subpixelModelsBuffer = [self subpixelModelsForState:tState];
    }];

    [tState enumerateDraws:^(const iTermTextPIU *pius, NSInteger instances, id<MTLTexture> texture, vector_uint2 textureSize, vector_uint2 cellSize, iTermMetalUnderlineDescriptor underlineDescriptor) {
        totalInstances += instances;
        __block id<MTLBuffer> vertexBuffer;
        [tState measureTimeForStat:iTermTextRendererStatNewQuad ofBlock:^{
            vertexBuffer = [self quadOfSize:tState.cellConfiguration.cellSize
                                textureSize:CGSizeMake(textureSize.x, textureSize.y)
                                poolContext:tState.poolContext];
        }];

        __block id<MTLBuffer> piuBuffer;
        [tState measureTimeForStat:iTermTextRendererStatNewPIU ofBlock:^{
            piuBuffer = [self piuBufferForPIUs:pius tState:tState instances:instances];
        }];

        NSDictionary *textures = @{ @(iTermTextureIndexPrimary): texture };
        if (tState.cellConfiguration.usingIntermediatePass) {
            textures = [textures dictionaryBySettingObject:tState.backgroundTexture forKey:@(iTermTextureIndexBackground)];
        }


        __block id<MTLBuffer> textureDimensionsBuffer;
        [tState measureTimeForStat:iTermTextRendererStatNewDims ofBlock:^{
            iTermTextureDimensions textureDimensions = {
                .textureSize = simd_make_float2(textureSize.x, textureSize.y),
                .cellSize = simd_make_float2(cellSize.x, cellSize.y),
                .underlineOffset = cellSize.y - (underlineDescriptor.offset * scale),
                .underlineThickness = underlineDescriptor.thickness * scale,
                .scale = scale
            };

            // These tend to get reused so avoid changing the buffer if it is the same as the last one.
            if (previousTextureDimensionsBuffer != nil &&
                !memcmp(&textureDimensions, &previousTextureDimensions, sizeof(textureDimensions))) {
                textureDimensionsBuffer = previousTextureDimensionsBuffer;
            } else {
                textureDimensionsBuffer = [_dimensionsPool requestBufferFromContext:tState.poolContext
                                                                          withBytes:&textureDimensions
                                                                     checkIfChanged:YES];
                textureDimensionsBuffer.label = @"Texture dimensions";
                previousTextureDimensionsBuffer = textureDimensionsBuffer;
                std::memcpy((void *)&previousTextureDimensions,
                            (void *)&textureDimensions,
                            sizeof(textureDimensions));
            }
        }];

        [tState measureTimeForStat:iTermTextRendererStatDraw ofBlock:^{
            [_cellRenderer drawWithTransientState:tState
                                    renderEncoder:renderEncoder
                                 numberOfVertices:6
                                     numberOfPIUs:instances
                                    vertexBuffers:@{ @(iTermVertexInputIndexVertices): vertexBuffer,
                                                     @(iTermVertexInputIndexPerInstanceUniforms): piuBuffer,
                                                     @(iTermVertexInputIndexOffset): tState.offsetBuffer }
                                  fragmentBuffers:@{ @(iTermFragmentBufferIndexColorModels): subpixelModelsBuffer,
                                                     @(iTermFragmentInputIndexTextureDimensions): textureDimensionsBuffer }
                                         textures:textures];
        }];
    }];
}

- (void)setASCIICellSize:(CGSize)cellSize
      creationIdentifier:(id)creationIdentifier
                creation:(NSDictionary<NSNumber *, iTermCharacterBitmap *> *(^)(char, iTermASCIITextureAttributes))creation {
    iTermASCIITextureGroup *replacement = [[iTermASCIITextureGroup alloc] initWithCellSize:cellSize
                                                                                    device:_cellRenderer.device
                                                                        creationIdentifier:(id)creationIdentifier
                                                                                  creation:creation];
    if (![replacement isEqual:_asciiTextureGroup]) {
        _asciiTextureGroup = replacement;
    }
}

#pragma mark - iTermMetalDebugInfoFormatter

- (void)writeVertexBuffer:(id<MTLBuffer>)buffer index:(NSUInteger)index toFolder:(NSURL *)folder {
    if (index == iTermVertexInputIndexPerInstanceUniforms) {
        NSMutableString *s = [NSMutableString string];
        const iTermTextPIU *pius = (const iTermTextPIU *)buffer.contents;
        for (int i = 0; i < buffer.length / sizeof(iTermTextPIU); i++) {
            [s appendString:[iTermTextRendererTransientState formatTextPIU:pius[i]]];
        }
        NSURL *url = [folder URLByAppendingPathComponent:@"vertexBuffer.iTermVertexInputIndexPerInstanceUniforms.txt"];
        [s writeToURL:url atomically:NO encoding:NSUTF8StringEncoding error:nil];
    }
}

@end
