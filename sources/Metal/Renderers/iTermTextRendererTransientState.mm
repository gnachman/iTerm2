//
//  iTermTextRendererTransientState.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/22/17.
//

#import "FutureMethods.h"
#import "iTermTextRendererTransientState.h"
#import "iTermTextRendererTransientState+Private.h"
#import "iTermPIUArray.h"
#import "iTermSubpixelModelBuilder.h"
#import "NSMutableData+iTerm.h"

#include <map>

const vector_float4 iTermIMEColor = simd_make_float4(1, 1, 0, 1);
const vector_float4 iTermAnnotationUnderlineColor = simd_make_float4(1, 1, 0, 1);

typedef struct {
    size_t piu_index;
    int x;
    int y;
    int outerPIUIndex;
} iTermTextFixup;

// text color component, background color component
typedef std::pair<unsigned char, unsigned char> iTermColorComponentPair;

static vector_uint2 CGSizeToVectorUInt2(const CGSize &size) {
    return simd_make_uint2(size.width, size.height);
}

static const size_t iTermPIUArrayIndexNotUnderlined = 0;
static const size_t iTermPIUArrayIndexUnderlined = 1;  // This can be used as the Underlined bit in this bitmask
static const size_t iTermPIUArrayIndexNotUnderlinedEmoji = 2;  // This can be used as the Emoji bit in this bitmask
static const size_t iTermPIUArrayIndexUnderlinedEmoji = 3;
static const size_t iTermPIUArraySize = 4;

static const size_t iTermNumberOfPIUArrays = iTermASCIITextureAttributesMax * 2;

@implementation iTermTextRendererTransientState {
    // Data's bytes contains a C array of iTermMetalBackgroundColorRLE with background colors.
    NSMutableArray<iTermData *> *_backgroundColorRLEDataArray;

    // Color models for this frame. Only used when there's no intermediate texture.
    NSMutableData *_colorModels;

    // Key is text, background color component. Value is color model number (0 is 1st, 1 is 2nd, etc)
    // and you can multiply the color model number by 256 to get its starting point in _colorModels.
    // Only used when there's no intermediate texture.
    std::map<iTermColorComponentPair, int> *_colorModelIndexes;

    iTerm2::PIUArray<iTermTextPIU> _asciiPIUArrays[iTermPIUArraySize][iTermNumberOfPIUArrays];
    iTerm2::PIUArray<iTermTextPIU> _asciiOverflowArrays[iTermPIUArraySize][iTermNumberOfPIUArrays];

    iTermPreciseTimerStats _stats[iTermTextRendererStatCount];

    vector_float4 _lastTextColor, _lastBackgroundColor;
    vector_int3 _lastColorModelIndex;
}

NS_INLINE vector_int3 GetColorModelIndexForPIU(iTermTextRendererTransientState *self, iTermTextPIU *piu) {
    if (simd_equal(piu->textColor, self->_lastTextColor) &&
        simd_equal(piu->backgroundColor, self->_lastBackgroundColor)) {
        return self->_lastColorModelIndex;
    } else {
        vector_int3 result = SlowGetColorModelIndexForPIU(self, piu);
        self->_lastTextColor = piu->textColor;
        self->_lastBackgroundColor = piu->backgroundColor;
        self->_lastColorModelIndex = result;
        return result;
    }
}

- (instancetype)initWithConfiguration:(__kindof iTermRenderConfiguration *)configuration {
    self = [super initWithConfiguration:configuration];
    if (self) {
        _backgroundColorRLEDataArray = [NSMutableArray array];
        iTermCellRenderConfiguration *cellConfiguration = configuration;
        if (!cellConfiguration.usingIntermediatePass) {
            _colorModels = [NSMutableData data];
            _colorModelIndexes = new std::map<iTermColorComponentPair, int>();
            _lastTextColor = _lastBackgroundColor = simd_make_float4(-1, -1, -1, -1);
        }
    }
    return self;
}

- (void)dealloc {
    if (_colorModelIndexes) {
        delete _colorModelIndexes;
    }
}

- (void)setDisableIndividualColorModels:(BOOL)disableIndividualColorModels NS_DEPRECATED_MAC(10_12, 10_14) {
    _disableIndividualColorModels = disableIndividualColorModels;
    if (disableIndividualColorModels) {
        _colorModels = nil;
        _colorModelIndexes = nil;
    }
}

