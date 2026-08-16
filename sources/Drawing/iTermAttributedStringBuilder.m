//
//  iTermAttributedStringBuilder.m
//  iTerm2
//
//  Created by George Nachman on 10/31/24.
//

#import "iTermAttributedStringBuilder.h"

#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermBackgroundColorRun.h"
#import "iTermBoxDrawingBezierCurveFactory.h"
#import "iTermExternalAttributeIndex.h"
#import "iTermColorMap.h"
#import "iTermMutableAttributedStringBuilder.h"

#define likely(x) __builtin_expect(!!(x), 1)
#define unlikely(x) __builtin_expect(!!(x), 0)

typedef struct iTermTextColorContext {
    NSColor *lastUnprocessedColor;
    CGFloat dimmingAmount;
    CGFloat mutingAmount;
    BOOL hasSelectedText;
    iTermColorMap *colorMap;
    id<iTermAttributedStringBuilderDelegate> delegate;
    NSData *findMatches;
    BOOL reverseVideo;
    screen_char_t previousCharacterAttributes;
    BOOL havePreviousCharacterAttributes;
    NSColor *backgroundColor;
    NSColor *previousBackgroundColor;
    CGFloat minimumContrast;
    NSColor *previousForegroundColor;
} iTermTextColorContext;

typedef NS_ENUM(unsigned char, iTermCharacterAttributesUnderline) {
    iTermCharacterAttributesUnderlineNone,
    iTermCharacterAttributesUnderlineRegular,  // Single unless isURL, then double.
    iTermCharacterAttributesUnderlineCurly,
    iTermCharacterAttributesUnderlineDouble,
    iTermCharacterAttributesUnderlineDotted,
    iTermCharacterAttributesUnderlineDashed
};

// IMPORTANT: If you add a field here also update the comparison function
// shouldSegmentWithAttributes:imageAttributes:previousAttributes:previousImageAttributes:combinedAttributesChanged:
typedef struct {
    BOOL initialized;
    BOOL shouldAntiAlias;
    NSColor *foregroundColor;
    BOOL boxDrawing;
    BOOL contrastIneligible;
    NSFont *font;
    BOOL bold;
    BOOL faint;
    BOOL fakeBold;
    BOOL fakeItalic;
    iTermCharacterAttributesUnderline underlineType;
    BOOL strikethrough;
    BOOL isURL;
    NSInteger ligatureLevel;
    BOOL drawable;
    BOOL hasUnderlineColor;
    RTLStatus rtlStatus;
    VT100TerminalColorValue underlineColor;
} iTermCharacterAttributes;

NSString *const iTermAntiAliasAttribute = @"iTermAntiAliasAttribute";
NSString *const iTermBoldAttribute = @"iTermBoldAttribute";
NSString *const iTermFaintAttribute = @"iTermFaintAttribute";
NSString *const iTermFakeBoldAttribute = @"iTermFakeBoldAttribute";
NSString *const iTermFakeItalicAttribute = @"iTermFakeItalicAttribute";
NSString *const iTermImageCodeAttribute = @"iTermImageCodeAttribute";
NSString *const iTermImageColumnAttribute = @"iTermImageColumnAttribute";
NSString *const iTermImageLineAttribute = @"iTermImageLineAttribute";
NSString *const iTermImageDisplayColumnAttribute = @"iTermImageDisplayColumnAttribute";
NSString *const iTermIsBoxDrawingAttribute = @"iTermIsBoxDrawingAttribute";
NSString *const iTermUnderlineLengthAttribute = @"iTermUnderlineLengthAttribute";
NSString *const iTermHasUnderlineColorAttribute = @"iTermHasUnderlineColorAttribute";
NSString *const iTermUnderlineColorAttribute = @"iTermUnderlineColorAttribute";  // @[r,g,b,mode]
NSString *const iTermKittyImageRowAttribute = @"iTermKittyImageRowAttribute";
NSString *const iTermKittyImageColumnAttribute = @"iTermKittyImageColumnAttribute";
NSString *const iTermKittyImageIDAttribute = @"iTermKittyImageIDAttribute";
NSString *const iTermKittyImagePlacementIDAttribute = @"iTermKittyImagePlacementIDAttribute";

// Cache key capturing exactly the fields that determine
// -dictionaryForCharacterAttributes:'s output, so identical attribute
// combinations reuse one interned NSDictionary instead of rebuilding it per run.
// The foreground color uses value equality (the delegate hands back a fresh
// NSColor per cell, so pointer identity would never hit); the font uses pointer
// equality (the font table returns stable instances, and a distinct instance just
// costs a rebuild, never a wrong result) so hash and equality stay consistent.
@interface iTermCharAttrsDictKey : NSObject <NSCopying>
@end

@implementation iTermCharAttrsDictKey {
@public
    uint64_t _scalars;  // all scalar fields, including the underline color, packed
    NSColor *_fg;
    NSFont *_font;
    NSUInteger _hash;
}
- (NSUInteger)hash {
    return _hash;
}
- (BOOL)isEqual:(id)object {
    if (object == self) {
        return YES;
    }
    if (![object isKindOfClass:[iTermCharAttrsDictKey class]]) {
        return NO;
    }
    iTermCharAttrsDictKey *other = object;
    return (_scalars == other->_scalars &&
            _font == other->_font &&
            (_fg == other->_fg || [_fg isEqual:other->_fg]));
}
- (id)copyWithZone:(NSZone *)zone {
    // A real copy: a single instance is reused for lookups (mutated in place), so
    // the stored key must be a stable snapshot.
    iTermCharAttrsDictKey *copy = [[iTermCharAttrsDictKey alloc] init];
    copy->_scalars = _scalars;
    copy->_fg = _fg;
    copy->_font = _font;
    copy->_hash = _hash;
    return copy;
}
@end

static inline BOOL iTermCharacterAttributesUnderlineColorEqual(iTermCharacterAttributes *newAttributes,
                                                               iTermCharacterAttributes *previousAttributes) {
    if (newAttributes->hasUnderlineColor != previousAttributes->hasUnderlineColor) {
        return NO;
    }
    if (!newAttributes->hasUnderlineColor) {
        return YES;
    }
    // Field-by-field rather than memcmp: VT100TerminalColorValue's
    // BOOL hasDarkVariant is followed by ints, so padding bytes can spuriously
    // differ even when the logical value is identical, fragmenting runs.
    const VT100TerminalColorValue *a = &newAttributes->underlineColor;
    const VT100TerminalColorValue *b = &previousAttributes->underlineColor;
    return a->red == b->red &&
           a->green == b->green &&
           a->blue == b->blue &&
           a->mode == b->mode &&
           a->hasDarkVariant == b->hasDarkVariant &&
           a->redDark == b->redDark &&
           a->greenDark == b->greenDark &&
           a->blueDark == b->blueDark;
}

