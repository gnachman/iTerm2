//
//  iTermASCIITextRenderer.m
//  iTerm2Shared
//
//  Created by George Nachman on 2/17/18.
//

#import "iTermASCIITextRenderer.h"

#import "iTermASCIITexture.h"
#import "iTermData.h"
#import "iTermTextRenderer.h"
#import "NSDictionary+iTerm.h"
#import "NSMutableData+iTerm.h"
#import "ScreenChar.h"

@implementation iTermASCIIRow
@end

@interface iTermASCIITextRendererTransientState()
@property (nonatomic, readonly) NSArray<iTermASCIIRow *> *rows;
@property (nonatomic, strong) iTermASCIITextureGroup *asciiTextureGroup;
@property (nonatomic, strong) iTermMetalBufferPool *configPool;
@property (nonatomic, strong) NSNumber *iteration;
@end

@implementation iTermASCIITextRendererTransientState {
    NSMutableArray<iTermASCIIRow *> *_rows;
}

- (NSString *)formatScreenChar:(screen_char_t)c {
    return [NSString stringWithFormat:@"[code=%@ fgMode=%@ foreground=%@ fgGreen=%@ fgBlue=%@ bgMode=%@ background=%@ bgGreen=%@ bgBlue=%@ complex=%@ bold=%@ faint=%@ italic=%@ blink=%@ underline=%@ image=%@ unused=%@ urlcode=%@]",
            @(c.code),
            @(c.foregroundColorMode),
            @(c.foregroundColor),
            @(c.fgGreen),
            @(c.fgBlue),
            @(c.backgroundColorMode),
            @(c.backgroundColor),
            @(c.bgGreen),
            @(c.bgBlue),
            @(c.complexChar),
            @(c.bold),
            @(c.faint),
            @(c.italic),
            @(c.blink),
            @(c.underline),
            @(c.image),
            @(c.unused),
            @(c.urlCode)];
}

- (void)writeDebugInfoToFolder:(NSURL *)folder {
    [super writeDebugInfoToFolder:folder];
    @autoreleasepool {
        int i = 0;
        for (iTermASCIIRow *row in _rows) {
            iTermData *data = row.screenChars;
            // Write out screen chars
            NSMutableString *s = [NSMutableString string];
            size_t size = data.length / sizeof(screen_char_t*);
            const screen_char_t *line = static_cast<const screen_char_t *>(data.bytes);
            for (int j = 0; j < size; j++) {
                [s appendString:[self.class formatScreenChar:line[j]]];
            }
            NSMutableString *name = [NSMutableString stringWithFormat:@"screen_char_t.%04d.txt", (int)i];
            [s writeToURL:[folder URLByAppendingPathComponent:name] atomically:NO encoding:NSUTF8StringEncoding error:nil];

            i++;
        }
    }
    NSString *s = [NSString stringWithFormat:@"backgroundTexture=%@\nasciiUnderlineDescriptor=%@\n",
                   _backgroundTexture,
                   iTermMetalUnderlineDescriptorDescription(&_underlineDescriptor)];
    [s writeToURL:[folder URLByAppendingPathComponent:@"state.txt"]
       atomically:NO
         encoding:NSUTF8StringEncoding
            error:NULL];
}

- (void)addRow:(iTermASCIIRow *)row {
    if (!_rows) {
        _rows = [NSMutableArray array];
    }
    [_rows addObject:row];
}

- (void)enumerateDraws:(void (^)(iTermASCIIRow *, int))block {
    [_rows enumerateObjectsUsingBlock:^(iTermASCIIRow * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        block(obj, idx);
    }];
}

@end