+ (NSString *)formatTextPIU:(iTermTextPIU)a {
    return [NSString stringWithFormat:
            @"offset=(%@, %@) "
            @"textureOffset=(%@, %@) "
            @"backgroundColor=(%@, %@, %@, %@) "
            @"textColor=(%@, %@, %@, %@) "
            @"colorModelIndex=(%@, %@, %@) "
            @"underlineStyle=%@ "
            @"underlineColor=(%@, %@, %@, %@)\n",
            @(a.offset.x),
            @(a.offset.y),
            @(a.textureOffset.x),
            @(a.textureOffset.y),
            @(a.backgroundColor.x),
            @(a.backgroundColor.y),
            @(a.backgroundColor.z),
            @(a.backgroundColor.w),
            @(a.textColor.x),
            @(a.textColor.y),
            @(a.textColor.z),
            @(a.textColor.w),
            @(a.colorModelIndex.x),
            @(a.colorModelIndex.y),
            @(a.colorModelIndex.z),
            @(a.underlineStyle),
            @(a.underlineColor.x),
            @(a.underlineColor.y),
            @(a.underlineColor.z),
            @(a.underlineColor.w)];
}

- (void)writeDebugInfoToFolder:(NSURL *)folder {
    [super writeDebugInfoToFolder:folder];

    [_modelData writeToURL:[folder URLByAppendingPathComponent:@"model.bin"] atomically:NO];

    @autoreleasepool {
        NSMutableString *s = [NSMutableString string];
        [_backgroundColorRLEDataArray enumerateObjectsUsingBlock:^(iTermData * _Nonnull data, NSUInteger idx, BOOL * _Nonnull stop) {
            const iTermMetalBackgroundColorRLE *rle = (const iTermMetalBackgroundColorRLE *)data.bytes;
            [s appendFormat:@"%4d: %@\n", (int)idx, iTermMetalBackgroundColorRLEDescription(rle)];
        }];
        [s writeToURL:[folder URLByAppendingPathComponent:@"backgroundColors.txt"] atomically:NO encoding:NSUTF8StringEncoding error:nil];
    }

    [_colorModels writeToURL:[folder URLByAppendingPathComponent:@"colorModels.bin"] atomically:NO];

    if (_colorModelIndexes) {
        @autoreleasepool {
            NSMutableString *s = [NSMutableString string];
            for (auto entry : *_colorModelIndexes) {
                [s appendFormat:@"(%@, %@) -> %@\n",
                 @(entry.first.first),
                 @(entry.first.second),
                 @(entry.second)];
            }
            [s writeToURL:[folder URLByAppendingPathComponent:@"colorModelIndexes.txt"] atomically:NO encoding:NSUTF8StringEncoding error:nil];
        }
    }

    @autoreleasepool {
        for (int k = 0; k < iTermPIUArraySize; k++) {
            for (int i = 0; i < sizeof(_asciiPIUArrays[k]) / sizeof(**_asciiPIUArrays); i++) {
                NSMutableString *s = [NSMutableString string];
                const int size = _asciiPIUArrays[k][i].size();
                for (int j = 0; j < size; j++) {
                    const iTermTextPIU &a = _asciiPIUArrays[k][i].get(j);
                    [s appendString:[self.class formatTextPIU:a]];
                }
                NSMutableString *name = [NSMutableString stringWithFormat:@"asciiPIUs.CenterPart."];
                if (i & iTermASCIITextureAttributesBold) {
                    [name appendString:@"B"];
                }
                if (i & iTermASCIITextureAttributesItalic) {
                    [name appendString:@"I"];
                }
                if (i & iTermASCIITextureAttributesThinStrokes) {
                    [name appendString:@"T"];
                }
                if (k == iTermPIUArrayIndexUnderlined ||
                    k == iTermPIUArrayIndexUnderlinedEmoji) {
                    [name appendString:@"U"];
                }
                if (k == iTermPIUArrayIndexNotUnderlinedEmoji ||
                    k == iTermPIUArrayIndexUnderlinedEmoji) {
                    [name appendString:@"E"];
                }
                [name appendString:@".txt"];
                [s writeToURL:[folder URLByAppendingPathComponent:name] atomically:NO encoding:NSUTF8StringEncoding error:nil];
            }
        }
    }

    @autoreleasepool {
        for (int k = 0; k < iTermPIUArraySize; k++) {
            for (int i = 0; i < sizeof(_asciiOverflowArrays[k]) / sizeof(**_asciiOverflowArrays); i++) {
                NSMutableString *s = [NSMutableString string];
                const int size = _asciiOverflowArrays[k][i].size();
                for (int j = 0; j < size; j++) {
                    const iTermTextPIU &a = _asciiOverflowArrays[k][i].get(j);
                    [s appendString:[self.class formatTextPIU:a]];
                }
                NSMutableString *name = [NSMutableString stringWithFormat:@"asciiPIUs.Overflow."];
                if (i & iTermASCIITextureAttributesBold) {
                    [name appendString:@"B"];
                }
                if (i & iTermASCIITextureAttributesItalic) {
                    [name appendString:@"I"];
                }
                if (i & iTermASCIITextureAttributesThinStrokes) {
                    [name appendString:@"T"];
                }
                [name appendString:@".txt"];
                [s writeToURL:[folder URLByAppendingPathComponent:name] atomically:NO encoding:NSUTF8StringEncoding error:nil];
            }
        }
    }

    if (_colorModelIndexes) {
        for (auto i : *_colorModelIndexes) {
            const iTermColorComponentPair p = i.first;
            [[iTermSubpixelModelBuilder sharedInstance] writeDebugDataToFolder:folder.path
                                                               foregroundColor:p.first / 255.0
                                                               backgroundColor:p.second / 255.0];
        }
    }

    NSString *s = [NSString stringWithFormat:@"backgroundTexture=%@\nasciiUnderlineDescriptor=%@\nnonAsciiUnderlineDescriptor=%@\nstrikethroughUnderlineDescriptor=%@\ndefaultBackgroundColor=(%@, %@, %@, %@)",
                   _backgroundTexture,
                   iTermMetalUnderlineDescriptorDescription(&_asciiUnderlineDescriptor),
                   iTermMetalUnderlineDescriptorDescription(&_nonAsciiUnderlineDescriptor),
                   iTermMetalUnderlineDescriptorDescription(&_strikethroughUnderlineDescriptor),
                   @(_defaultBackgroundColor.x),
                   @(_defaultBackgroundColor.y),
                   @(_defaultBackgroundColor.z),
                   @(_defaultBackgroundColor.w)];
    if (iTermTextIsMonochrome()) {} else {
        s = [s stringByAppendingFormat:@"\ndisableIndividualColorModels=%@", @(_disableIndividualColorModels)];
    }
    [s writeToURL:[folder URLByAppendingPathComponent:@"state.txt"]
       atomically:NO
         encoding:NSUTF8StringEncoding
            error:NULL];
}