static NSColor *iTermTextDrawingHelperGetTextColor(screen_char_t *c,
                                                   iTermExternalAttribute *ea,
                                                   BOOL inUnderlinedRange,
                                                   int index,
                                                   iTermTextColorContext *context,
                                                   const iTermBackgroundColorRun *colorRun,
                                                   BOOL disableMinimumContrast) {
    NSColor *rawColor = nil;
    BOOL isMatch = NO;
    if (c->faint && colorRun && !context->backgroundColor) {
        context->backgroundColor = [context->delegate unprocessedColorForBackgroundRun:colorRun
                                                           enableBlending:YES];
    }
    const BOOL needsProcessing = context->backgroundColor && (context->minimumContrast > 0.001 ||
                                                              context->dimmingAmount > 0.001 ||
                                                              context->mutingAmount > 0.001 ||
                                                              c->faint);  // faint implies alpha<1 and is faster than getting the alpha component

    if (context->findMatches && !context->hasSelectedText) {
        // Test if this is a highlighted match from a find.
        int theIndex = index / 8;
        int mask = 1 << (index & 7);
        const char *matchBytes = context->findMatches.bytes;
        if (theIndex < [context->findMatches length] && (matchBytes[theIndex] & mask)) {
            isMatch = YES;
        }
    }

    if (isMatch) {
        // Black-on-yellow search result.
        NSColor *bgColor = [context->colorMap colorForKey:kColorMapMatch];
        rawColor = iTermTextDrawingHelperTextColorForMatch(bgColor);
        assert(rawColor);
        context->havePreviousCharacterAttributes = NO;
    } else if (inUnderlinedRange) {
        NSColor *hoverColor = [context->colorMap colorForKey:kColorMapLinkHover];
        NSColor *linkColor = hoverColor ?: [context->colorMap colorForKey:kColorMapLink];
        rawColor = linkColor;
        assert(rawColor);
        context->havePreviousCharacterAttributes = NO;
    } else if (context->hasSelectedText && context->delegate.useSelectedTextColor) {
        // Selected text.
        rawColor = [context->colorMap colorForKey:kColorMapSelectedText];
        assert(rawColor);
        context->havePreviousCharacterAttributes = NO;
    } else if (context->reverseVideo &&
               ((c->foregroundColor == ALTSEM_DEFAULT && c->foregroundColorMode == ColorModeAlternate) ||
                (c->foregroundColor == ALTSEM_CURSOR && c->foregroundColorMode == ColorModeAlternate))) {
        // Reverse video is on. Either is cursor or has default foreground color. Use
        // background color.
        rawColor = [context->colorMap colorForKey:kColorMapBackground];
        assert(rawColor);
        context->havePreviousCharacterAttributes = NO;
    } else {
        // For dual-mode (ColorModeExternal) cells, resolve the appearance variant
        // up front; subsequent cache comparisons use the resolved fields, so
        // consecutive External cells with different dark variants don't
        // falsely cache-hit.
        screen_char_t resolvedChar = *c;
        if (c->foregroundColorMode == ColorModeExternal && ea.dualModeForeground.valid) {
            const VT100TerminalColorValue v = [context->colorMap resolvedDualModeColor:ea.dualModeForeground];
            resolvedChar.foregroundColor = v.red;
            resolvedChar.fgGreen = v.green;
            resolvedChar.fgBlue = v.blue;
            resolvedChar.foregroundColorMode = v.mode;
        }
        if (!context->havePreviousCharacterAttributes ||
            resolvedChar.foregroundColor != context->previousCharacterAttributes.foregroundColor ||
            resolvedChar.fgGreen != context->previousCharacterAttributes.fgGreen ||
            resolvedChar.fgBlue != context->previousCharacterAttributes.fgBlue ||
            resolvedChar.foregroundColorMode != context->previousCharacterAttributes.foregroundColorMode ||
            c->bold != context->previousCharacterAttributes.bold ||
            c->faint != context->previousCharacterAttributes.faint ||
            !context->previousForegroundColor) {
            // "Normal" case for uncached text color. Recompute the unprocessed color from the character.
            context->previousCharacterAttributes = resolvedChar;
            context->havePreviousCharacterAttributes = YES;
            rawColor = [context->delegate colorForCode:resolvedChar.foregroundColor
                                                 green:resolvedChar.fgGreen
                                                  blue:resolvedChar.fgBlue
                                             colorMode:resolvedChar.foregroundColorMode
                                                  bold:c->bold
                                                 faint:c->faint
                                          isBackground:NO];
            assert(rawColor);
        } else if (needsProcessing && context->backgroundColor != context->previousBackgroundColor) {
            // Foreground attributes match prior cell, but background changed:
            // need to reprocess for contrast.
            rawColor = context->lastUnprocessedColor;
            assert(rawColor);
        } else {
            // Text color is unchanged. Either it's independent of the background color or the
            // background color has not changed.
            return context->previousForegroundColor;
        }
    }

    context->lastUnprocessedColor = rawColor;

    NSColor *result = nil;
    if (needsProcessing) {
        result = [context->colorMap processedTextColorForTextColor:rawColor
                                               overBackgroundColor:context->backgroundColor
                                            disableMinimumContrast:disableMinimumContrast];
    } else {
        result = rawColor;
    }
    context->previousForegroundColor = result;
    assert(result);
    return result;
}

static BOOL iTermTextDrawingHelperShouldAntiAlias(screen_char_t *c,
                                                  BOOL useNonAsciiFont,
                                                  BOOL asciiAntiAlias,
                                                  BOOL nonAsciiAntiAlias,
                                                  BOOL isRetina,
                                                  BOOL forceAntialiasingOnRetina) {
    if (isRetina && forceAntialiasingOnRetina) {
        return YES;
    }
    if (!useNonAsciiFont || (c->code < 128 && !c->complexChar)) {
        return asciiAntiAlias;
    } else {
        return nonAsciiAntiAlias;
    }
}

// Attribute-dictionary cache tuning.
enum {
    // Drop the cache wholesale once it holds this many entries, rather than paying
    // for LRU bookkeeping on a per-run hot path.
    kDictCacheMaxEntries = 1024,
    // Number of lookups to observe before deciding whether caching pays off.
    kDictCacheWarmupLookups = 2000,
    // Disable caching if fewer than 1/this of warmup lookups hit (i.e. <25%).
    kDictCacheMinHitRateDivisor = 4,
};