@implementation iTermASCIITextRenderer {
    iTermMetalCellRenderer *_cellRenderer;
    iTermMetalMixedSizeBufferPool *_screenCharPool;
    iTermASCIITextureGroup *_asciiTextureGroup;
    iTermMetalBufferPool *_dimensionsPool;
    iTermMetalBufferPool *_configPool;
    NSMutableDictionary<NSNumber *, id<MTLBuffer>> *_rowInfos;
    id<MTLBuffer> _models;
    id<MTLBuffer> _evensBuffer;
    id<MTLBuffer> _oddsBuffer;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        // This is here because I need a c++ place to stick it.
        static_assert(sizeof(screen_char_t) == SIZEOF_SCREEN_CHAR_T, "Screen char sizes unequal");

        // The maximum number of rows we'll handle efficiently
        static const NSInteger maxRows = 512;
        _cellRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                    vertexFunctionName:@"iTermASCIITextVertexShader"
                                                  fragmentFunctionName:@"iTermASCIITextFragmentShader"
                                                              blending:[iTermMetalBlending compositeSourceOver]
                                                        piuElementSize:sizeof(screen_char_t)
                                                   transientStateClass:[iTermASCIITextRendererTransientState class]];
        _screenCharPool = [[iTermMetalMixedSizeBufferPool alloc] initWithDevice:device
                                                                       capacity:maxRows * (iTermMetalDriverMaximumNumberOfFramesInFlight + 1)
                                                                           name:@"ASCII PIU lines"];
        _dimensionsPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermTextureDimensions)];
        _configPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermASCIITextConfiguration)];
        _rowInfos = [NSMutableDictionary dictionary];

        // Use a generic color model for blending. No need to use a buffer pool here because this is only
        // created once.
        NSData *subpixelModelData = [iTermTextRenderer subpixelModelData];
        _models = [_cellRenderer.device newBufferWithBytes:subpixelModelData.bytes
                                                    length:subpixelModelData.length
                                                   options:MTLResourceStorageModeManaged];

        int oddsValue = 1;
        int evensValue = 0;
        _evensBuffer = [_cellRenderer.device newBufferWithBytes:&evensValue length:sizeof(evensValue) options:MTLResourceStorageModeShared];
        _oddsBuffer = [_cellRenderer.device newBufferWithBytes:&oddsValue length:sizeof(oddsValue) options:MTLResourceStorageModeShared];
        _models.label = @"Subpixel models";
    }
    return self;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateASCIITextTS;
}

- (__kindof iTermMetalRendererTransientState * _Nonnull)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                                                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    __kindof iTermMetalCellRendererTransientState * _Nonnull transientState =
    [_cellRenderer createTransientStateForCellConfiguration:configuration
                                              commandBuffer:commandBuffer];
    [self initializeTransientState:transientState];
    return transientState;
}

- (id<MTLBuffer>)newQuadOfSize:(const vector_float2)size poolContext:(iTermMetalBufferPoolContext *)poolContext {
    const float big = 1.0 / 3.0;
    const float small = -1.0 / 3.0;
    const iTermVertex vertices[] = {
        // Pixel Positions             Texture Coordinates
        { { size.x,      0 }, { big, 0.f } },
        { {      0,      0 }, { small, 0.f } },
        { {      0, size.y }, { small, 1.f } },

        { { size.x,      0 }, { big, 0.f } },
        { {      0, size.y }, { small, 1.f } },
        { { size.x, size.y }, { big, 1.f } },
    };
    return [_cellRenderer.verticesPool requestBufferFromContext:poolContext
                                                      withBytes:vertices
                                                 checkIfChanged:YES];
}

- (void)initializeTransientState:(iTermASCIITextRendererTransientState *)tState {
    tState.asciiTextureGroup = _asciiTextureGroup;
}

- (id<MTLTexture>)newTemporaryTextureWithTexture:(id<MTLTexture>)backgroundTexture
                                          tState:(iTermASCIITextRendererTransientState *)tState {
    MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                                 width:tState.configuration.viewportSize.x
                                                                                                height:tState.configuration.viewportSize.y
                                                                                             mipmapped:NO];
    textureDescriptor.usage = (MTLTextureUsageShaderRead |
                               MTLTextureUsageShaderWrite |
                               MTLTextureUsageRenderTarget |
                               MTLTextureUsagePixelFormatView);
    return [_cellRenderer.device newTextureWithDescriptor:textureDescriptor];
}