- (iTermPreciseTimerStats *)stats {
    return _stats;
}

- (int)numberOfStats {
    return iTermTextRendererStatCount;
}

- (NSString *)nameForStat:(int)i {
    return [@[ @"text.newQuad",
               @"text.newPIU",
               @"text.newDims",
               @"text.info",
               @"text.subpixel",
               @"text.draw" ] objectAtIndex:i];
}

- (BOOL)haveAsciiOverflow {
    for (int k = 0; k < iTermPIUArraySize; k++) {
        for (int i = 0; i < iTermNumberOfPIUArrays; i++) {
            const int n = _asciiOverflowArrays[k][i].get_number_of_segments();
            if (n > 0) {
                for (int j = 0; j < n; j++) {
                    if (_asciiOverflowArrays[k][i].size_of_segment(j) > 0) {
                        return YES;
                    }
                }
            }
        }
    }
    return NO;
}

- (void)enumerateASCIIDrawsFromArrays:(iTerm2::PIUArray<iTermTextPIU> *)piuArrays
                           underlined:(BOOL)underlined
                                emoji:(BOOL)emoji
                                block:(void (^)(const iTermTextPIU *,
                                                NSInteger,
                                                id<MTLTexture>,
                                                vector_uint2,
                                                vector_uint2,
                                                iTermMetalUnderlineDescriptor,
                                                iTermMetalUnderlineDescriptor,
                                                BOOL underlined,
                                                BOOL emoji))block {
    for (int i = 0; i < iTermNumberOfPIUArrays; i++) {
        const int n = piuArrays[i].get_number_of_segments();
        iTermASCIITexture *asciiTexture = [_asciiTextureGroup asciiTextureForAttributes:(iTermASCIITextureAttributes)i];
        ITBetaAssert(asciiTexture, @"nil ascii texture for attributes %d", i);
        for (int j = 0; j < n; j++) {
            if (piuArrays[i].size_of_segment(j) > 0) {
                block(piuArrays[i].start_of_segment(j),
                      piuArrays[i].size_of_segment(j),
                      asciiTexture.textureArray.texture,
                      CGSizeToVectorUInt2(asciiTexture.textureArray.atlasSize),
                      CGSizeToVectorUInt2(_asciiTextureGroup.glyphSize),
                      _asciiUnderlineDescriptor,
                      _strikethroughUnderlineDescriptor,
                      underlined,
                      emoji);
            }
        }
    }
}