@implementation iTermAttributedStringBuilder {
    int _statsCount;
    // Interns -dictionaryForCharacterAttributes: results across runs and frames.
    // The builder is used serially (one per Metal per-frame state; rows built in
    // order), so no locking is needed. Bounded to avoid unbounded growth on
    // pathological unique-color content.
    NSMutableDictionary<iTermCharAttrsDictKey *, NSDictionary *> *_dictCache;
    iTermCharAttrsDictKey *_dictLookupKey;  // Reused for lookups to avoid per-run allocation.
    NSInteger _dictCacheLookups;
    NSInteger _dictCacheHits;
    BOOL _dictCacheDisabled;  // Set when the hit rate is too low to be worth the overhead.
}

- (instancetype)initWithStats:(iTermAttributedStringBuilderStatsPointers)stats {
    self = [super init];
    if (self) {
        _stats = stats;
    }
    return self;
}

- (void)setColorMap:(iTermColorMap *)colorMap
                    reverseVideo:(BOOL)reverseVideo
                 minimumContrast:(CGFloat)minimumContrast
                           zippy:(BOOL)zippy
         asciiLigaturesAvailable:(BOOL)asciiLigaturesAvailable
                  asciiLigatures:(BOOL)asciiLigatures
preferSpeedToFullLigatureSupport:(BOOL)preferSpeedToFullLigatureSupport
             lowFiCombiningMarks:(BOOL)lowFiCombiningMarks
                        cellSize:(NSSize)cellSize
            blinkingItemsVisible:(BOOL)blinkingItemsVisible
                    blinkAllowed:(BOOL)blinkAllowed
                 useNonAsciiFont:(BOOL)useNonAsciiFont
                  asciiAntiAlias:(BOOL)asciiAntiAlias
               nonAsciiAntiAlias:(BOOL)nonAsciiAntiAlias
                        isRetina:(BOOL)isRetina
       forceAntialiasingOnRetina:(BOOL)forceAntialiasingOnRetina
                     boldAllowed:(BOOL)boldAllowed
                   italicAllowed:(BOOL)italicAllowed
               nonAsciiLigatures:(BOOL)nonAsciiLigatures
        useNativePowerlineGlyphs:(BOOL)useNativePowerlineGlyphs
                    fontProvider:(id<FontProviderProtocol>)fontProvider
                       fontTable:(iTermFontTable *)fontTable
           delegate:(id<iTermAttributedStringBuilderDelegate>)delegate {
    _colorMap = colorMap;
    _reverseVideo = reverseVideo;
    _minimumContrast = minimumContrast;
    _zippy = zippy;
    _asciiLigaturesAvailable = asciiLigaturesAvailable;
    _asciiLigatures = asciiLigatures;
    _preferSpeedToFullLigatureSupport = preferSpeedToFullLigatureSupport;
    _lowFiCombiningMarks = lowFiCombiningMarks;
    _cellSize = cellSize;
    _blinkingItemsVisible = blinkingItemsVisible;
    _blinkAllowed = blinkAllowed;
    _useNonAsciiFont = useNonAsciiFont;
    _asciiAntiAlias = asciiAntiAlias;
    _nonAsciiAntiAlias = nonAsciiAntiAlias;
    _isRetina = isRetina;
    _forceAntialiasingOnRetina = forceAntialiasingOnRetina;
    _boldAllowed = boldAllowed;
    _italicAllowed = italicAllowed;
    _nonAsciiLigatures = nonAsciiLigatures;
    _useNativePowerlineGlyphs = useNativePowerlineGlyphs;
    _fontProvider = fontProvider;
    _fontTable = fontTable;
    _delegate = delegate;
}