- (void)createPipelineState:(iTermASCIITextRendererTransientState *)tState {
    tState.iteration = @(tState.iteration.intValue + 1);
    tState.pipelineState = [_cellRenderer pipelineStateForKey:[tState.iteration stringValue]];
}

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(__kindof iTermMetalCellRendererTransientState *)transientState {
    iTermASCIITextRendererTransientState *tState = transientState;

    static const iTermASCIITextureAttributes B = iTermASCIITextureAttributesBold;
    static const iTermASCIITextureAttributes I = iTermASCIITextureAttributesItalic;
    static const iTermASCIITextureAttributes T = iTermASCIITextureAttributesThinStrokes;

    id<MTLTexture> tempTexture = [self newTemporaryTextureWithTexture:tState.backgroundTexture
                                                                 tState:tState];
    renderEncoder = tState.blitBlock(tState.backgroundTexture, tempTexture);
    [self createPipelineState:tState];

    NSDictionary<NSNumber *, id<MTLTexture>> *textures =
    @{
      @(iTermTextureIndexPlain):          [tState.asciiTextureGroup asciiTextureForAttributes:0].textureArray.texture,
      @(iTermTextureIndexBold):           [tState.asciiTextureGroup asciiTextureForAttributes:B].textureArray.texture,
      @(iTermTextureIndexItalic):         [tState.asciiTextureGroup asciiTextureForAttributes:I].textureArray.texture,
      @(iTermTextureIndexBoldItalic):     [tState.asciiTextureGroup asciiTextureForAttributes:B | I].textureArray.texture,
      @(iTermTextureIndexThin):           [tState.asciiTextureGroup asciiTextureForAttributes:T].textureArray.texture,
      @(iTermTextureIndexThinBold):       [tState.asciiTextureGroup asciiTextureForAttributes:B | T].textureArray.texture,
      @(iTermTextureIndexThinItalic):     [tState.asciiTextureGroup asciiTextureForAttributes:I | T].textureArray.texture,
      @(iTermTextureIndexThinBoldItalic): [tState.asciiTextureGroup asciiTextureForAttributes:B | I | T].textureArray.texture,
      @(iTermTextureIndexBackground):     tempTexture,
    };

    id<MTLBuffer> textureDimensionsBuffer;
    iTermTextureDimensions textureDimensions = {
        .textureSize = tState.asciiTextureGroup.atlasSize,
        .cellSize = simd_make_float2(tState.cellConfiguration.cellSize.width, tState.cellConfiguration.cellSize.height),
        .underlineOffset = static_cast<float>(tState.cellConfiguration.cellSize.height - tState.underlineDescriptor.offset * tState.cellConfiguration.scale),
        .underlineThickness = static_cast<float>(tState.underlineDescriptor.thickness * tState.cellConfiguration.scale),
        .scale = static_cast<float>(tState.cellConfiguration.scale)
    };
    if (tState.cellConfiguration.usingIntermediatePass) {
        textures = [textures dictionaryBySettingObject:tState.backgroundTexture forKey:@(iTermTextureIndexBackground)];
    }
    textureDimensionsBuffer = [_dimensionsPool requestBufferFromContext:tState.poolContext
                                                              withBytes:&textureDimensions
                                                         checkIfChanged:YES];
    textureDimensionsBuffer.label = @"Texture dimensions";

#warning Optimize this by using same technique in iTermTetRenderer.mm
    const float vw = static_cast<float>(tState.cellConfiguration.cellSize.width * 3);
    const float vh = static_cast<float>(tState.cellConfiguration.cellSize.height);

    const float w = vw / textureDimensions.textureSize.x;
    const float h = vh / textureDimensions.textureSize.y;

    const iTermVertex vertices[] = {
        // Pixel Positions, Texture Coordinates
        { { vw,   0 }, { w, 0 } },
        { { 0,   0 }, { 0, 0 } },
        { { 0,  vh }, { 0, h } },

        { { vw,  0 }, { w, 0 } },
        { { 0,  vh }, { 0, h } },
        { { vw, vh }, { w, h } },
    };
    tState.vertexBuffer = [_cellRenderer.device newBufferWithBytes:vertices length:sizeof(vertices) options:MTLResourceStorageModeShared];
// END SHITTY SLOW CODE

    iTermASCIITextConfiguration config = {
        .gridSize = simd_make_uint2(tState.cellConfiguration.gridSize.width,
                                    tState.cellConfiguration.gridSize.height),
        .cellSize = simd_make_float2(tState.cellConfiguration.cellSize.width,
                                     tState.cellConfiguration.cellSize.height),
        .scale = static_cast<float>(tState.cellConfiguration.scale),
        .atlasSize = tState.asciiTextureGroup.atlasSize
    };
    id<MTLBuffer> configBuffer = [_configPool requestBufferFromContext:tState.poolContext
                                                             withBytes:&config
                                                        checkIfChanged:YES];
    [self drawPassEven:YES tState:tState config:configBuffer textureDimensions:textureDimensionsBuffer renderEncoder:renderEncoder textures:textures];
    renderEncoder = tState.blitBlock(tState.backgroundTexture, tempTexture);
    [self createPipelineState:tState];
    [self drawPassEven:NO tState:tState config:configBuffer textureDimensions:textureDimensionsBuffer renderEncoder:renderEncoder textures:textures];
}