- (size_t)enumerateNonASCIIDraws:(void (^)(const iTermTextPIU *,
                                           NSInteger,
                                           id<MTLTexture>,
                                           vector_uint2,
                                           vector_uint2,
                                           iTermMetalUnderlineDescriptor,
                                           iTermMetalUnderlineDescriptor,
                                           BOOL underlined,
                                           BOOL emoji))block {
    return 0;
}

- (void)enumerateASCIIDrawsFromArrays:(iTerm2::PIUArray<iTermTextPIU>[iTermPIUArraySize][iTermNumberOfPIUArrays])piuArrays
                                block:(void (^)(const iTermTextPIU *, NSInteger, id<MTLTexture>, vector_uint2, vector_uint2, iTermMetalUnderlineDescriptor, iTermMetalUnderlineDescriptor, BOOL, BOOL))block {
    [self enumerateASCIIDrawsFromArrays:piuArrays[iTermPIUArrayIndexUnderlined]
                             underlined:true
                                  emoji:false
                                  block:block];
    [self enumerateASCIIDrawsFromArrays:piuArrays[iTermPIUArrayIndexUnderlinedEmoji]
                             underlined:true
                                  emoji:true
                                  block:block];
    [self enumerateASCIIDrawsFromArrays:piuArrays[iTermPIUArrayIndexNotUnderlined]
                             underlined:false
                                  emoji:false
                                  block:block];
    [self enumerateASCIIDrawsFromArrays:piuArrays[iTermPIUArrayIndexNotUnderlinedEmoji]
                             underlined:false
                                  emoji:true
                                  block:block];
}

- (void)enumerateDraws:(void (^)(const iTermTextPIU *,
                                 NSInteger,
                                 id<MTLTexture>,
                                 vector_uint2,
                                 vector_uint2,
                                 iTermMetalUnderlineDescriptor,
                                 iTermMetalUnderlineDescriptor,
                                 BOOL underlined,
                                 BOOL emoji))block
             copyBlock:(void (^)(void))copyBlock {
    [self enumerateNonASCIIDraws:block];
    [self enumerateASCIIDrawsFromArrays:_asciiPIUArrays block:block];
    if ([self haveAsciiOverflow]) {
        copyBlock();
        [self enumerateASCIIDrawsFromArrays:_asciiOverflowArrays block:block];
    }
}

- (void)willDraw {
    DLog(@"WILL DRAW %@", self);
    // Fix up the background color of parts of glyphs that are drawn outside their cell. Add to the
    // correct page's PIUs.
    DLog(@"END WILL DRAW");
}

NS_INLINE iTermTextPIU *iTermTextRendererTransientStateAddASCIIPart(iTermTextPIU *piu,
                                                                    char code,
                                                                    float w,
                                                                    float h,
                                                                    iTermASCIITexture *texture,
                                                                    float cellWidth,
                                                                    int x,
                                                                    CGSize asciiOffset,
                                                                    iTermASCIITextureOffset offset,
                                                                    vector_float4 textColor,
                                                                    vector_float4 backgroundColor,
                                                                    iTermMetalGlyphAttributesUnderline underlineStyle,
                                                                    vector_float4 underlineColor) {
    piu->offset = simd_make_float2(x * cellWidth + asciiOffset.width,
                                   asciiOffset.height);
    const int index = iTermASCIITextureIndexOfCode(code, offset);
    MTLOrigin origin = iTermTextureArrayOffsetForIndex(texture.textureArray, index);
    piu->textureOffset = (vector_float2){ origin.x * w, origin.y * h };
    piu->textColor = textColor;
    piu->backgroundColor = backgroundColor;
    piu->underlineStyle = underlineStyle;
    piu->underlineColor = underlineColor;
    return piu;
}

