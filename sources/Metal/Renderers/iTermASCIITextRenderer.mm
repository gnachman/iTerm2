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
#import "NSMutableData+iTerm.h"
#import "ScreenChar.h"

@implementation iTermASCIIRow
@end

@interface iTermASCIITextRendererTransientState()
@property (nonatomic, readonly) NSArray<iTermASCIIRow *> *rows;
@property (nonatomic, strong) iTermASCIITextureGroup *asciiTextureGroup;
@property (nonatomic, readonly) id<MTLBuffer> configurationBuffer;
@property (nonatomic, strong) iTermMetalBufferPool *configPool;
@property (nonatomic, strong) NSData *colorMap;
@property (nonatomic, strong) iTermMetalMixedSizeBufferPool *bitmapPool;
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

            s = [NSMutableString string];
            [s appendFormat:@"Selected indices:\n"];
            [row.selectedIndices enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
                [s appendFormat:@"%@ ", @(idx)];
            }];

            [s appendFormat:@"\nFind matches:\n"];
            NSData *findMatches = row.findMatches;
            const unsigned char *bytes = static_cast<const unsigned char *>(findMatches.bytes);
            for (int j = 0; j < findMatches.length * 8; j++) {
                if (bytes[j / 8] & (1 << (j&7))) {
                    [s appendFormat:@"%@ ", @(j)];
                }
            }

            [s appendFormat:@"\nMarked range:\n%@", NSStringFromRange(row.markedRange)];
            [s appendFormat:@"\nUnderlined range:\n%@", NSStringFromRange(row.underlinedRange)];
            [s appendFormat:@"\nAnnotated indices:\n%@", row.annotatedIndices];
            name = [NSMutableString stringWithFormat:@"bitfields.%04d.txt", (int)i];
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

- (id<MTLBuffer>)configurationBuffer {
    iTermCellRenderConfiguration *cellConfig = self.cellConfiguration;
    iTermASCIITextConfiguration configuration = {
        .cellSize = simd_make_float2(cellConfig.cellSize.width,
                                     cellConfig.cellSize.height),
        .gridSize = simd_make_uint2(cellConfig.gridSize.width,
                                    cellConfig.gridSize.height),
        .scale = static_cast<float>(cellConfig.scale),
        .atlasSize = _asciiTextureGroup.atlasSize
    };
    return [_configPool requestBufferFromContext:self.poolContext
                                       withBytes:&configuration
                                  checkIfChanged:YES];
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

- (id<MTLBuffer>)bitArrayForIndexSet:(NSIndexSet *)indexSet {
    NSMutableData *temp = [NSMutableData dataWithLength:self.cellConfiguration.gridSize.width / 8 + 1];
    unsigned char *bytes = static_cast<unsigned char *>(temp.mutableBytes);
    [indexSet enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        bytes[idx / 8] |= (1 << (idx & 7));
    }];
    return [self bitArrayForData:temp];
}

- (id<MTLBuffer>)bitArrayForData:(NSData *)data {
    return [_bitmapPool requestBufferFromContext:self.poolContext size:data.length bytes:data.bytes];
}

- (id<MTLBuffer>)bitArrayForRange:(NSRange)range {
    return [self bitArrayForIndexSet:[NSIndexSet indexSetWithIndexesInRange:range]];
}

@end

@implementation iTermASCIITextRenderer {
    iTermMetalCellRenderer *_cellRenderer;
    iTermMetalMixedSizeBufferPool *_screenCharPool;
    iTermMetalBufferPool *_configurationPool;
    iTermASCIITextureGroup *_asciiTextureGroup;
    iTermMetalBufferPool *_dimensionsPool;
    iTermMetalMixedSizeBufferPool *_colorMapPool;
    iTermMetalMixedSizeBufferPool *_bitmapPool;
    NSMutableDictionary<NSNumber *, id<MTLBuffer>> *_rowInfos;
    id<MTLBuffer> _models;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
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
        _configurationPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermASCIITextConfiguration)];
        _colorMapPool = [[iTermMetalMixedSizeBufferPool alloc] initWithDevice:device
                                                                     capacity:iTermMetalDriverMaximumNumberOfFramesInFlight + 1
                                                                         name:@"Serialized Color Maps"];
        _bitmapPool = [[iTermMetalMixedSizeBufferPool alloc] initWithDevice:device
                                                                   capacity:maxRows * (iTermMetalDriverMaximumNumberOfFramesInFlight + 1)
                                                                       name:@"Bit fields"];
        _rowInfos = [NSMutableDictionary dictionary];

        // Use a generic color model for blending. No need to use a buffer pool here because this is only
        // created once.
        NSData *subpixelModelData = [iTermTextRenderer subpixelModelData];
        _models = [_cellRenderer.device newBufferWithBytes:subpixelModelData.bytes
                                                    length:subpixelModelData.length
                                                   options:MTLResourceStorageModeManaged];
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

