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
#import "iTermTexture.h"
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

// True for macOS 10.14+. Means no subpixel antialiasing, so text blending is very simple.
static BOOL gMonochromeText;

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
    id<MTLTexture> _models NS_DEPRECATED_MAC(10_12, 10_14);
    iTermASCIITextureGroup *_asciiTextureGroup;

    iTermTexturePageCollectionSharedPointer *_texturePageCollectionSharedPointer;
    NSMutableArray<iTermTextRendererCachedQuad *> *_quadCache;
    CGSize _cellSizeForQuadCache;

    iTermMetalBufferPool *_emptyBuffers;
    iTermMetalBufferPool *_verticesPool;
    iTermMetalBufferPool *_dimensionsPool;
    iTermMetalBufferPool *_textInfoPool;
    iTermMetalMixedSizeBufferPool *_piuPool;
    iTermMetalMixedSizeBufferPool *_subpixelModelPool NS_DEPRECATED_MAC(10_12, 10_14);
}

/*
 * Input is organized as
 *  Index   Text  Bg   Sample
 *      0     0   0        0
 *                       ...
 *                       255
 *    256         1        0
 *                       ...
 *                       255
 *  256*2         2        0
 *              ...
 * 256*17        17        0
 *                       ...
 *                       255
 * 256*18      1   0       0
 *               ...
 *
 * Output is organized as a 2d texture that lets us use the GPU's bilinear
 * interpolation. It's about 33% faster overall on my iMac.
 *
 *                sample=0 sample=1 ...
 *                text ->  text->
 *  background    0...255  0...255
 *  |        0    XXXXXXX  XXXXXXX     XXXXXXX
 *  V      ...    XXXXXXX  XXXXXXX ... XXXXXXX
 *          17    XXXXXXX  XXXXXXX     XXXXXXX
 *
 * Width = 256 * 18
 * Height = 18
 * Bytes per sample = 1
 */
+ (NSData *)transformedData:(NSData *)input {
    const unsigned char *inputBytes = reinterpret_cast<const unsigned char *>(input.bytes);
    unsigned char (^load)(int, int, int) = ^unsigned char(int text, int background, int bwSample) {
        const size_t i = 256 * (18 * text + background) + bwSample;
        return inputBytes[i];
    };

    NSMutableData *output = [NSMutableData uninitializedDataWithLength:18 * 18 * 256];
    unsigned char *outputBytes = reinterpret_cast<unsigned char *>(output.mutableBytes);
    void (^store)(int, int, int, unsigned char) = ^void(int text, int background, int bwSample, unsigned char value) {
        const size_t i = 18 * (bwSample + 256 * background) + text;
        outputBytes[i] = value;
    };
    for (int t = 0; t < 18; t ++) {
        for (int b = 0; b < 18; b ++) {
            for (int s = 0; s < 256; s++) {
                store(t, b, s, load(t, b, s));
            }
        }
    }
    return output;
}

+ (void)enumerateGridOfSubpixelModels:(void (^)(float, float, iTermSubpixelModel *))block NS_DEPRECATED_MAC(10_12, 10_14) {
    // The fragment function assumes we use the value 17 here. It's
    // convenient that 17 evenly divides 255 (17 * 15 = 255).
    float stride = 255.0/17.0;
    for (float textColor = 0; textColor < 256; textColor += stride) {
        for (float backgroundColor = 0; backgroundColor < 256; backgroundColor += stride) {
            iTermSubpixelModel *model = [[iTermSubpixelModelBuilder sharedInstance] modelForForegroundColor:MIN(MAX(0, textColor / 255.0), 1)
                                                                                           backgroundColor:MIN(MAX(0, backgroundColor / 255.0), 1)];
            block(textColor, backgroundColor, model);
        }
    }
}

+ (NSData *)subpixelModelData NS_DEPRECATED_MAC(10_12, 10_14) {
    static NSData *subpixelModelData;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableData *data = [NSMutableData data];
        [self enumerateGridOfSubpixelModels:^(float textColor, float backgroundColor, iTermSubpixelModel *model) {
            [data appendData:model.table];
        }];
        subpixelModelData = [self transformedData:data];
    });
    return subpixelModelData;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateTextTS;
}