- (NSArray<id<iTermAttributedString>> *)attributedStringsForLine:(const screen_char_t *)line
                                                        bidiInfo:(iTermBidiDisplayInfo *)bidiInfo
                                              externalAttributes:(id<iTermExternalAttributeIndexReading>)eaIndex
                                                           range:(NSRange)indexRange
                                                 hasSelectedText:(BOOL)hasSelectedText
                                                 backgroundColor:(NSColor *)backgroundColor
                                                  forceTextColor:(NSColor *)forceTextColor
                                                        colorRun:(const iTermBackgroundColorRun *)colorRun
                                                     findMatches:(NSData *)findMatches
                                                 underlinedRange:(NSRange)underlinedRange
                                                       positions:(CTVector(CGFloat) *)positions {
    NSMutableArray<id<iTermAttributedString>> *attributedStrings = [NSMutableArray array];
    iTermColorMap *colorMap = self.colorMap;
    iTermTextColorContext textColorContext = {
        .lastUnprocessedColor = nil,
        .dimmingAmount = colorMap.dimmingAmount,
        .mutingAmount = colorMap.mutingAmount,
        .hasSelectedText = hasSelectedText,
        .colorMap = self.colorMap,
        .delegate = _delegate,
        .findMatches = findMatches,
        .reverseVideo = _reverseVideo,
        .havePreviousCharacterAttributes = NO,
        .backgroundColor = backgroundColor,
        .minimumContrast = _minimumContrast,
        .previousForegroundColor = nil,
    };
    NSDictionary *previousImageAttributes = nil;
    iTermMutableAttributedStringBuilder *builder = [[iTermMutableAttributedStringBuilder alloc] initWithPreferSpeedToFullLigatureSupport:_preferSpeedToFullLigatureSupport
                                                                    lowFiCombiningMarks:_lowFiCombiningMarks];
    builder.hasBidi = bidiInfo != nil;
    builder.startColumn = indexRange.location;
    builder.zippy = self.zippy;
    builder.asciiLigaturesAvailable = _asciiLigaturesAvailable && _asciiLigatures;
    if (bidiInfo) {
        [builder enableExplicitDirectionControls];
    }
    iTermCharacterAttributes characterAttributes = { 0 };
    iTermCharacterAttributes previousCharacterAttributes = { 0 };
    int segmentLength = 0;
    BOOL previousDrawable = YES;
    screen_char_t predecessor = { 0 };
    BOOL lastCharacterImpartsEmojiPresentation = NO;
    iTermExternalAttribute *prevEa = nil;
    iTermKittyUnicodePlaceholderState kittyPlaceholderState;
    iTermKittyUnicodePlaceholderStateInit(&kittyPlaceholderState);

    // Only defined if not preferring speed to full ligature support.
    BOOL lastWasNull = NO;
    NSCharacterSet *emojiWithDefaultTextPresentation = [NSCharacterSet emojiWithDefaultTextPresentation];
    NSCharacterSet *emojiWithDefaultEmojiPresentationCharacterSet = [NSCharacterSet emojiWithDefaultEmojiPresentation];
    const int *bidiLUT = [bidiInfo lut];
    const int bidiLUTLength = bidiInfo.numberOfCells;
    const BOOL asciiLigatures = _asciiLigaturesAvailable && _asciiLigatures;
    const BOOL nonAsciiLigatures = _nonAsciiLigatures;

    for (int i = indexRange.location; i < NSMaxRange(indexRange); i++) {
        iTermPreciseTimerStatsStartTimer(_stats.attrsForChar);
        screen_char_t c = line[i];
        if (ScreenCharIsDWL_SPACER(c)) {
            // DWL_SPACERs are structural placeholders on double-width lines.
            // They occupy a cell but carry no content — skip entirely.
            continue;
        }
        if (!_preferSpeedToFullLigatureSupport) {
            if (c.code == 0) {
                if (!lastWasNull) {
                    c.code = ' ';
                }
                lastWasNull = YES;
            } else {
                lastWasNull = NO;
            }
        }
        unichar code = c.code;
        BOOL isComplex = c.complexChar;

        NSString *charAsString;

        CGFloat xPosition;
        int cellDraw;
        if (bidiLUT && i < bidiLUTLength) {
            cellDraw = bidiLUT[i];
        } else {
            cellDraw = i;
        }
        xPosition = cellDraw * _cellSize.width;

        if (isComplex && !c.image) {
            charAsString = ComplexCharToStr(code);

            if (i > indexRange.location &&
                builder.length > 0 &&
                !(!predecessor.complexChar && predecessor.code < 128) &&
                ComplexCharCodeIsSpacingCombiningMark(code)) {
                // Spacing combining marks get their own cell but get drawn together with their base
                // character which is assumed to be in the preceding cell so they combine properly.
                // This does not apply to ASCII characters, since they can never combine with a
                // spacing combining mark. That's done for performance in the GPU renderer to avoid
                // complicating its ASCII fastpath.
                int lastCellDraw;
                if (bidiLUT && i - 1 < bidiLUTLength) {
                    lastCellDraw = bidiLUT[i - i];
                } else {
                    lastCellDraw = i - 1;
                }
                [builder appendString:charAsString
                                  rtl:c.rtlStatus == RTLStatusRTL
                           sourceCell:i
                           drawInCell:lastCellDraw];
                const CGFloat lastValue = CTVectorGet(positions, CTVectorCount(positions) - 1);
                for (int i = 0; i < charAsString.length; i++) {
                    CTVectorAppend(positions, lastValue);
                }
                continue;
            }
            const UTF32Char base = [charAsString firstCharacter];
            if (lastCharacterImpartsEmojiPresentation && [emojiWithDefaultTextPresentation longCharacterIsMember:base] && ![charAsString containsString:@"\ufe0f"]) {
                // Prevent previous character's emoji presentation from making this one have an emoji presentation as well.
                // Leave lastCharacterImpartsEmojiPresentation set to YES intentionally.
                charAsString = [charAsString stringByAppendingString:@"\ufe0e"];
            } else {
                lastCharacterImpartsEmojiPresentation = [emojiWithDefaultEmojiPresentationCharacterSet longCharacterIsMember:base];
            }
        } else if (!c.image) {
            charAsString = nil;
            if (lastCharacterImpartsEmojiPresentation && [emojiWithDefaultTextPresentation characterIsMember:code]) {
                unichar chars[2] = { code, 0xfe0e };
                // Prevent previous character's emoji presentation from making this one have an emoji presentation as well.
                // See issue 9185
                charAsString = [NSString stringWithCharacters:chars length:2];
            } else if (code != DWC_RIGHT && code >= iTermMinimumDefaultEmojiPresentationCodePoint) {  // filter out small values for speed
                lastCharacterImpartsEmojiPresentation = [emojiWithDefaultEmojiPresentationCharacterSet characterIsMember:code];
            }
        } else {
            charAsString = nil;
        }

        iTermExternalAttribute *ea = eaIndex[i];
        const BOOL drawable = iTermTextDrawingHelperIsCharacterDrawable(&c,
                                                                        i > indexRange.location ? &predecessor : NULL,
                                                                        charAsString != nil,
                                                                        _blinkingItemsVisible,
                                                                        _blinkAllowed,
                                                                        _preferSpeedToFullLigatureSupport,
                                                                        ea.url != nil);
        predecessor = c;
        if (!drawable) {
            if ((characterAttributes.drawable && ScreenCharIsDWC_RIGHT(c)) ||
                (i > indexRange.location && !memcmp(&c, &line[i - 1], sizeof(c)))) {
                // This optimization short-circuits long runs of terminal nulls.
                ++segmentLength;
                characterAttributes.drawable = NO;
                continue;
            }
        }

        if (likely(underlinedRange.length == 0) &&
            likely(drawable == previousDrawable) &&
            likely(i > indexRange.location) &&
            [self character:&c withExtendedAttributes:ea isEquivalentToCharacter:&line[i-1] withExtendedAttributes:prevEa]) {
            ++segmentLength;
            iTermPreciseTimerStatsMeasureAndAccumulate(_stats.attrsForChar);
            if (drawable ||
                ((characterAttributes.underlineType ||
                  characterAttributes.strikethrough ||
                  characterAttributes.isURL) && segmentLength == 1)) {
                [self updateBuilder:builder
                         withString:drawable ? charAsString : @" "
                        orCharacter:code
                                rtl:c.rtlStatus == RTLStatusRTL
                          positions:positions
                             offset:xPosition
                         sourceCell:i
                         drawInCell:cellDraw];
            }
            continue;
        }
        previousDrawable = drawable;

        UTF32Char remapped = 0;
        [self getAttributesForCharacter:&c
                     externalAttributes:ea
                                atIndex:i
                         forceTextColor:forceTextColor
                         forceUnderline:NSLocationInRange(i, underlinedRange)
                               colorRun:colorRun
                               drawable:drawable
                       textColorContext:&textColorContext
                             attributes:&characterAttributes
                               remapped:&remapped];
        prevEa = ea;
        if (!c.image && remapped) {
            if (c.complexChar) {
                charAsString = [charAsString stringByReplacingBaseCharacterWith:remapped];
            } else if (remapped <= 0xffff) {
                code = remapped;
            } else {
                charAsString = [NSString stringWithLongCharacter:remapped];
            }
        }
        iTermPreciseTimerStatsMeasureAndAccumulate(_stats.attrsForChar);

        iTermPreciseTimerStatsStartTimer(_stats.shouldSegment);

        NSDictionary *imageAttributes = [self imageAttributesForCharacter:&c
                                                       externalAttributes:ea
                                                                    state:&kittyPlaceholderState
                                                            displayColumn:i];
        BOOL combinedAttributesChanged = NO;

        // I tried segmenting when fastpath eligibility changes so we can use the fast path as much
        // as possible. In the vimdiff benchmark it was neutral, and in the spam.cc benchmark it was
        // hugely negative (66->210 ms). The failed change was to segment when this is true:
        // builder.canUseFastPath != (!c.complexChar && iTermCharacterSupportsFastPath(code, _asciiLigaturesAvailable))
        if ([self shouldSegmentWithAttributes:&characterAttributes
                              imageAttributes:imageAttributes
                           previousAttributes:&previousCharacterAttributes
                      previousImageAttributes:previousImageAttributes
                     combinedAttributesChanged:&combinedAttributesChanged]) {
            iTermPreciseTimerStatsStartTimer(_stats.buildMutableAttributedString);
            builder.endColumn = i;
            id<iTermAttributedString> builtString = builder.attributedString;
            if (previousCharacterAttributes.underlineType ||
                previousCharacterAttributes.strikethrough ||
                previousCharacterAttributes.isURL) {
                [builtString addAttribute:iTermUnderlineLengthAttribute
                                    value:@(segmentLength)];
            }
            segmentLength = 0;
            iTermPreciseTimerStatsMeasureAndAccumulate(_stats.buildMutableAttributedString);

            if (builtString.length > 0) {
                [attributedStrings addObject:builtString];
            }
            builder = [[iTermMutableAttributedStringBuilder alloc] initWithPreferSpeedToFullLigatureSupport:_preferSpeedToFullLigatureSupport
                                                                    lowFiCombiningMarks:_lowFiCombiningMarks];
            builder.hasBidi = bidiInfo != nil;
            builder.startColumn = i;
            builder.zippy = self.zippy;
            builder.asciiLigaturesAvailable = asciiLigatures;
        }
        ++segmentLength;
        previousCharacterAttributes = characterAttributes;
        previousImageAttributes = [imageAttributes copy];
        iTermPreciseTimerStatsMeasureAndAccumulate(_stats.shouldSegment);

        iTermPreciseTimerStatsStartTimer(_stats.combineAttributes);
        if (combinedAttributesChanged) {  // This implies that we segmented
            NSDictionary *combinedAttributes = [self dictionaryForCharacterAttributes:&characterAttributes];
            if (imageAttributes) {
                combinedAttributes = [combinedAttributes dictionaryByMergingDictionary:imageAttributes];
            }
            [builder setAttributes:combinedAttributes];
            const BOOL isAscii = (!isComplex && c.code < 127);
            const BOOL ligatures = isAscii ? asciiLigatures : nonAsciiLigatures;
            if (ligatures) {
                // Force the slow path so we always have a chance of using stylistic alternatives or contextual alternates.
                // The fast path can't do it and there's no way to tell if a particular character will benefit from it.
                // These features are close enough to ligatures in my mental model that it makes sense, at least to me.
                // The settings UI reflects this by revealing the options button only when ligatures are enabled.
                if ([[NSFont castFrom:combinedAttributes[NSFontAttributeName]] it_hasStylisticAlternatives] ||
                    [[NSFont castFrom:combinedAttributes[NSFontAttributeName]] it_hasContextualAlternates]) {
                    [builder disableFastPath];
                }
            }
        }
        iTermPreciseTimerStatsMeasureAndAccumulate(_stats.combineAttributes);

        if (drawable || ((characterAttributes.underlineType ||
                          characterAttributes.strikethrough ||
                          characterAttributes.isURL) && segmentLength == 1)) {
            // Use " " when not drawable to prevent 0-length attributed strings when an underline/strikethrough is
            // present. If we get here's because there's an underline/strikethrough (which isn't quite obvious
            // from the if statement's condition).
            [self updateBuilder:builder
                     withString:drawable ? charAsString : @" "
                    orCharacter:code
                            rtl:c.rtlStatus == RTLStatusRTL
                      positions:positions
                         offset:xPosition
                     sourceCell:i
                     drawInCell:cellDraw];
        }
    }
    if (builder.length) {
        iTermPreciseTimerStatsStartTimer(_stats.buildMutableAttributedString);
        builder.endColumn = NSMaxRange(indexRange);
        id<iTermAttributedString> builtString = builder.attributedString;
        if (previousCharacterAttributes.underlineType ||
            previousCharacterAttributes.strikethrough ||
            previousCharacterAttributes.isURL) {
            [builtString addAttribute:iTermUnderlineLengthAttribute
                                            value:@(segmentLength)];
        }
        iTermPreciseTimerStatsMeasureAndAccumulate(_stats.buildMutableAttributedString);

        if (builtString.length > 0) {
            [attributedStrings addObject:builtString];
        }
    }

    return attributedStrings;
}