- (void)initializeTransientState:(iTermASCIITextRendererTransientState *)tState {
    tState.vertexBuffer = [_cellRenderer newQuadOfSize:tState.cellConfiguration.cellSize
                                           poolContext:tState.poolContext];
    tState.vertexBuffer.label = @"Vertices";
    tState.asciiTextureGroup = _asciiTextureGroup;
    tState.configPool = _configurationPool;
    tState.colorMap = _colorMap;
    tState.bitmapPool = _bitmapPool;
}

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(__kindof iTermMetalCellRendererTransientState *)transientState {
    iTermASCIITextRendererTransientState *tState = transientState;

    static const iTermASCIITextureAttributes B = iTermASCIITextureAttributesBold;
    static const iTermASCIITextureAttributes I = iTermASCIITextureAttributesItalic;
    static const iTermASCIITextureAttributes T = iTermASCIITextureAttributesThinStrokes;
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
    };

    id<MTLBuffer> textureDimensionsBuffer;
    iTermTextureDimensions textureDimensions = {
        .textureSize = tState.asciiTextureGroup.atlasSize,
        .cellSize = simd_make_float2(tState.cellConfiguration.cellSize.width, tState.cellConfiguration.cellSize.height),
        .underlineOffset = static_cast<float>(tState.cellConfiguration.cellSize.height - tState.underlineDescriptor.offset * tState.cellConfiguration.scale),
        .underlineThickness = static_cast<float>(tState.underlineDescriptor.thickness * tState.cellConfiguration.scale),
        .scale = static_cast<float>(tState.cellConfiguration.scale)
    };
    textureDimensionsBuffer = [_dimensionsPool requestBufferFromContext:tState.poolContext
                                                              withBytes:&textureDimensions
                                                         checkIfChanged:YES];
    textureDimensionsBuffer.label = @"Texture dimensions";

#warning Optimize this by using same technique in iTermTetRenderer.mm
    const float vw = static_cast<float>(tState.cellConfiguration.cellSize.width);
    const float vh = static_cast<float>(tState.cellConfiguration.cellSize.height);

    const float w = vw / textureDimensions.textureSize.x;
    const float h = vh / textureDimensions.textureSize.y;

    const iTermVertex vertices[] = {
        // Pixel Positions, Texture Coordinates
        { { vw,  0 }, { w, 0 } },
        { { 0,   0 }, { 0, 0 } },
        { { 0,  vh }, { 0, h } },

        { { vw,  0 }, { w, 0 } },
        { { 0,  vh }, { 0, h } },
        { { vw, vh }, { w, h } },
    };
    tState.vertexBuffer = [_cellRenderer.device newBufferWithBytes:vertices length:sizeof(vertices) options:MTLResourceStorageModeShared];
// END SHITTY SLOW CODE

    id<MTLBuffer> colorMapBuffer = [_colorMapPool requestBufferFromContext:tState.poolContext
                                                                      size:tState.colorMap.length
                                                                     bytes:tState.colorMap.bytes];
    [tState enumerateDraws:^(iTermASCIIRow *row, int line) {
        id<MTLBuffer> screenChars = [_screenCharPool requestBufferFromContext:tState.poolContext
                                                                         size:row.screenChars.length
                                                                        bytes:row.screenChars.bytes];
        [_cellRenderer drawWithTransientState:tState
                                renderEncoder:renderEncoder
                             numberOfVertices:6
                                 numberOfPIUs:row.screenChars.length / sizeof(screen_char_t)
                                vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer,
                                                 @(iTermVertexInputIndexPerInstanceUniforms): screenChars,
                                                 @(iTermVertexInputIndexOffset): tState.offsetBuffer,
                                                 @(iTermVertexInputIndexASCIITextRowInfo): [self rowInfoBufferForLine:line],
                                                 @(iTermVertexInputIndexASCIITextConfiguration): tState.configurationBuffer,
                                                 @(iTermVertexInputIndexColorMap): colorMapBuffer,
                                                 @(iTermVertexInputSelectedIndices): [tState bitArrayForIndexSet:row.selectedIndices],
                                                 @(iTermVertexInputFindMatchIndices): [tState bitArrayForData:row.findMatches],
                                                 @(iTermVertexInputMarkedIndices): [tState bitArrayForRange:row.markedRange],
                                                 @(iTermVertexInputUnderlinedIndices): [tState bitArrayForRange:row.underlinedRange],
                                                 @(iTermVertexInputAnnotatedIndices): [tState bitArrayForIndexSet:row.annotatedIndices] }
                              fragmentBuffers:@{ @(iTermFragmentBufferIndexColorModels): _models,
                                                 @(iTermFragmentInputIndexTextureDimensions): textureDimensionsBuffer }
                                     textures:textures];
    }];
}

- (id<MTLBuffer>)rowInfoBufferForLine:(int)line {
    id<MTLBuffer> rowInfoBuffer = _rowInfos[@(line)];
    if (!rowInfoBuffer) {
        iTermASCIIRowInfo rowInfo = {
            .row = line
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