- (id<MTLBuffer>)subpixelModelsForState:(iTermTextRendererTransientState *)tState NS_DEPRECATED_MAC(10_12, 10_14) {
    if (tState.colorModels) {
        if (tState.colorModels.length == 0) {
            // Blank screen, emoji-only screen, etc. The buffer won't get accessed but it can't be nil.
            return [_emptyBuffers requestBufferFromContext:tState.poolContext];
        }
        // Return a color model with exactly the fg/bg combos on screen.
        return [_subpixelModelPool requestBufferFromContext:tState.poolContext
                                                       size:tState.colorModels.length
                                                      bytes:tState.colorModels.bytes];
    } else {
        return [_subpixelModelPool requestBufferFromContext:tState.poolContext
                                                       size:1
                                                      bytes:""];
    }
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            if (iTermTextIsMonochrome()) {
                gMonochromeText = YES;
            } else {
                gMonochromeText = NO;
            }
        });
        // NOTE: The vertex and fragment function names get changed later. These aren't used but must be valid.
        iTermMetalBlending *blending;
        if (iTermTextIsMonochrome()) {
            blending = [iTermMetalBlending premultipliedCompositing];
        } else {
            blending = [[iTermMetalBlending alloc] init];
        }
        _cellRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                    vertexFunctionName:@"iTermTextVertexShader"
                                                  fragmentFunctionName:@"iTermTextFragmentShaderWithBlendingEmoji"
                                                              blending:blending
                                                        piuElementSize:sizeof(iTermTextPIU)
                                                   transientStateClass:[iTermTextRendererTransientState class]];
        _cellRenderer.formatterDelegate = self;

        _quadCache = [NSMutableArray array];
        _emptyBuffers = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:1];
        _verticesPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermVertex) * 6];
        _dimensionsPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermTextureDimensions)];
        _textInfoPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermVertexInputMojaveVertexTextInfoStruct)];

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

        if (iTermTextIsMonochrome()) {} else {
            _subpixelModelPool = [[iTermMetalMixedSizeBufferPool alloc] initWithDevice:device
                                                                              capacity:512
                                                                                  name:@"subpixel PIU"];
            NSData *subpixelModelData = [iTermTextRenderer subpixelModelData];

            MTLTextureDescriptor *textureDescriptor =
              [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm
                                                                 width:18 * 256
                                                                height:18
                                                             mipmapped:NO];
            _models = [_cellRenderer.device newTextureWithDescriptor:textureDescriptor];
            _models.label = @"Subpixel Models";
            [_models replaceRegion:MTLRegionMake2D(0, 0, 18 * 256, 18)
                       mipmapLevel:0
                         withBytes:subpixelModelData.bytes
                       bytesPerRow:18 * 256];
            [iTermTexture setBytesPerRow:18*256
                             rawDataSize:18 * 256 * 18
                         samplesPerPixel:1
                              forTexture:_models];
        }
    }
    return self;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (nullable __kindof iTermMetalRendererTransientState *)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                                                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    if (!CGSizeEqualToSize(configuration.cellSize, _cellSizeForQuadCache)) {
        // All quads depend on cell size. No point keeping usesless entries in the cache.
        [_quadCache removeAllObjects];
        _cellSizeForQuadCache = configuration.cellSize;
    }
    // NOTE: Any time a glyph overflows its bounds into a neighboring cell it's possible the strokes will intersect.
    // I haven't thought of a way to make that look good yet without having to do one draw pass per overflow glyph that
    // blends using the output of the preceding passes.
    __kindof iTermMetalCellRendererTransientState * _Nonnull transientState =
        [_cellRenderer createTransientStateForCellConfiguration:configuration
                                              commandBuffer:commandBuffer];
    [self initializeTransientState:transientState
                     commandBuffer:commandBuffer];
    return transientState;

}

