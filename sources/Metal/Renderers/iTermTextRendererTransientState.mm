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
#import "iTermTexturePage.h"
#import "iTermTexturePageCollection.h"
#import "NSMutableData+iTerm.h"

#include <map>

const vector_float4 iTermIMEColor = simd_make_float4(1, 1, 0, 1);
const vector_float4 iTermAnnotationUnderlineColor = simd_make_float4(1, 1, 0, 1);

namespace iTerm2 {
    class TexturePage;
}

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
    iTerm2::PIUArray<iTermTextPIU> _asciiPIUArrays[iTermPIUArraySize][iTermNumberOfPIUArrays];
    iTerm2::PIUArray<iTermTextPIU> _asciiOverflowArrays[iTermPIUArraySize][iTermNumberOfPIUArrays];

    // Array of PIUs for each texture page.
    std::map<iTerm2::TexturePage *, iTerm2::PIUArray<iTermTextPIU> *> _pius[iTermPIUArraySize];

    iTermPreciseTimerStats _stats[iTermTextRendererStatCount];
}

- (void)dealloc {
    for (size_t i = 0; i < iTermPIUArraySize; i++) {
        for (auto it = _pius[i].begin(); it != _pius[i].end(); it++) {
            delete it->second;
        }
    }
}

+ (NSString *)formatTextPIU:(iTermTextPIU)a {
    return [NSString stringWithFormat:
            @"offset=(%@, %@) "
            @"textureOffset=(%@, %@) "
            @"textColor=(%@, %@, %@, %@) "
            @"underlineStyle=%@ "
            @"underlineColor=(%@, %@, %@, %@)\n",
            @(a.offset.x),
            @(a.offset.y),
            @(a.textureOffset.x),
            @(a.textureOffset.y),
            @(a.textColor.x),
            @(a.textColor.y),
            @(a.textColor.z),
            @(a.textColor.w),
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

    @autoreleasepool {
        for (int k = 0; k < iTermPIUArraySize; k++) {
            NSMutableString *s = [NSMutableString string];
            for (auto entry : _pius[k]) {
                const iTerm2::TexturePage *texturePage = entry.first;
                iTerm2::PIUArray<iTermTextPIU> *piuArray = entry.second;
                [s appendFormat:@"Texture Page with texture %@:\n", texturePage->get_texture().label];
                if (piuArray) {
                    for (int j = 0; j < piuArray->size(); j++) {
                        iTermTextPIU &piu = piuArray->get(j);
                        [s appendString:[self.class formatTextPIU:piu]];
                    }
                }
            }
            NSString *name = @"non-ascii-pius.txt";
            if (k & iTermPIUArrayIndexUnderlined) {
                name = [@"underlined-" stringByAppendingString:name];
            }
            if (k & iTermPIUArrayIndexNotUnderlinedEmoji) {
                name = [@"emoji-" stringByAppendingString:name];
            }
            [s writeToURL:[folder URLByAppendingPathComponent:name] atomically:NO encoding:NSUTF8StringEncoding error:nil];
        }
    }

    NSString *s = [NSString stringWithFormat:@"backgroundTexture=%@\nasciiUnderlineDescriptor=%@\nnonAsciiUnderlineDescriptor=%@\nstrikethroughUnderlineDescriptor=%@",
                   _backgroundTexture,
                   iTermMetalUnderlineDescriptorDescription(&_asciiUnderlineDescriptor),
                   iTermMetalUnderlineDescriptorDescription(&_nonAsciiUnderlineDescriptor),
                   iTermMetalUnderlineDescriptorDescription(&_strikethroughUnderlineDescriptor)];
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
    // ASCII glyphs are shifted by self.asciiOffset.height pixels relative to non-ascii glyphs.
    // The underlines would come along with them so we adjust them here. Issue 10168.
    iTermMetalUnderlineDescriptor adjustedASCIIUnderlineDescriptor = _asciiUnderlineDescriptor;
    adjustedASCIIUnderlineDescriptor.offset -= self.asciiOffset.height / self.configuration.scale;
    vector_uint2 augmentedGlyphSize = CGSizeToVectorUInt2(_asciiTextureGroup.glyphSize);
    if (iTermTextIsMonochrome()) {
        // There is only a center part for ASCII on Mojave because the glyph size is increased to contain the largest ASCII glyph, notwithstanding the ascii offset.
        // If we don't account for ascii offset here than glyphs that spill into the right (such as Italic often does) can be truncated.
        augmentedGlyphSize.x += self.asciiOffset.width;
        augmentedGlyphSize.y += self.asciiOffset.height;
    }
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
                      augmentedGlyphSize,
                      adjustedASCIIUnderlineDescriptor,
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
    size_t sum = 0;
    for (size_t k = 0; k < iTermPIUArraySize; k++) {
        for (auto const &mapPair : _pius[k]) {
            const iTerm2::TexturePage *const &texturePage = mapPair.first;
            const iTerm2::PIUArray<iTermTextPIU> *const &piuArray = mapPair.second;

            for (size_t i = 0; i < piuArray->get_number_of_segments(); i++) {
                const size_t count = piuArray->size_of_segment(i);
                if (count > 0) {
                    sum += count;
                    block(piuArray->start_of_segment(i),
                          count,
                          texturePage->get_texture(),
                          texturePage->get_atlas_size(),
                          texturePage->get_cell_size(),
                          _nonAsciiUnderlineDescriptor,
                          _strikethroughUnderlineDescriptor,
                          !!(k & iTermPIUArrayIndexUnderlined),
                          !!(k & iTermPIUArrayIndexNotUnderlinedEmoji));
                }
            }
        }
    }
    return sum;
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
    for (int k = 0; k < iTermPIUArraySize; k++) {
        for (auto pair : _pius[k]) {
            iTerm2::TexturePage *page = pair.first;
            page->record_use();
        }
    }
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
                                                                    iTermMetalGlyphAttributesUnderline underlineStyle,
                                                                    vector_float4 underlineColor) {
    piu->offset = simd_make_float2(x * cellWidth + asciiOffset.width,
                                   asciiOffset.height);
    const int index = iTermASCIITextureIndexOfCode(code, offset);
    MTLOrigin origin = iTermTextureArrayOffsetForIndex(texture.textureArray, index);
    piu->textureOffset = (vector_float2){ origin.x * w, origin.y * h };
    piu->textColor = textColor;
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
        if (attributes[x].hasUnderlineColor) {
            underlineColor = attributes[x].underlineColor;
        } else {
            underlineColor = _asciiUnderlineDescriptor.color.w > 0 ? _asciiUnderlineDescriptor.color : attributes[x].foregroundColor;
        }
    }

    iTermMetalGlyphAttributesUnderline underlineStyle = attributes[x].underlineStyle;
    vector_float4 textColor = attributes[x].foregroundColor;
    if (inMarkedRange) {
        // Marked range gets a yellow underline.
        underlineStyle = iTermMetalGlyphAttributesUnderlineSingle;
    }

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
                                                    underlineStyle,
                                                    underlineColor);
        return;
    }
    // Pre-10.14, ASCII glyphs can get chopped up into multiple parts. This is necessary so subpixel AA will work right.
    
    // Add PIU for left overflow
    if (parts & iTermASCIITexturePartsLeft) {
        if (x > 0) {
            // Normal case
            iTermTextRendererTransientStateAddASCIIPart(_asciiOverflowArrays[outerPIUIndex][asciiAttrs].get_next(),
                                                        code,
                                                        w,
                                                        h,
                                                        texture,
                                                        cellWidth,
                                                        x - 1,
                                                        asciiOffset,
                                                        iTermASCIITextureOffsetLeft,
                                                        textColor,
                                                        iTermMetalGlyphAttributesUnderlineNone,
                                                        underlineColor);
        } else {
            // Intrusion into left margin
            iTermTextRendererTransientStateAddASCIIPart(_asciiOverflowArrays[outerPIUIndex][asciiAttrs].get_next(),
                                                        code,
                                                        w,
                                                        h,
                                                        texture,
                                                        cellWidth,
                                                        x - 1,
                                                        asciiOffset,
                                                        iTermASCIITextureOffsetLeft,
                                                        textColor,
                                                        iTermMetalGlyphAttributesUnderlineNone,
                                                        underlineColor);
        }
    }

    // Add PIU for center part, which is always present
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
                                                underlineStyle,
                                                underlineColor);
    // Add PIU for right overflow
    if (parts & iTermASCIITexturePartsRight) {
        const int lastColumn = self.cellConfiguration.gridSize.width - 1;
        if (x < lastColumn) {
            // Normal case
            iTermTextRendererTransientStateAddASCIIPart(_asciiOverflowArrays[outerPIUIndex][asciiAttrs].get_next(),
                                                        code,
                                                        w,
                                                        h,
                                                        texture,
                                                        cellWidth,
                                                        x + 1,
                                                        asciiOffset,
                                                        iTermASCIITextureOffsetRight,
                                                        attributes[x].foregroundColor,
                                                        iTermMetalGlyphAttributesUnderlineNone,
                                                        underlineColor);
        } else {
            // Intrusion into right margin
            iTermTextRendererTransientStateAddASCIIPart(_asciiOverflowArrays[outerPIUIndex][asciiAttrs].get_next(),
                                                        code,
                                                        w,
                                                        h,
                                                        texture,
                                                        cellWidth,
                                                        x + 1,
                                                        asciiOffset,
                                                        iTermASCIITextureOffsetRight,
                                                        attributes[x].foregroundColor,
                                                        iTermMetalGlyphAttributesUnderlineNone,
                                                        underlineColor);
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
    const iTermMetalGlyphKey *glyphKeys = (iTermMetalGlyphKey *)glyphKeysData.bytes;
    const iTermMetalGlyphAttributes *attributes = (iTermMetalGlyphAttributes *)attributesData.bytes;
    vector_float2 reciprocalAsciiAtlasSize = 1.0 / _asciiTextureGroup.atlasSize;
    CGSize glyphSize = self.cellConfiguration.glyphSize;
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
        } else {
            // Non-ASCII slower path
            const iTerm2::GlyphKey glyphKey(&glyphKeys[x]);
            std::vector<const iTerm2::GlyphEntry *> *entries = _texturePageCollectionSharedPointer.object->find(glyphKey);
            if (!entries) {
                entries = _texturePageCollectionSharedPointer.object->add(x, glyphKey, context, creation);
                if (!entries) {
                    continue;
                }
            } else if (entries->empty()) {
                continue;
            }
            const bool &hasAnnotation = attributes[x].annotation;
            const bool hasUnderline = attributes[x].underlineStyle != iTermMetalGlyphAttributesUnderlineNone;
            const iTerm2::GlyphEntry *firstGlyphEntry = (*entries)[0];
            const int outerPIUIndex = iTermOuterPIUIndex(hasAnnotation, hasUnderline, firstGlyphEntry->_is_emoji);
            for (auto entry : *entries) {
                auto it = _pius[outerPIUIndex].find(entry->_page);
                iTerm2::PIUArray<iTermTextPIU> *array;
                if (it == _pius[outerPIUIndex].end()) {
                    array = _pius[outerPIUIndex][entry->_page] = new iTerm2::PIUArray<iTermTextPIU>(_numberOfCells);
                } else {
                    array = it->second;
                }
                iTermTextPIU *piu = array->get_next();
                // Build the PIU
                const int &part = entry->_part;
                const int dx = iTermImagePartDX(part);
                const int dy = iTermImagePartDY(part);
                piu->offset = simd_make_float2(x * cellWidth + dx * glyphSize.width,
                                               -dy * glyphSize.height + yOffset);
                MTLOrigin origin = entry->get_origin();
                vector_float2 reciprocal_atlas_size = entry->_page->get_reciprocal_atlas_size();
                piu->textureOffset = simd_make_float2(origin.x * reciprocal_atlas_size.x,
                                                      origin.y * reciprocal_atlas_size.y);
                piu->textColor = attributes[x].foregroundColor;
                if (attributes[x].annotation) {
                    piu->underlineStyle = iTermMetalGlyphAttributesUnderlineSingle;
                    piu->underlineColor = iTermAnnotationUnderlineColor;
                } else if (inMarkedRange) {
                    piu->underlineStyle = iTermMetalGlyphAttributesUnderlineSingle;
                    piu->underlineColor = _nonAsciiUnderlineDescriptor.color.w > 1 ? _nonAsciiUnderlineDescriptor.color : piu->textColor;
                } else {
                    piu->underlineStyle = attributes[x].underlineStyle;
                    if (attributes[x].hasUnderlineColor) {
                        piu->underlineColor = attributes[x].underlineColor;
                    } else {
                        piu->underlineColor = _nonAsciiUnderlineDescriptor.color.w > 1 ? _nonAsciiUnderlineDescriptor.color : piu->textColor;
                    }
                }
                if (part != iTermTextureMapMiddleCharacterPart &&
                    part != iTermTextureMapMiddleCharacterPart + 1) {
                    // Only underline center part and its right neighbor of the character. There are weird artifacts otherwise,
                    // such as floating underlines (for parts above and below) or doubly drawn
                    // underlines.
                    piu->underlineStyle = iTermMetalGlyphAttributesUnderlineNone;
                }
            }
        }
        [glyphKeysData checkForOverrun2];
        [attributesData checkForOverrun2];
    }
    //DLog(@"END setGlyphKeysData for %@", self);
}

- (void)didComplete {
    DLog(@"BEGIN didComplete for %@", self);
    _texturePageCollectionSharedPointer.object->prune_if_needed();  // The static analyzer wrongly says this is a use-after-free.
    DLog(@"END didComplete");
}

- (nonnull NSMutableData *)modelData  {
    if (_modelData == nil) {
        _modelData = [[NSMutableData alloc] initWithUninitializedLength:sizeof(iTermTextPIU) * self.cellConfiguration.gridSize.width * self.cellConfiguration.gridSize.height];
    }
    return _modelData;
}

- (void)expireNonASCIIGlyphs {
    _texturePageCollectionSharedPointer.object->remove_all();
}

@end