static inline int iTermOuterPIUIndex(const bool &annotation, const bool &underlined, const bool &emoji) {
    const int underlineBit = (annotation || underlined) ? iTermPIUArrayIndexUnderlined : 0;
    const int emojiBit = emoji ? iTermPIUArrayIndexNotUnderlinedEmoji : 0;
    return underlineBit | emojiBit;
}

- (void)addASCIICellToPIUsForCode:(char)code
                                x:(int)x
                           offset:(CGSize)asciiOffset
                                w:(float)w
                                h:(float)h
                        cellWidth:(float)cellWidth
                       asciiAttrs:(iTermASCIITextureAttributes)asciiAttrs
                       attributes:(const iTermMetalGlyphAttributes *)attributes
                    inMarkedRange:(BOOL)inMarkedRange {
    // When profiling, objc_retain and objc_release took 20% of the time in this function, which
    // is called super frequently. It should be safe not to retain the texture because the texture
    // group retains it. Once a texture is set in the group it won't be removed or replaced.
    __unsafe_unretained iTermASCIITexture *texture = _asciiTextureGroup->_textures[asciiAttrs];
    if (!texture) {
        texture = [_asciiTextureGroup asciiTextureForAttributes:asciiAttrs];
    }

    iTermASCIITextureParts parts = texture.parts[(size_t)code];
    vector_float4 underlineColor = { 0, 0, 0, 0 };

    const bool &hasAnnotation = attributes[x].annotation;
    const bool hasUnderline = attributes[x].underlineStyle != iTermMetalGlyphAttributesUnderlineNone;
    const int outerPIUIndex = iTermOuterPIUIndex(hasAnnotation, hasUnderline, false);
    if (hasAnnotation) {
        underlineColor = iTermAnnotationUnderlineColor;
    } else if (hasUnderline) {
        underlineColor = _asciiUnderlineDescriptor.color.w > 0 ? _asciiUnderlineDescriptor.color : attributes[x].foregroundColor;
    }

    iTermMetalGlyphAttributesUnderline underlineStyle = attributes[x].underlineStyle;
    vector_float4 textColor = attributes[x].foregroundColor;
    if (inMarkedRange) {
        // Marked range gets a yellow underline.
        underlineStyle = iTermMetalGlyphAttributesUnderlineSingle;
    }

    iTermTextPIU *piu;
    if (iTermTextIsMonochrome()) {
        // There is only a center part for ASCII on Mojave because the glyph size is increased to contain the largest ASCII glyph.
        iTermTextRendererTransientStateAddASCIIPart(_asciiPIUArrays[outerPIUIndex][asciiAttrs].get_next(),
                                                    code,
                                                    w,
                                                    h,
                                                    texture,
                                                    cellWidth,
                                                    x,
                                                    asciiOffset,
                                                    iTermASCIITextureOffsetCenter,
                                                    textColor,
                                                    attributes[x].backgroundColor,
                                                    underlineStyle,
                                                    underlineColor);
        return;
    }
    // Pre-10.14, ASCII glyphs can get chopped up into multiple parts. This is necessary so subpixel AA will work right.
    
    // Add PIU for left overflow
    if (parts & iTermASCIITexturePartsLeft) {
        if (x > 0) {
            // Normal case
            piu = iTermTextRendererTransientStateAddASCIIPart(_asciiOverflowArrays[outerPIUIndex][asciiAttrs].get_next(),
                                                              code,
                                                              w,
                                                              h,
                                                              texture,
                                                              cellWidth,
                                                              x - 1,
                                                              asciiOffset,
                                                              iTermASCIITextureOffsetLeft,
                                                              textColor,
                                                              attributes[x - 1].backgroundColor,
                                                              iTermMetalGlyphAttributesUnderlineNone,
                                                              underlineColor);
        } else {
            // Intrusion into left margin
            piu = iTermTextRendererTransientStateAddASCIIPart(_asciiOverflowArrays[outerPIUIndex][asciiAttrs].get_next(),
                                                              code,
                                                              w,
                                                              h,
                                                              texture,
                                                              cellWidth,
                                                              x - 1,
                                                              asciiOffset,
                                                              iTermASCIITextureOffsetLeft,
                                                              textColor,
                                                              _defaultBackgroundColor,
                                                              iTermMetalGlyphAttributesUnderlineNone,
                                                              underlineColor);
        }
        if (_colorModels) {
            piu->colorModelIndex = GetColorModelIndexForPIU(self, piu);
        }
    }

    // Add PIU for center part, which is always present
    piu = iTermTextRendererTransientStateAddASCIIPart(_asciiPIUArrays[outerPIUIndex][asciiAttrs].get_next(),
                                                      code,
                                                      w,
                                                      h,
                                                      texture,
                                                      cellWidth,
                                                      x,
                                                      asciiOffset,
                                                      iTermASCIITextureOffsetCenter,
                                                      textColor,
                                                      attributes[x].backgroundColor,
                                                      underlineStyle,
                                                      underlineColor);
    if (_colorModels) {
        piu->colorModelIndex = GetColorModelIndexForPIU(self, piu);
    }

    // Add PIU for right overflow
    if (parts & iTermASCIITexturePartsRight) {
        const int lastColumn = self.cellConfiguration.gridSize.width - 1;
        if (x < lastColumn) {
            // Normal case
            piu = iTermTextRendererTransientStateAddASCIIPart(_asciiOverflowArrays[outerPIUIndex][asciiAttrs].get_next(),
                                                              code,
                                                              w,
                                                              h,
                                                              texture,
                                                              cellWidth,
                                                              x + 1,
                                                              asciiOffset,
                                                              iTermASCIITextureOffsetRight,
                                                              attributes[x].foregroundColor,
                                                              attributes[x + 1].backgroundColor,
                                                              iTermMetalGlyphAttributesUnderlineNone,
                                                              underlineColor);
        } else {
            // Intrusion into right margin
            piu = iTermTextRendererTransientStateAddASCIIPart(_asciiOverflowArrays[outerPIUIndex][asciiAttrs].get_next(),
                                                              code,
                                                              w,
                                                              h,
                                                              texture,
                                                              cellWidth,
                                                              x + 1,
                                                              asciiOffset,
                                                              iTermASCIITextureOffsetRight,
                                                              attributes[x].foregroundColor,
                                                              _defaultBackgroundColor,
                                                              iTermMetalGlyphAttributesUnderlineNone,
                                                              underlineColor);
        }
        if (_colorModels) {
            piu->colorModelIndex = GetColorModelIndexForPIU(self, piu);
        }
    }
}