- (void)updateBuilder:(iTermMutableAttributedStringBuilder *)builder
           withString:(NSString *)string
          orCharacter:(unichar)code
                  rtl:(BOOL)rtl
            positions:(CTVector(CGFloat) *)positions
               offset:(CGFloat)offset
           sourceCell:(int)sourceCell
           drawInCell:(int)drawInCell {
    iTermPreciseTimerStatsStartTimer(_stats.updateBuilder);
    NSUInteger length;
    if (string) {
        [builder appendString:string rtl:rtl sourceCell:sourceCell drawInCell:drawInCell];
        length = string.length;
    } else {
        [builder appendCharacter:code rtl:rtl sourceCell:sourceCell drawInCell:drawInCell];
        length = 1;
    }
    iTermPreciseTimerStatsMeasureAndAccumulate(_stats.updateBuilder);

    iTermPreciseTimerStatsStartTimer(_stats.advances);
    // Append to positions.
    for (NSUInteger j = 0; j < length; j++) {
        CTVectorAppend(positions, offset);
    }
    iTermPreciseTimerStatsMeasureAndAccumulate(_stats.advances);
}

- (void)getAttributesForCharacter:(screen_char_t *)c
               externalAttributes:(iTermExternalAttribute *)ea
                          atIndex:(NSInteger)i
                   forceTextColor:(NSColor *)forceTextColor
                   forceUnderline:(BOOL)inUnderlinedRange
                         colorRun:(const iTermBackgroundColorRun *)colorRun
                         drawable:(BOOL)drawable
                 textColorContext:(iTermTextColorContext *)textColorContext
                       attributes:(iTermCharacterAttributes *)attributes
                         remapped:(UTF32Char *)remapped {
    attributes->initialized = YES;
    attributes->shouldAntiAlias = iTermTextDrawingHelperShouldAntiAlias(c,
                                                                        _useNonAsciiFont,
                                                                        _asciiAntiAlias,
                                                                        _nonAsciiAntiAlias,
                                                                        _isRetina,
                                                                        _forceAntialiasingOnRetina);
    const BOOL isComplex = c->complexChar;
    const unichar code = c->code;

    const UTF32Char longCode = isComplex ? BaseCharacterForComplexChar(code) : code;
    attributes->boxDrawing = [[iTermBoxDrawingBezierCurveFactory boxDrawingCharactersWithBezierPathsIncludingPowerline:_useNativePowerlineGlyphs] longCharacterIsMember:longCode];

    attributes->contrastIneligible = !isComplex && [[iTermBoxDrawingBezierCurveFactory blockDrawingCharacters] characterIsMember:code];

    if (forceTextColor) {
        attributes->foregroundColor = forceTextColor;
    } else {
        attributes->foregroundColor = iTermTextDrawingHelperGetTextColor(c,
                                                                         ea,
                                                                         inUnderlinedRange,
                                                                         i,
                                                                         textColorContext,
                                                                         colorRun,
                                                                         attributes->contrastIneligible);
    }

    attributes->bold = c->bold;
    attributes->faint = c->faint;
    attributes->fakeBold = c->bold;  // default value
    attributes->fakeItalic = c->italic;  // default value
    PTYFontInfo *fontInfo = [_fontProvider fontForCharacter:isComplex ? [CharToStr(code, isComplex) longCharacterAtIndex:0] : code
                                                useBoldFont:_boldAllowed
                                              useItalicFont:_italicAllowed
                                                 renderBold:&attributes->fakeBold
                                               renderItalic:&attributes->fakeItalic
                                                   remapped:remapped];

    attributes->font = fontInfo.font;
    attributes->ligatureLevel = fontInfo.ligatureLevel;
    if (_preferSpeedToFullLigatureSupport) {
        if (!c->complexChar &&
            iTermCharacterSupportsFastPath(c->code, _asciiLigaturesAvailable)) {
            attributes->ligatureLevel = 0;
        }
        if (c->complexChar || c->code > 128) {
            if (!_nonAsciiLigatures) {
                attributes->ligatureLevel = 0;
            }
        }
    }
    if (c->underline) {
        switch (ScreenCharGetUnderlineStyle(*c)) {
            case VT100UnderlineStyleSingle:
                attributes->underlineType = iTermCharacterAttributesUnderlineRegular;
                break;
            case VT100UnderlineStyleCurly:
                attributes->underlineType = iTermCharacterAttributesUnderlineCurly;
                break;
            case VT100UnderlineStyleDouble:
                attributes->underlineType = iTermCharacterAttributesUnderlineDouble;
                break;
            case VT100UnderlineStyleDotted:
                attributes->underlineType = iTermCharacterAttributesUnderlineDotted;
                break;
            case VT100UnderlineStyleDashed:
                attributes->underlineType = iTermCharacterAttributesUnderlineDashed;
                break;
        }
    } else if (inUnderlinedRange) {
        attributes->underlineType = iTermCharacterAttributesUnderlineRegular;
    } else {
        attributes->underlineType = iTermCharacterAttributesUnderlineNone;
    }
    attributes->strikethrough = c->strikethrough;
    attributes->drawable = drawable;
    attributes->rtlStatus = c->rtlStatus;
    if (ea) {
        attributes->hasUnderlineColor = ea.hasUnderlineColor;
        // Resolve any light/dark variant against the current background so
        // downstream code (drawing, copy-as-attributed-string) sees a single
        // concrete RGB.
        attributes->underlineColor = ea.hasUnderlineColor
            ? [textColorContext->colorMap resolvedColorValue:ea.underlineColor]
            : (VT100TerminalColorValue){ 0 };
        attributes->isURL = (ea.url != nil);
    } else {
        attributes->hasUnderlineColor = NO;
        attributes->isURL = NO;
        memset(&attributes->underlineColor, 0, sizeof(attributes->underlineColor));
    }
}

