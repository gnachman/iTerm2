//
//  iTermAttributedStringBuilder.m
//  iTerm2
//
//  Created by George Nachman on 10/31/24.
//

#import "iTermAttributedStringBuilder.h"

#import "NSDictionary+iTerm.h"
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
    iTermCharacterAttributesUnderlineDouble
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

static inline BOOL iTermCharacterAttributesUnderlineColorEqual(iTermCharacterAttributes *newAttributes,
                                                               iTermCharacterAttributes *previousAttributes) {
    if (newAttributes->hasUnderlineColor != previousAttributes->hasUnderlineColor) {
        return NO;
    }
    if (!newAttributes->hasUnderlineColor) {
        return YES;
    }
    return memcmp(&newAttributes->underlineColor,
                  &previousAttributes->underlineColor,
                  sizeof(newAttributes->underlineColor)) == 0;
}

static NSColor *iTermTextDrawingHelperGetTextColor(screen_char_t *c,
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
        // Blue link text.
        rawColor = [context->colorMap colorForKey:kColorMapLink];
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
    } else if (!context->havePreviousCharacterAttributes ||
               c->foregroundColor != context->previousCharacterAttributes.foregroundColor ||
               c->fgGreen != context->previousCharacterAttributes.fgGreen ||
               c->fgBlue != context->previousCharacterAttributes.fgBlue ||
               c->foregroundColorMode != context->previousCharacterAttributes.foregroundColorMode ||
               c->bold != context->previousCharacterAttributes.bold ||
               c->faint != context->previousCharacterAttributes.faint ||
               !context->previousForegroundColor) {
        // "Normal" case for uncached text color. Recompute the unprocessed color from the character.
        context->previousCharacterAttributes = *c;
        context->havePreviousCharacterAttributes = YES;
        rawColor = [context->delegate colorForCode:c->foregroundColor
                                             green:c->fgGreen
                                              blue:c->fgBlue
                                         colorMode:c->foregroundColorMode
                                              bold:c->bold
                                             faint:c->faint
                                      isBackground:NO];
        assert(rawColor);
    } else {
        // Foreground attributes are just like the last character. There is a cached foreground color.
        if (needsProcessing && context->backgroundColor != context->previousBackgroundColor) {
            // Process the text color for the current background color, which has changed since
            // the last cell.
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

@implementation iTermAttributedStringBuilder {
    int _statsCount;
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
    iTermMutableAttributedStringBuilder *builder = [[iTermMutableAttributedStringBuilder alloc] init];
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
            builder = [[iTermMutableAttributedStringBuilder alloc] init];
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

    attributes->boxDrawing = !isComplex && [[iTermBoxDrawingBezierCurveFactory boxDrawingCharactersWithBezierPathsIncludingPowerline:_useNativePowerlineGlyphs] characterIsMember:code];
    attributes->contrastIneligible = !isComplex && [[iTermBoxDrawingBezierCurveFactory blockDrawingCharacters] characterIsMember:code];

    if (forceTextColor) {
        attributes->foregroundColor = forceTextColor;
    } else {
        attributes->foregroundColor = iTermTextDrawingHelperGetTextColor(c,
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
        switch (c->underlineStyle) {
            case VT100UnderlineStyleSingle:
                attributes->underlineType = iTermCharacterAttributesUnderlineRegular;
                break;
            case VT100UnderlineStyleCurly:
                attributes->underlineType = iTermCharacterAttributesUnderlineCurly;
                break;
            case VT100UnderlineStyleDouble:
                attributes->underlineType = iTermCharacterAttributesUnderlineDouble;
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
        attributes->underlineColor = ea.underlineColor;
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
    NSUnderlineStyle underlineStyle = NSUnderlineStyleNone;
    switch (attributes->underlineType) {
        case iTermCharacterAttributesUnderlineNone:
            if (attributes->isURL) {
                underlineStyle = NSUnderlinePatternDash;
            }
            break;
        case iTermCharacterAttributesUnderlineDouble:
            if (attributes->isURL) {
                underlineStyle = NSUnderlineStylePatternDot;  // Mixed solid/underline isn't an option, so repurpose this.
            } else {
                underlineStyle = NSUnderlineStyleDouble;
            }
            break;
        case iTermCharacterAttributesUnderlineRegular:
            if (attributes->isURL) {
                underlineStyle = NSUnderlineStylePatternDot;  // Mixed solid/underline isn't an option, so repurpose this.
            } else {
                underlineStyle = NSUnderlineStyleSingle;
            }
            break;
        case iTermCharacterAttributesUnderlineCurly:
            if (attributes->isURL) {
                underlineStyle = NSUnderlineStylePatternDot;  // Mixed solid/underline isn't an option, so repurpose this.
            } else {
                underlineStyle = NSUnderlineStyleThick;  // Curly isn't an option, so repurpose this.
            }
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
    NSWritingDirection writingDirection;
    switch (attributes->rtlStatus) {
        case RTLStatusUnknown:
        case RTLStatusLTR:
            writingDirection = NSWritingDirectionLeftToRight | NSWritingDirectionOverride;
            break;
        case RTLStatusRTL:
            writingDirection = NSWritingDirectionRightToLeft | NSWritingDirectionOverride;
            break;
    }
    return @{ (NSString *)kCTLigatureAttributeName: @(attributes->ligatureLevel),
              (NSString *)kCTForegroundColorAttributeName: (id)[attributes->foregroundColor CGColor],
              NSFontAttributeName: attributes->font,
              iTermAntiAliasAttribute: @(attributes->shouldAntiAlias),
              iTermIsBoxDrawingAttribute: @(attributes->boxDrawing),
              iTermFakeBoldAttribute: @(attributes->fakeBold),
              iTermBoldAttribute: @(attributes->bold),
              iTermFaintAttribute: @(attributes->faint),
              iTermFakeItalicAttribute: @(attributes->fakeItalic),
              iTermHasUnderlineColorAttribute: @(attributes->hasUnderlineColor),
              iTermUnderlineColorAttribute: @[ @(attributes->underlineColor.red),
                                               @(attributes->underlineColor.green),
                                               @(attributes->underlineColor.blue),
                                               @(attributes->underlineColor.mode) ],
              NSUnderlineStyleAttributeName: @(underlineStyle),
              NSStrikethroughStyleAttributeName: @(strikethroughStyle),
              NSParagraphStyleAttributeName: paragraphStyle,
              NSWritingDirectionAttributeName: @[@(writingDirection)],
    };
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