static inline BOOL GlyphKeyCanTakeASCIIFastPath(const iTermMetalGlyphKey &glyphKey) {
    return (glyphKey.code <= iTermASCIITextureMaximumCharacter &&
            glyphKey.code >= iTermASCIITextureMinimumCharacter &&
            !glyphKey.isComplex &&
            !glyphKey.boxDrawing);
}

- (void)setGlyphKeysData:(iTermGlyphKeyData *)glyphKeysData
                   count:(int)count
          attributesData:(iTermAttributesData *)attributesData
                     row:(int)row
  backgroundColorRLEData:(nonnull iTermData *)backgroundColorRLEData
       markedRangeOnLine:(NSRange)markedRangeOnLine
                 context:(iTermMetalBufferPoolContext *)context
                creation:(NSDictionary<NSNumber *, iTermCharacterBitmap *> *(NS_NOESCAPE ^)(int x, BOOL *emoji))creation {
    //DLog(@"BEGIN setGlyphKeysData for %@", self);
    ITDebugAssert(row == _backgroundColorRLEDataArray.count);
    [_backgroundColorRLEDataArray addObject:backgroundColorRLEData];
    const iTermMetalGlyphKey *glyphKeys = (iTermMetalGlyphKey *)glyphKeysData.bytes;
    const iTermMetalGlyphAttributes *attributes = (iTermMetalGlyphAttributes *)attributesData.bytes;
    vector_float2 reciprocalAsciiAtlasSize = 1.0 / _asciiTextureGroup.atlasSize;
    const float cellHeight = self.cellConfiguration.cellSize.height;
    const float cellWidth = self.cellConfiguration.cellSize.width;
    const float verticalShift = round((cellHeight - self.cellConfiguration.cellSizeWithoutSpacing.height) / (2 * self.configuration.scale)) * self.configuration.scale;
    const float yOffset = (self.cellConfiguration.gridSize.height - row - 1) * cellHeight + verticalShift;
    const float asciiYOffset = -self.asciiOffset.height;
    const float asciiXOffset = -self.asciiOffset.width;

    std::map<int, int> lastRelations;
    BOOL inMarkedRange = NO;

    for (int x = 0; x < count; x++) {
        if (x == markedRangeOnLine.location) {
            inMarkedRange = YES;
        } else if (inMarkedRange && x == NSMaxRange(markedRangeOnLine)) {
            inMarkedRange = NO;
        }

        if (!glyphKeys[x].drawable) {
            continue;
        }
        if (GlyphKeyCanTakeASCIIFastPath(glyphKeys[x])) {
            // ASCII fast path
            iTermASCIITextureAttributes asciiAttrs = iTermASCIITextureAttributesFromGlyphKeyTypeface(glyphKeys[x].typeface,
                                                                                                     glyphKeys[x].thinStrokes);
            [self addASCIICellToPIUsForCode:glyphKeys[x].code
                                          x:x
                                     offset:CGSizeMake(asciiXOffset, yOffset + asciiYOffset)
                                          w:reciprocalAsciiAtlasSize.x
                                          h:reciprocalAsciiAtlasSize.y
                                  cellWidth:cellWidth
                                 asciiAttrs:asciiAttrs
                                 attributes:attributes
                              inMarkedRange:inMarkedRange];
            [glyphKeysData checkForOverrun1];
            [attributesData checkForOverrun1];
        }
        [glyphKeysData checkForOverrun2];
        [attributesData checkForOverrun2];
    }
    //DLog(@"END setGlyphKeysData for %@", self);
}