- (BOOL)shouldSegmentWithAttributes:(iTermCharacterAttributes *)newAttributes
                    imageAttributes:(NSDictionary *)imageAttributes
                 previousAttributes:(iTermCharacterAttributes *)previousAttributes
            previousImageAttributes:(NSDictionary *)previousImageAttributes
           combinedAttributesChanged:(BOOL *)combinedAttributesChanged {
    if (unlikely(!previousAttributes->initialized)) {
        // First char of first segment
        *combinedAttributesChanged = YES;
        return NO;
    }

    if (likely(!imageAttributes && !previousImageAttributes)) {
        // Not an image cell. Try to quickly check if the attributes are the same, which is the normal case.
        if (likely(!memcmp(previousAttributes, newAttributes, sizeof(*previousAttributes)))) {
            // Identical, byte-for-byte
            *combinedAttributesChanged = NO;
        } else {
            // Properly compare object fields
            *combinedAttributesChanged = (newAttributes->shouldAntiAlias != previousAttributes->shouldAntiAlias ||
                                          ![newAttributes->foregroundColor isEqual:previousAttributes->foregroundColor] ||
                                          newAttributes->boxDrawing != previousAttributes->boxDrawing ||
                                          newAttributes->contrastIneligible != previousAttributes ->contrastIneligible ||
                                          ![newAttributes->font isEqual:previousAttributes->font] ||
                                          newAttributes->ligatureLevel != previousAttributes->ligatureLevel ||
                                          newAttributes->bold != previousAttributes->bold ||
                                          newAttributes->faint != previousAttributes->faint ||
                                          newAttributes->fakeItalic != previousAttributes->fakeItalic ||
                                          newAttributes->underlineType != previousAttributes->underlineType ||
                                          newAttributes->strikethrough != previousAttributes->strikethrough ||
                                          newAttributes->isURL != previousAttributes->isURL ||
                                          newAttributes->drawable != previousAttributes->drawable ||
                                          newAttributes->rtlStatus != previousAttributes->rtlStatus ||
                                          !iTermCharacterAttributesUnderlineColorEqual(newAttributes, previousAttributes));
        }
        return *combinedAttributesChanged;
    } else if ((imageAttributes == nil) != (previousImageAttributes == nil)) {
        // Entering or exiting image
        *combinedAttributesChanged = YES;
        return YES;
    } else {
        // Going from image cell to image cell. Segment unless it's an adjacent image cell.
        *combinedAttributesChanged = YES;  // In theory an image cell should never repeat, so shortcut comparison.
        return ![self imageAttributes:imageAttributes followImageAttributes:previousImageAttributes];
    }
}