- (void)drawPassEven:(BOOL)even
              tState:(iTermASCIITextRendererTransientState *)tState
              config:(id<MTLBuffer>)configBuffer
   textureDimensions:(id<MTLBuffer>)textureDimensionsBuffer
       renderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
            textures:(NSDictionary<NSNumber *, id<MTLTexture>> *)textures {
    [tState enumerateDraws:^(iTermASCIIRow *row, int line) {
        id<MTLBuffer> screenChars = [_screenCharPool requestBufferFromContext:tState.poolContext
                                                                         size:row.screenChars.length
                                                                        bytes:row.screenChars.bytes];
        NSDictionary<NSNumber *, id<MTLBuffer>> *vertexBuffers = @{
              @(iTermVertexInputIndexVertices): tState.vertexBuffer,
              @(iTermVertexInputIndexPerInstanceUniforms): screenChars,
              @(iTermVertexInputIndexOffset): tState.offsetBuffer,
              @(iTermVertexInputCellColors): tState.colorsBuffer,
              @(iTermVertexInputIndexASCIITextConfiguration): configBuffer,
              @(iTermVertexInputIndexASCIITextRowInfo): [self rowInfoBufferForLine:line tState:tState] };

        [_cellRenderer drawWithTransientState:tState
                                renderEncoder:renderEncoder
                             numberOfVertices:6
                                 numberOfPIUs:row.screenChars.length / sizeof(screen_char_t)
                                vertexBuffers:[vertexBuffers dictionaryBySettingObject:even ? _evensBuffer : _oddsBuffer forKey:@(iTermVertexInputMask)]
                              fragmentBuffers:@{ @(iTermFragmentBufferIndexColorModels): _models,
                                                 @(iTermFragmentInputIndexTextureDimensions): textureDimensionsBuffer }
                                     textures:textures];
    }];
}

- (id<MTLBuffer>)rowInfoBufferForLine:(int)line tState:(iTermASCIITextRendererTransientState *)tState {
    id<MTLBuffer> rowInfoBuffer = _rowInfos[@(line)];
    if (!rowInfoBuffer) {
        iTermASCIIRowInfo rowInfo = {
            .row = line,
            .debugX = (line == tState.debugCoord.y) ? tState.debugCoord.x : -1
        };
        rowInfoBuffer = [_cellRenderer.device newBufferWithBytes:&rowInfo
                                                          length:sizeof(rowInfo)
                                                         options:MTLResourceStorageModeShared];
        _rowInfos[@(line)] = rowInfoBuffer;
    }
    return rowInfoBuffer;
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


@end