- (void)initializeTransientState:(iTermTextRendererTransientState *)tState
                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    const CGSize currentSize = tState.cellConfiguration.glyphSize;
    if (_texturePageCollectionSharedPointer != NULL) {
        const vector_uint2 &oldSize = _texturePageCollectionSharedPointer.object->get_cell_size();
        if (oldSize.x != currentSize.width || oldSize.y != currentSize.height) {
            _texturePageCollectionSharedPointer = nil;
        }
    }
    if (!_texturePageCollectionSharedPointer) {
        iTerm2::TexturePageCollection *collection = new iTerm2::TexturePageCollection(_cellRenderer.device,
                                                                                      simd_make_uint2(currentSize.width, currentSize.height),
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

static NSString *const FragmentFunctionName(const BOOL &underlined,
                                            const BOOL &blending,
                                            const BOOL &emoji) {
    static NSArray<NSString *> *names = @[ @"iTermTextFragmentShaderSolidBackground",
                                           @"iTermTextFragmentShaderSolidBackgroundEmoji",
                                           @"iTermTextFragmentShaderWithBlending",
                                           @"iTermTextFragmentShaderWithBlendingEmoji",
                                           @"iTermTextFragmentShaderSolidBackgroundUnderlined",
                                           @"iTermTextFragmentShaderSolidBackgroundUnderlinedEmoji",
                                           @"iTermTextFragmentShaderWithBlendingUnderlined",
                                           @"iTermTextFragmentShaderWithBlendingUnderlinedEmoji",
                                           
                                           @"iTermTextFragmentShaderMonochrome",                  // mono regular text
                                           @"iTermTextFragmentShaderWithBlendingEmoji",           // mono emoji
                                           @"iTermTextFragmentShaderMonochrome",                  // mono blending regular text (impossible)
                                           @"iTermTextFragmentShaderWithBlendingEmoji",           // mono blending emoji (impossible)
                                           @"iTermTextFragmentShaderMonochromeUnderlined",        // mono underlined regular text
                                           @"iTermTextFragmentShaderMonochromeUnderlinedEmoji",   // mono underlined emoji
                                           @"iTermTextFragmentShaderMonochromeUnderlined",        // mono underlined blending regular text (impossible)
                                           @"iTermTextFragmentShaderMonochromeUnderlinedEmoji"];  // mono underlined blending emoji (impossible)
    int index = (gMonochromeText ? 8 : 0) | (underlined ? 4 : 0) | (blending ? 2 : 0) | (emoji ? 1 : 0);
    return names[index];
}

static NSString *const VertexFunctionName(const BOOL &underlined,
                                          const BOOL &blending,
                                          const BOOL &emoji) {
    static NSArray<NSString *> *names = @[ @"iTermTextVertexShader",           // solid color regular text
                                           @"iTermTextVertexShaderEmoji",      // emoji
                                           @"iTermTextVertexShaderBlending",   // blending regular text
                                           @"iTermTextVertexShaderEmoji",      // blending emoji
                                           @"iTermTextVertexShader",           // underlined solid color regular text
                                           @"iTermTextVertexShader",           // underlined solid color emoji
                                           @"iTermTextVertexShader",           // underlined blending regular text
                                           @"iTermTextVertexShader",           // underlined blending emoji
                                           
                                           // Monochrome (10.14+)
                                           @"iTermTextVertexShaderMonochrome",  // mono
                                           @"iTermTextVertexShaderEmoji",       // mono emoji
                                           @"iTermTextVertexShaderMonochrome",  // mono blending (impossible)
                                           @"iTermTextVertexShaderEmoji",       // mono blending emoji (impossible)
                                           @"iTermTextVertexShader",            // mono underlined
                                           @"iTermTextVertexShader",            // mono underlined emoji
                                           @"iTermTextVertexShader",            // mono underlined blending (impossible)
                                           @"iTermTextVertexShader" ];          // mono underlined blending emoji (impossible)
    int index = (gMonochromeText ? 8 : 0) | (underlined ? 4 : 0) | (blending ? 2 : 0) | (emoji ? 1 : 0);
    return names[index];
}

- (void)blitFromTemporaryToIntermediateTexture:(iTermMetalFrameData * _Nonnull)frameData NS_DEPRECATED_MAC(10_12, 10_14) {
    [frameData.renderEncoder endEncoding];
    
    id<MTLBlitCommandEncoder> blitter = [frameData.commandBuffer blitCommandEncoder];
    blitter.label = [NSString stringWithFormat:@"Temporary>Intermediate"];
    id<MTLTexture> source = frameData.temporaryRenderPassDescriptor.colorAttachments[0].texture;
    id<MTLTexture> dest = frameData.intermediateRenderPassDescriptor.colorAttachments[0].texture;
    [blitter copyFromTexture:source
                 sourceSlice:0
                 sourceLevel:0
                sourceOrigin:MTLOriginMake(0, 0, 0)
                  sourceSize:MTLSizeMake(source.width, source.height, 1)
                   toTexture:dest
            destinationSlice:0
            destinationLevel:0
           destinationOrigin:MTLOriginMake(0, 0, 0)];
    [blitter endEncoding];
    
    [frameData updateRenderEncoderWithRenderPassDescriptor:frameData.temporaryRenderPassDescriptor
                                                      stat:iTermMetalFrameDataStatNA
                                                     label:@"Draw more text"];
}

- (id<MTLBuffer>)textInfoBufferForTransientState:(iTermTextRendererTransientState *)tState {
    iTermVertexInputMojaveVertexTextInfoStruct textInfo;
    float power;
    if (tState.cellConfiguration.scale == 2.0) {
        power = 3;
    } else {
        // See issue 7032 for how this was arrived at
        power = 2.0;
    }
    textInfo.powerConstant = power;
    textInfo.powerMultiplier = -(power - 1.0);
    id<MTLBuffer> buffer = [self->_textInfoPool requestBufferFromContext:tState.poolContext
                                                               withBytes:&textInfo
                                                          checkIfChanged:YES];
    buffer.label = @"Text info";
    return buffer;
}

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalCellRendererTransientState *)transientState {
    iTermTextRendererTransientState *tState = transientState;
    tState.vertexBuffer.label = @"Text vertex buffer";
    tState.offsetBuffer.label = @"Offset";
    const float scale = tState.cellConfiguration.scale;
    const simd_float2 cellSize = simd_make_float2(frameData.cellConfiguration.cellSize.width,
                                                  frameData.cellConfiguration.cellSize.height);
    bool blending;
    if (iTermTextIsMonochrome()) {
        blending = false;
    } else {
        blending = tState.cellConfiguration.usingIntermediatePass || tState.disableIndividualColorModels;
    }

    // The vertex buffer's texture coordinates depend on the texture map's atlas size so it must
    // be initialized after the texture map.
    __block NSInteger totalInstances = 0;
    __block iTermTextureDimensions previousTextureDimensions;
    __block id<MTLBuffer> previousTextureDimensionsBuffer = nil;

    __block id<MTLBuffer> subpixelModelsBuffer NS_DEPRECATED_MAC(10_12, 10_14);
    if (iTermTextIsMonochrome()) {} {
        [tState measureTimeForStat:iTermTextRendererStatSubpixelModel ofBlock:^{
            subpixelModelsBuffer = [self subpixelModelsForState:tState];
        }];
    }

    [tState enumerateDraws:^(const iTermTextPIU *pius,
                             NSInteger instances,
                             id<MTLTexture> texture,
                             vector_uint2 textureSize,
                             vector_uint2 glyphSize,
                             iTermMetalUnderlineDescriptor underlineDescriptor,
                             BOOL underlined,
                             BOOL emoji) {
        totalInstances += instances;
        __block id<MTLBuffer> vertexBuffer;
        [tState measureTimeForStat:iTermTextRendererStatNewQuad ofBlock:^{
            vertexBuffer = [self quadOfSize:CGSizeMake(glyphSize.x, glyphSize.y)
                                textureSize:CGSizeMake(textureSize.x, textureSize.y)
                                poolContext:tState.poolContext];
        }];

        __block id<MTLBuffer> textInfoBuffer;
        [tState measureTimeForStat:iTermTextRendererStatNewTextInfo ofBlock:^{
            textInfoBuffer = [self textInfoBufferForTransientState:tState];
        }];
        __block id<MTLBuffer> piuBuffer;
        [tState measureTimeForStat:iTermTextRendererStatNewPIU ofBlock:^{
            piuBuffer = [self piuBufferForPIUs:pius tState:tState instances:instances];
        }];

        NSDictionary *textures;
        if (iTermTextIsMonochrome()) {
            textures = @{ @(iTermTextureIndexPrimary): texture };
        } else {
            textures = @{ @(iTermTextureIndexPrimary): texture,
                          @(iTermTextureIndexSubpixelModels): self->_models };
            if (tState.cellConfiguration.usingIntermediatePass || tState.disableIndividualColorModels) {
                textures = [textures dictionaryBySettingObject:tState.backgroundTexture forKey:@(iTermTextureIndexBackground)];
            }
        }

        __block id<MTLBuffer> textureDimensionsBuffer;
        const float underlineThickness = underlineDescriptor.thickness * scale;
        [tState measureTimeForStat:iTermTextRendererStatNewDims ofBlock:^{
            iTermTextureDimensions textureDimensions = {
                .textureSize = simd_make_float2(textureSize.x, textureSize.y),
                .glyphSize = simd_make_float2(glyphSize.x, glyphSize.y),
                .cellSize = cellSize,
                .underlineOffset = MAX(underlineThickness, glyphSize.y - (underlineDescriptor.offset * scale)),
                .underlineThickness = underlineThickness,
                .scale = scale,
            };

            // These tend to get reused so avoid changing the buffer if it is the same as the last one.
            if (previousTextureDimensionsBuffer != nil &&
                !memcmp(&textureDimensions, &previousTextureDimensions, sizeof(textureDimensions))) {
                textureDimensionsBuffer = previousTextureDimensionsBuffer;
            } else {
                textureDimensionsBuffer = [self->_dimensionsPool requestBufferFromContext:tState.poolContext
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
            // Change the pipeline state just before drawing so we get the right underlined/not underlined state.
            self->_cellRenderer.fragmentFunctionName = FragmentFunctionName(underlined, blending, emoji);
            self->_cellRenderer.vertexFunctionName = VertexFunctionName(underlined, blending, emoji);
            tState.pipelineState = [self->_cellRenderer pipelineState];
            NSDictionary *fragmentBuffers;
            if (iTermTextIsMonochrome()) {
                fragmentBuffers = @{ @(iTermFragmentInputIndexTextureDimensions): textureDimensionsBuffer };
            } else {
                fragmentBuffers = @{ @(iTermFragmentBufferIndexColorModels): subpixelModelsBuffer,
                                     @(iTermFragmentInputIndexTextureDimensions): textureDimensionsBuffer };
            }
            [self->_cellRenderer drawWithTransientState:tState
                                          renderEncoder:frameData.renderEncoder
                                       numberOfVertices:6
                                           numberOfPIUs:instances
                                          vertexBuffers:@{ @(iTermVertexInputIndexVertices): vertexBuffer,
                                                           @(iTermVertexInputMojaveVertexTextInfo): textInfoBuffer,
                                                           @(iTermVertexInputIndexPerInstanceUniforms): piuBuffer,
                                                           @(iTermVertexInputIndexOffset): tState.offsetBuffer }
                                        fragmentBuffers:fragmentBuffers
                                               textures:textures];
        }];
    }
                 copyBlock:^{
                     if (iTermTextIsMonochrome()) {
                         // We don't write to a temporary texture on 10.14.
                         return;
                     } else {
#if ENABLE_PRETTY_ASCII_OVERLAP
                         [self blitFromTemporaryToIntermediateTexture:frameData];
#endif
                     }
                 }
     ];
}

- (void)setASCIICellSize:(CGSize)cellSize
               glyphSize:(CGSize)glyphSize
      creationIdentifier:(id)creationIdentifier
                creation:(NSDictionary<NSNumber *, iTermCharacterBitmap *> *(^)(char, iTermASCIITextureAttributes))creation {
    iTermASCIITextureGroup *replacement = [[iTermASCIITextureGroup alloc] initWithGlyphSize:glyphSize
                                                                                     device:_cellRenderer.device
                                                                         creationIdentifier:(id)creationIdentifier
                                                                                   creation:creation];
    if (![replacement isEqual:_asciiTextureGroup]) {
        _asciiTextureGroup = replacement;
    }
}

- (void)writeDebugInfoToFolder:(NSURL *)folder {
    if (iTermTextIsMonochrome()) {
        return;
    }
    NSMutableData *data = [NSMutableData data];
    [self.class enumerateGridOfSubpixelModels:^(float textColor, float backgroundColor, iTermSubpixelModel *model) {
        NSString *name = [NSString stringWithFormat:@"SubpixelModelGridBwGlyph.t_%02x.b_%02x.dat",
                          (int)textColor, (int)backgroundColor];
        NSURL *url = [folder URLByAppendingPathComponent:name];
        [model.table writeToURL:url atomically:NO];
        
        [data appendData:model.table];
    }];
    NSString *name = @"SubpixelModelGridComposite_Untransformed.dat";
    NSURL *url = [folder URLByAppendingPathComponent:name];
    [data writeToURL:url atomically:NO];
    
    name = @"SubpixelModelGridComposite_Transformed.dat";
    url = [folder URLByAppendingPathComponent:name];
    [[self.class transformedData:data] writeToURL:url atomically:NO];
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