- (NSDictionary *)dictionaryForCharacterAttributes:(iTermCharacterAttributes *)attributes {
    // Fast path: return an interned dictionary if we have already built one for
    // this exact attribute combination. A single lookup key is reused (mutated in
    // place) so a cache hit costs no allocation.
    iTermCharAttrsDictKey *key = nil;
    if (!_dictCacheDisabled) {
        if (!_dictLookupKey) {
            _dictLookupKey = [[iTermCharAttrsDictKey alloc] init];
        }
        key = _dictLookupKey;
        // Bits 0-31: scalar flags/enums. Bits 32-63: underline color (only when
        // present), so a single word captures every field the dictionary depends on.
        uint64_t scalars = (((uint64_t)attributes->underlineType) |
                            ((uint64_t)attributes->strikethrough << 4) |
                            ((uint64_t)attributes->isURL << 5) |
                            ((uint64_t)attributes->shouldAntiAlias << 6) |
                            ((uint64_t)attributes->boxDrawing << 7) |
                            ((uint64_t)attributes->fakeBold << 8) |
                            ((uint64_t)attributes->bold << 9) |
                            ((uint64_t)attributes->faint << 10) |
                            ((uint64_t)attributes->fakeItalic << 11) |
                            ((uint64_t)attributes->hasUnderlineColor << 12) |
                            ((uint64_t)attributes->rtlStatus << 13) |
                            ((uint64_t)(attributes->ligatureLevel & 0xffff) << 16));
        if (attributes->hasUnderlineColor) {
            scalars |= (((uint64_t)(attributes->underlineColor.red & 0xff) << 32) |
                        ((uint64_t)(attributes->underlineColor.green & 0xff) << 40) |
                        ((uint64_t)(attributes->underlineColor.blue & 0xff) << 48) |
                        ((uint64_t)(attributes->underlineColor.mode & 0xff) << 56));
        }
        key->_scalars = scalars;
        key->_fg = attributes->foregroundColor;
        key->_font = attributes->font;
        // Cheap multiplicative mix of the packed scalars, the (value-based) color
        // hash, and the font pointer. Avoids the byte-loop hashing and the
        // per-lookup -[NSFont hash] message send.
        NSUInteger h = (NSUInteger)(scalars ^ (scalars >> 32));
        h = h * 1099511628211ULL + key->_fg.hash;
        h = h * 1099511628211ULL + (NSUInteger)(__bridge void *)key->_font;
        key->_hash = h;
        _dictCacheLookups++;
        NSDictionary *cached = _dictCache[key];
        if (cached) {
            _dictCacheHits++;
            return cached;
        }
    }

    NSUnderlineStyle underlineStyle = NSUnderlineStyleNone;
    switch (attributes->underlineType) {
        case iTermCharacterAttributesUnderlineNone:
            if (attributes->isURL) {
                underlineStyle = NSUnderlinePatternDash;
            }
            break;
        case iTermCharacterAttributesUnderlineDouble:
            underlineStyle = NSUnderlineStyleDouble;
            break;
        case iTermCharacterAttributesUnderlineRegular:
            underlineStyle = NSUnderlineStyleSingle;
            break;
        case iTermCharacterAttributesUnderlineCurly:
            underlineStyle = NSUnderlineStyleThick;  // Curly isn't an option, so repurpose this.
            break;
        case iTermCharacterAttributesUnderlineDotted:
            underlineStyle = NSUnderlineStylePatternDot;
            break;
        case iTermCharacterAttributesUnderlineDashed:
            underlineStyle = NSUnderlinePatternDash;
            break;
    }
    NSUnderlineStyle strikethroughStyle = NSUnderlineStyleNone;
    if (attributes->strikethrough) {
        strikethroughStyle = NSUnderlineStyleSingle;
    }
    static NSMutableParagraphStyle *paragraphStyle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        paragraphStyle.lineBreakMode = NSLineBreakByClipping;
        paragraphStyle.tabStops = @[];
        paragraphStyle.baseWritingDirection = NSWritingDirectionLeftToRight;
    });
    // The writing-direction attribute has only two possible values, so intern the
    // two one-element arrays instead of allocating one per run.
    static NSArray *ltrWritingDirection;
    static NSArray *rtlWritingDirection;
    static dispatch_once_t writingDirectionOnce;
    dispatch_once(&writingDirectionOnce, ^{
        ltrWritingDirection = @[@(NSWritingDirectionLeftToRight | (NSWritingDirection)NSWritingDirectionOverride)];
        rtlWritingDirection = @[@(NSWritingDirectionRightToLeft | (NSWritingDirection)NSWritingDirectionOverride)];
    });
    NSArray *writingDirection = (attributes->rtlStatus == RTLStatusRTL) ? rtlWritingDirection : ltrWritingDirection;

    // The underline-color components array is only read when hasUnderlineColor is
    // set (see -underlineColorForAttributes:), which is rare. Use a shared
    // placeholder otherwise so the common case allocates no array.
    static NSArray *placeholderUnderlineColor;
    static dispatch_once_t underlineColorOnce;
    dispatch_once(&underlineColorOnce, ^{
        placeholderUnderlineColor = @[@0, @0, @0, @0];
    });
    NSArray *underlineColor = placeholderUnderlineColor;
    if (attributes->hasUnderlineColor) {
        underlineColor = @[ @(attributes->underlineColor.red),
                            @(attributes->underlineColor.green),
                            @(attributes->underlineColor.blue),
                            @(attributes->underlineColor.mode) ];
    }

    NSDictionary *result = @{ (NSString *)kCTLigatureAttributeName: @(attributes->ligatureLevel),
              (NSString *)kCTForegroundColorAttributeName: (id)[attributes->foregroundColor CGColor],
              NSFontAttributeName: attributes->font,
              iTermAntiAliasAttribute: @(attributes->shouldAntiAlias),
              iTermIsBoxDrawingAttribute: @(attributes->boxDrawing),
              iTermFakeBoldAttribute: @(attributes->fakeBold),
              iTermBoldAttribute: @(attributes->bold),
              iTermFaintAttribute: @(attributes->faint),
              iTermFakeItalicAttribute: @(attributes->fakeItalic),
              iTermHasUnderlineColorAttribute: @(attributes->hasUnderlineColor),
              iTermUnderlineColorAttribute: underlineColor,
              NSUnderlineStyleAttributeName: @(underlineStyle),
              NSStrikethroughStyleAttributeName: @(strikethroughStyle),
              NSParagraphStyleAttributeName: paragraphStyle,
              NSWritingDirectionAttributeName: writingDirection,
    };

    if (key) {
        if (!_dictCache) {
            _dictCache = [[NSMutableDictionary alloc] init];
        } else if (_dictCache.count >= kDictCacheMaxEntries) {
            // Bound memory on pathological unique-color content by dropping it
            // wholesale rather than paying for LRU bookkeeping.
            [_dictCache removeAllObjects];
        }
        // Store a stable copy; the lookup key is reused and mutated in place.
        _dictCache[[key copyWithZone:NULL]] = result;

        // Adaptive: on content whose attribute combinations are almost all unique
        // (e.g. a different truecolor per cell) the cache never hits and only adds
        // overhead, so after a warmup we stop caching for the life of this builder.
        // The disable is deliberately permanent: the target workload is a sustained
        // full-screen color animation, where re-probing each frame would just pay
        // the warmup cost repeatedly.
        if (_dictCacheLookups >= kDictCacheWarmupLookups &&
            _dictCacheHits * kDictCacheMinHitRateDivisor < _dictCacheLookups) {
            _dictCacheDisabled = YES;
            _dictCache = nil;
            _dictLookupKey = nil;
        }
    }
    return result;
}