static vector_int3 SlowGetColorModelIndexForPIU(iTermTextRendererTransientState *self, iTermTextPIU *piu) {
    iTermColorComponentPair redPair = std::make_pair(piu->textColor.x * 255,
                                                     piu->backgroundColor.x * 255);
    iTermColorComponentPair greenPair = std::make_pair(piu->textColor.y * 255,
                                                       piu->backgroundColor.y * 255);
    iTermColorComponentPair bluePair = std::make_pair(piu->textColor.z * 255,
                                                      piu->backgroundColor.z * 255);
    vector_int3 result;
    auto it = self->_colorModelIndexes->find(redPair);
    if (it == self->_colorModelIndexes->end()) {
        result.x = [self allocateColorModelForColorPair:redPair];
    } else {
        result.x = it->second;
    }
    it = self->_colorModelIndexes->find(greenPair);
    if (it == self->_colorModelIndexes->end()) {
        result.y = [self allocateColorModelForColorPair:greenPair];
    } else {
        result.y = it->second;
    }
    it = self->_colorModelIndexes->find(bluePair);
    if (it == self->_colorModelIndexes->end()) {
        result.z = [self allocateColorModelForColorPair:bluePair];
    } else {
        result.z = it->second;
    }

    return result;
}

- (int)allocateColorModelForColorPair:(iTermColorComponentPair)colorPair {
    int i = _colorModelIndexes->size();
    iTermSubpixelModel *model = [[iTermSubpixelModelBuilder sharedInstance] modelForForegroundColor:colorPair.first / 255.0
                                                                                    backgroundColor:colorPair.second / 255.0];
    [_colorModels appendData:model.table];
    (*_colorModelIndexes)[colorPair] = i;
    return i;
}

- (void)didComplete {
    DLog(@"BEGIN didComplete for %@", self);
    DLog(@"END didComplete");
}

- (nonnull NSMutableData *)modelData  {
    if (_modelData == nil) {
        _modelData = [[NSMutableData alloc] initWithUninitializedLength:sizeof(iTermTextPIU) * self.cellConfiguration.gridSize.width * self.cellConfiguration.gridSize.height];
    }
    return _modelData;
}

@end