- (BOOL)character:(const screen_char_t *)c
withExtendedAttributes:(iTermExternalAttribute *)ea1
isEquivalentToCharacter:(const screen_char_t *)pc
withExtendedAttributes:(iTermExternalAttribute *)ea2 {
    if (c->complexChar != pc->complexChar) {
        return NO;
    }
    if (!c->complexChar) {
        if (_useNonAsciiFont) {
            BOOL ascii = c->code < 128;
            BOOL pcAscii = pc->code < 128;
            if (ascii != pcAscii) {
                return NO;
            }
        }
        if (iTermCharacterSupportsFastPath(c->code, _asciiLigaturesAvailable) != iTermCharacterSupportsFastPath(pc->code, _asciiLigaturesAvailable)) {
            return NO;
        }

        static NSCharacterSet *boxSet;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            boxSet = [iTermBoxDrawingBezierCurveFactory boxDrawingCharactersWithBezierPathsIncludingPowerline:_useNativePowerlineGlyphs];
        });
        BOOL box = [boxSet characterIsMember:c->code];
        BOOL pcBox = [boxSet characterIsMember:pc->code];
        if (box != pcBox) {
            return NO;
        }
    }
    if (!ScreenCharacterAttributesEqual(*c, *pc)) {
        return NO;
    }
    if ([_fontTable haveSpecialExceptionFor:*c orCharacter:*pc]) {
        return NO;
    }
    if (c->virtualPlaceholder) {
        // Anti-optimization: each unicode placeholder gets its own attributed string for now.
        // I can improve this later.
        return NO;
    }
    if (ea1 == nil && ea2 == nil) {
        // fast path
        return YES;
    }

    if (ea1 != nil) {
        return NO;
    }

    return [ea1 isEqualToExternalAttribute:ea2];
}

- (NSDictionary *)imageAttributesForCharacter:(screen_char_t *)c
                           externalAttributes:(iTermExternalAttribute *)ea
                                        state:(iTermKittyUnicodePlaceholderState *)state
                                displayColumn:(int)displayColumn {
    if (c->image) {
        if (c->virtualPlaceholder) {
            iTermKittyUnicodePlaceholderInfo info;
            if (!iTermDecodeKittyUnicodePlaceholder(c, ea, state, &info)) {
                return nil;
            }
            return @{ iTermKittyImageRowAttribute: @(info.row),
                      iTermKittyImageColumnAttribute: @(info.column),
                      iTermKittyImageIDAttribute: @(info.imageID),
                      iTermKittyImagePlacementIDAttribute: @(info.placementID),
                      iTermImageDisplayColumnAttribute: @(displayColumn)
            };
        } else {
            return @{ iTermImageCodeAttribute: @(c->code),
                      iTermImageColumnAttribute: @(c->foregroundColor),
                      iTermImageLineAttribute: @(c->backgroundColor),
                      iTermImageDisplayColumnAttribute: @(displayColumn) };
        }
    } else {
        iTermKittyUnicodePlaceholderStateInit(state);
        return nil;
    }
}

- (BOOL)imageAttributes:(NSDictionary *)imageAttributes
  followImageAttributes:(NSDictionary *)previousImageAttributes {
    if (![previousImageAttributes[iTermImageCodeAttribute] isEqual:imageAttributes[iTermImageCodeAttribute]]) {
        return NO;
    }
    if (![previousImageAttributes[iTermImageLineAttribute] isEqual:imageAttributes[iTermImageLineAttribute]]) {
        return NO;
    }
    if ((([previousImageAttributes[iTermImageColumnAttribute] integerValue] + 1) & 0xff) != ([imageAttributes[iTermImageColumnAttribute] integerValue] & 0xff)) {
        return NO;
    }

    return YES;
}

- (void)copySettingsFrom:(iTermAttributedStringBuilder *)other
                colorMap:(iTermColorMap *)colorMap
                delegate:(id<iTermAttributedStringBuilderDelegate>)delegate {
    _colorMap = colorMap;
    _reverseVideo = other.reverseVideo;
    _minimumContrast = other.minimumContrast;
    _zippy = other.zippy;
    _asciiLigaturesAvailable = other.asciiLigaturesAvailable;
    _asciiLigatures = other.asciiLigatures;
    _preferSpeedToFullLigatureSupport = other.preferSpeedToFullLigatureSupport;
    _lowFiCombiningMarks = other.lowFiCombiningMarks;
    _cellSize = other.cellSize;
    _blinkingItemsVisible = other.blinkingItemsVisible;
    _blinkAllowed = other.blinkAllowed;
    _useNonAsciiFont = other.useNonAsciiFont;
    _asciiAntiAlias = other.asciiAntiAlias;
    _nonAsciiAntiAlias = other.nonAsciiAntiAlias;
    _isRetina = other.isRetina;
    _forceAntialiasingOnRetina = other.forceAntialiasingOnRetina;
    _boldAllowed = other.boldAllowed;
    _italicAllowed = other.italicAllowed;
    _nonAsciiLigatures = other.nonAsciiLigatures;
    _useNativePowerlineGlyphs = other.useNativePowerlineGlyphs;
    _fontProvider = [other.fontProvider cloneFontProvider];
    _fontTable = other.fontTable;
    _delegate = delegate;
}

- (NSString *)statisticsString {
    @synchronized([iTermPreciseTimersLock class]) {
        iTermPreciseTimerStatsRecordTimer(_stats.attrsForChar);
        iTermPreciseTimerStatsRecordTimer(_stats.shouldSegment);
        iTermPreciseTimerStatsRecordTimer(_stats.buildMutableAttributedString);
        iTermPreciseTimerStatsRecordTimer(_stats.combineAttributes);
        iTermPreciseTimerStatsRecordTimer(_stats.updateBuilder);
        iTermPreciseTimerStatsRecordTimer(_stats.advances);

        iTermPreciseTimerStats array[] = {
            *_stats.attrsForChar,
            *_stats.shouldSegment,
            *_stats.buildMutableAttributedString,
            *_stats.combineAttributes,
            *_stats.updateBuilder,
            *_stats.advances,
        };
        _statsCount += 1;
        NSString *result = iTermPreciseTimerLogString(NSStringFromClass([self class]),
                                                      array,
                                                      sizeof(array) / sizeof(*array),
                                                      nil,
                                                      NO);

        if (_statsCount % 1000 == 0) {
            iTermPreciseTimerStatsInit(_stats.attrsForChar, NULL);
            iTermPreciseTimerStatsInit(_stats.shouldSegment, NULL);
            iTermPreciseTimerStatsInit(_stats.buildMutableAttributedString, NULL);
            iTermPreciseTimerStatsInit(_stats.combineAttributes, NULL);
            iTermPreciseTimerStatsInit(_stats.updateBuilder, NULL);
            iTermPreciseTimerStatsInit(_stats.advances, NULL);
        }

        return result;
    }

}
@end
