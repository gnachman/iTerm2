//
//  iTermMetalGlue.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/8/17.
//

#import "iTermMetalGlue.h"

#import "DebugLogging.h"
#import "iTermCharacterSource.h"
#import "iTermColorMap.h"
#import "iTermController.h"
#import "iTermSelection.h"
#import "iTermSmartCursorColor.h"
#import "iTermTextDrawingHelper.h"
#import "iTermTextRendererTransientState.h"
#import "NSColor+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSStringITerm.h"
#import "PTYFontInfo.h"
#import "PTYTextView.h"
#import "VT100Screen.h"

NS_ASSUME_NONNULL_BEGIN

extern void CGContextSetFontSmoothingStyle(CGContextRef, int);
extern int CGContextGetFontSmoothingStyle(CGContextRef);

typedef struct {
    unsigned int isMatch : 1;
    unsigned int inUnderlinedRange : 1;
    unsigned int selected : 1;
    unsigned int foregroundColor : 8;
    unsigned int fgGreen : 8;
    unsigned int fgBlue  : 8;
    unsigned int bold : 1;
    unsigned int faint : 1;
    vector_float4 background;
} iTermTextColorKey;

typedef struct {
    int bgColor;
    int bgGreen;
    int bgBlue;
    ColorMode bgColorMode;
    BOOL selected;
    BOOL isMatch;
} iTermBackgroundColorKey;

static vector_float4 VectorForColor(NSColor *color) {
    return (vector_float4) { color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent };
}

static NSColor *ColorForVector(vector_float4 v) {
    return [NSColor colorWithRed:v.x green:v.y blue:v.z alpha:v.w];
}

@interface iTermMetalGlue()
// Screen-relative cursor location on last frame
@property (nonatomic) VT100GridCoord oldCursorScreenCoord;
// Used to remember the last time the cursor moved to avoid drawing a blinked-out
// cursor while it's moving.
@property (nonatomic) NSTimeInterval lastTimeCursorMoved;
@end

@interface iTermMetalPerFrameState : NSObject<
    iTermMetalDriverDataSourcePerFrameState,
    iTermSmartCursorColorDelegate> {
    BOOL _havePreviousCharacterAttributes;
    screen_char_t _previousCharacterAttributes;
    vector_float4 _lastUnprocessedColor;
    BOOL _havePreviousForegroundColor;
    vector_float4 _previousForegroundColor;
    NSMutableArray<NSMutableData *> *_lines;
    NSMutableArray<NSIndexSet *> *_selectedIndexes;
    NSMutableDictionary<NSNumber *, NSData *> *_matches;
    NSMutableDictionary<NSNumber *, NSValue *> *_underlinedRanges;
    iTermColorMap *_colorMap;
    PTYFontInfo *_asciiFont;
    PTYFontInfo *_nonAsciiFont;
    BOOL _useBoldFont;
    BOOL _useItalicFont;
    BOOL _useNonAsciiFont;
    BOOL _reverseVideo;
    BOOL _useBrightBold;
    BOOL _isFrontTextView;
    vector_float4 _unfocusedSelectionColor;
    CGFloat _transparencyAlpha;
    BOOL _transparencyAffectsOnlyDefaultBackgroundColor;
    iTermMetalCursorInfo *_cursorInfo;
    iTermThinStrokesSetting _thinStrokes;
    BOOL _isRetina;
    BOOL _isInKeyWindow;
    BOOL _textViewIsActiveSession;
    BOOL _shouldDrawFilledInCursor;
    VT100GridSize _gridSize;
    VT100GridCoordRange _visibleRange;
    NSInteger _numberOfScrollbackLines;
    BOOL _cursorVisible;
    BOOL _cursorBlinking;
    BOOL _blinkingItemsVisible;
    BOOL _blinkAllowed;
    NSRange _inputMethodMarkedRange;
    NSTimeInterval _timeSinceCursorMoved;

    CGFloat _backgroundImageBlending;
    BOOL _backgroundImageTiled;
    NSImage *_backgroundImage;
    BOOL _asciiAntialias;
    BOOL _nonasciiAntialias;
    iTermMetalUnderlineDescriptor _asciiUnderlineDescriptor;
    iTermMetalUnderlineDescriptor _nonAsciiUnderlineDescriptor;
    NSImage *_badgeImage;
    CGRect _badgeSourceRect;
    CGRect _badgeDestinationRect;
    CGRect _documentVisibleRect;
    iTermMetalIMEInfo *_imeInfo;
    BOOL _showBroadcastStripes;
}

- (instancetype)initWithTextView:(PTYTextView *)textView
                          screen:(VT100Screen *)screen
                            glue:(iTermMetalGlue *)glue NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@implementation iTermMetalGlue

#pragma mark - iTermMetalDriverDataSource

- (nullable id<iTermMetalDriverDataSourcePerFrameState>)metalDriverWillBeginDrawingFrame {
    if (self.textView.drawingHelper.delegate == nil) {
        return nil;
    }
    return [[iTermMetalPerFrameState alloc] initWithTextView:self.textView screen:self.screen glue:self];
}

- (void)metalDriverDidDrawFrame {
    [self.delegate metalGlueDidDrawFrame];
}

@end

@implementation iTermMetalPerFrameState

- (instancetype)initWithTextView:(PTYTextView *)textView
                          screen:(VT100Screen *)screen
                            glue:(iTermMetalGlue *)glue {
    assert([NSThread isMainThread]);
    self = [super init];
    if (self) {
        _havePreviousCharacterAttributes = NO;
        _isFrontTextView = (textView == [[iTermController sharedInstance] frontTextView]);
        _unfocusedSelectionColor = VectorForColor([[_colorMap colorForKey:kColorMapSelection] colorDimmedBy:2.0/3.0
                                                                                           towardsGrayLevel:0.5]);
        _transparencyAlpha = textView.transparencyAlpha;
        iTermTextDrawingHelper *drawingHelper = textView.drawingHelper;
        _transparencyAffectsOnlyDefaultBackgroundColor = drawingHelper.transparencyAffectsOnlyDefaultBackgroundColor;

        // Copy lines from model. Always use these for consistency. I should also copy the color map
        // and any other data dependencies.
        _lines = [NSMutableArray array];
        _selectedIndexes = [NSMutableArray array];
        _matches = [NSMutableDictionary dictionary];
        _underlinedRanges = [NSMutableDictionary dictionary];
        _documentVisibleRect = textView.enclosingScrollView.documentVisibleRect;
        _visibleRange = [drawingHelper coordRangeForRect:_documentVisibleRect];
        long long totalScrollbackOverflow = [screen totalScrollbackOverflow];
        const int width = _visibleRange.end.x - _visibleRange.start.x;
        for (int i = _visibleRange.start.y; i < _visibleRange.end.y; i++) {
            screen_char_t *line = [screen getLineAtIndex:i];
            [_lines addObject:[NSMutableData dataWithBytes:line length:sizeof(screen_char_t) * width]];
            [_selectedIndexes addObject:[textView.selection selectedIndexesOnLine:i]];
            NSData *findMatches = [drawingHelper.delegate drawingHelperMatchesOnLine:i];
            if (findMatches) {
                _matches[@(i - _visibleRange.start.y)] = findMatches;
            }

            const long long absoluteLine = totalScrollbackOverflow + i;
            _underlinedRanges[@(i - _visibleRange.start.y)] = [NSValue valueWithRange:[drawingHelper underlinedRangeOnLine:absoluteLine]];
        }

        _gridSize = VT100GridSizeMake(textView.dataSource.width,
                                      textView.dataSource.height);
        _colorMap = [textView.colorMap copy];
        _asciiFont = textView.primaryFont;
        _nonAsciiFont = textView.secondaryFont;
        _useBoldFont = textView.useBoldFont;
        _useItalicFont = textView.useItalicFont;
        _useNonAsciiFont = textView.useNonAsciiFont;
        _reverseVideo = textView.dataSource.terminal.reverseVideo;
        _useBrightBold = textView.useBrightBold;
        _thinStrokes = textView.thinStrokes;
        _isRetina = drawingHelper.isRetina;
        _isInKeyWindow = [textView isInKeyWindow];
        _textViewIsActiveSession = [textView.delegate textViewIsActiveSession];
        _shouldDrawFilledInCursor = ([textView.delegate textViewShouldDrawFilledInCursor] || textView.keyFocusStolenCount);
        _numberOfScrollbackLines = textView.dataSource.numberOfScrollbackLines;
        _cursorVisible = drawingHelper.cursorVisible;
        _cursorBlinking = textView.isCursorBlinking;
        _blinkAllowed = textView.blinkAllowed;
        _blinkingItemsVisible = drawingHelper.blinkingItemsVisible;
        _inputMethodMarkedRange = drawingHelper.inputMethodMarkedRange;
        _asciiAntialias = drawingHelper.asciiAntiAlias;
        _nonasciiAntialias = drawingHelper.nonAsciiAntiAlias;
        _badgeImage = drawingHelper.badgeImage;
        if (_badgeImage) {
            _badgeDestinationRect = [iTermTextDrawingHelper rectForBadgeImageOfSize:_badgeImage.size
                                                                    destinationRect:textView.enclosingScrollView.documentVisibleRect
                                                               destinationFrameSize:textView.frame.size
                                                                        visibleSize:textView.enclosingScrollView.documentVisibleRect.size
                                                                      sourceRectPtr:&_badgeSourceRect];
        }

        VT100GridCoord cursorScreenCoord = VT100GridCoordMake(textView.dataSource.cursorX - 1,
                                                              textView.dataSource.cursorY - 1);
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (!VT100GridCoordEquals(cursorScreenCoord, glue.oldCursorScreenCoord)) {
            glue.lastTimeCursorMoved = now;
        }
        _timeSinceCursorMoved = now - glue.lastTimeCursorMoved;
        glue.oldCursorScreenCoord = cursorScreenCoord;

        iTermSmartCursorColor *smartCursorColor = nil;
        if (drawingHelper.useSmartCursorColor) {
            smartCursorColor = [[iTermSmartCursorColor alloc] init];
            smartCursorColor.delegate = self;
        }

        const int offset = _visibleRange.start.y - _numberOfScrollbackLines;
        _cursorInfo = [[iTermMetalCursorInfo alloc] init];
        _cursorInfo.copyMode = drawingHelper.copyMode;
        _cursorInfo.copyModeCursorCoord = VT100GridCoordMake(drawingHelper.copyModeCursorCoord.x,
                                                             drawingHelper.copyModeCursorCoord.y - _visibleRange.start.y);
        _cursorInfo.copyModeCursorSelecting = drawingHelper.copyModeSelecting;
        NSInteger lineWithCursor = textView.dataSource.cursorY - 1 + _numberOfScrollbackLines;
        if ([self shouldDrawCursor] &&
            textView.cursorVisible &&
            _visibleRange.start.y <= lineWithCursor &&
            lineWithCursor + 1 < _visibleRange.end.y) {
            _cursorInfo.cursorVisible = YES;
            _cursorInfo.type = drawingHelper.cursorType;
            _cursorInfo.coord = VT100GridCoordMake(textView.dataSource.cursorX - 1,
                                                   textView.dataSource.cursorY - 1 - offset);
            _cursorInfo.cursorColor = [self backgroundColorForCursor];
            if (_cursorInfo.type == CURSOR_BOX) {
                _cursorInfo.shouldDrawText = YES;
                const screen_char_t *line = (screen_char_t *)_lines[_cursorInfo.coord.y].bytes;
                screen_char_t screenChar = line[_cursorInfo.coord.x];
                const BOOL focused = ((_isInKeyWindow && _textViewIsActiveSession) || _shouldDrawFilledInCursor);
                if (!focused) {
                    _cursorInfo.shouldDrawText = NO;
                    _cursorInfo.frameOnly = YES;
                } else if (smartCursorColor) {
                    _cursorInfo.textColor = [self fastCursorColorForCharacter:screenChar
                                                               wantBackground:YES
                                                                        muted:NO];
                    _cursorInfo.cursorColor = [smartCursorColor backgroundColorForCharacter:screenChar];
                    NSColor *regularTextColor = [NSColor colorWithRed:_cursorInfo.textColor.x
                                                                green:_cursorInfo.textColor.y
                                                                 blue:_cursorInfo.textColor.z
                                                                alpha:_cursorInfo.textColor.w];
                    NSColor *smartTextColor = [smartCursorColor textColorForCharacter:screenChar
                                                                     regularTextColor:regularTextColor
                                                                 smartBackgroundColor:_cursorInfo.cursorColor];
                    CGFloat components[4];
                    [smartTextColor getComponents:components];
                    _cursorInfo.textColor = simd_make_float4(components[0],
                                                             components[1],
                                                             components[2],
                                                             components[3]);
                } else {
                    if (_reverseVideo) {
                        _cursorInfo.textColor = [_colorMap fastColorForKey:kColorMapBackground];
                    } else {
                        _cursorInfo.textColor = [self colorForCode:ALTSEM_CURSOR
                                                             green:0
                                                              blue:0
                                                         colorMode:ColorModeAlternate
                                                              bold:NO
                                                             faint:NO
                                                      isBackground:NO];
                    }
                }
            }
        } else {
            _cursorInfo.cursorVisible = NO;
        }

        _backgroundImageBlending = textView.blend;
        _backgroundImageTiled = textView.delegate.backgroundImageTiled;
        _backgroundImage = [textView.delegate textViewBackgroundImage];

        _asciiUnderlineDescriptor.color = VectorForColor([_colorMap colorForKey:kColorMapUnderline]);
        _asciiUnderlineDescriptor.offset = [drawingHelper yOriginForUnderlineGivenFontXHeight:_asciiFont.font.xHeight yOffset:0];
        _asciiUnderlineDescriptor.thickness = [drawingHelper underlineThicknessForFont:_asciiFont.font];

        _nonAsciiUnderlineDescriptor.color = _asciiUnderlineDescriptor.color;
        _nonAsciiUnderlineDescriptor.offset = [drawingHelper yOriginForUnderlineGivenFontXHeight:_nonAsciiFont.font.xHeight yOffset:0];
        _nonAsciiUnderlineDescriptor.thickness = [drawingHelper underlineThicknessForFont:_nonAsciiFont.font];

        // Replace screen contents with input method editor.
        if ([self hasMarkedText]) {
            VT100GridCoord startCoord = drawingHelper.cursorCoord;
            startCoord.y += drawingHelper.numberOfScrollbackLines - _visibleRange.start.y;
            [self copyMarkedText:drawingHelper.markedText.string
                  cursorLocation:drawingHelper.inputMethodSelectedRange.location
                              to:drawingHelper.cursorCoord
          ambiguousIsDoubleWidth:drawingHelper.ambiguousIsDoubleWidth
                   normalization:drawingHelper.normalization
                  unicodeVersion:drawingHelper.unicodeVersion
                       gridWidth:drawingHelper.gridSize.width
                numberOfIMELines:drawingHelper.numberOfIMELines];
        }

        _showBroadcastStripes = drawingHelper.showStripes;
    }
    return self;
}

- (void)copyMarkedText:(NSString *)str
        cursorLocation:(int)cursorLocation
                    to:(VT100GridCoord)startCoord
ambiguousIsDoubleWidth:(BOOL)ambiguousIsDoubleWidth
         normalization:(iTermUnicodeNormalization)normalization
        unicodeVersion:(NSInteger)unicodeVersion
             gridWidth:(int)gridWidth
      numberOfIMELines:(int)numberOfIMELines {
    const int maxLen = [str length] * kMaxParts;
    screen_char_t buf[maxLen];
    screen_char_t fg = {0}, bg = {0};
    int len;
    int cursorIndex = cursorLocation;
    StringToScreenChars(str,
                        buf,
                        fg,
                        bg,
                        &len,
                        ambiguousIsDoubleWidth,
                        &cursorIndex,
                        NULL,
                        normalization,
                        unicodeVersion);
    VT100GridCoord coord = startCoord;
    coord.y -= numberOfIMELines;
    BOOL foundCursor = NO;
    BOOL justWrapped = NO;
    BOOL foundStart = NO;
    _imeInfo = [[iTermMetalIMEInfo alloc] init];
    for (int i = 0; i < len; i++) {
        if (coord.y >= 0 && coord.y < _lines.count) {
            if (i == cursorIndex) {
                foundCursor = YES;
                _imeInfo.cursorCoord = coord;
            }
            screen_char_t *line = (screen_char_t *)_lines[coord.y].mutableBytes;
            screen_char_t c = buf[i];
            c.foregroundColor = iTermIMEColor.x * 255;
            c.fgGreen = iTermIMEColor.y * 255;
            c.fgBlue = iTermIMEColor.z * 255;
            c.foregroundColorMode = ColorMode24bit;

            c.backgroundColor = ALTSEM_DEFAULT;
            c.bgGreen = 0;
            c.bgBlue = 0;
            c.backgroundColorMode = ColorModeAlternate;

            c.underline = YES;

            if (i + 1 < len &&
                coord.x == gridWidth -1 &&
                line[i+1].code == DWC_RIGHT &&
                !line[i+1].complexChar) {
                // Bump DWC to start of next line instead of splitting it
                c.code = ' ';
                c.complexChar = NO;
                i--;
            } else {
                if (!foundStart) {
                    foundStart = YES;
                    [_imeInfo setRangeStart:coord];
                }
                line[coord.x] = c;
            }

        }
        justWrapped = NO;
        coord.x++;
        if (coord.x == gridWidth) {
            coord.x = 0;
            coord.y++;
            justWrapped = YES;
        }
        [_imeInfo setRangeEnd:coord];
    }

    if (!foundCursor) {
        if (justWrapped) {
            _imeInfo.cursorCoord = VT100GridCoordMake(gridWidth, coord.y - 1);
        } else {
            _imeInfo.cursorCoord = coord;
        }
    }
}

- (BOOL)showBroadcastStripes {
    return _showBroadcastStripes;
}

- (nullable iTermMetalIMEInfo *)imeInfo {
    return _imeInfo;
}

- (CGRect)badgeSourceRect {
    return _badgeSourceRect;
}

- (CGRect)badgeDestinationRect {
    CGRect rect = _badgeDestinationRect;
    rect.origin.x -= _documentVisibleRect.origin.x;
    rect.origin.y -= _documentVisibleRect.origin.y;
    return rect;
}

- (NSImage *)badgeImage {
    return _badgeImage;
}

- (VT100GridSize)gridSize {
    return _gridSize;
}

- (vector_float4)defaultBackgroundColor {
    NSColor *color = [_colorMap colorForKey:kColorMapBackground];
    return simd_make_float4((float)color.redComponent,
                            (float)color.greenComponent,
                            (float)color.blueComponent,
                            1);
}

// Private queue
- (nullable iTermMetalCursorInfo *)metalDriverCursorInfo {
    return _cursorInfo;
}

// Private queue
- (NSImage *)metalBackgroundImageGetTiled:(nullable BOOL *)tiled {
    if (tiled) {
        *tiled = _backgroundImageTiled;
    }
    return _backgroundImage;
}

// Private queue
- (void)metalGetGlyphKeys:(iTermMetalGlyphKey *)glyphKeys
               attributes:(iTermMetalGlyphAttributes *)attributes
               background:(iTermMetalBackgroundColorRLE *)backgroundRLE
                 rleCount:(int *)rleCount
                      row:(int)row
                    width:(int)width
           drawableGlyphs:(int *)drawableGlyphsPtr {
    screen_char_t *line = (screen_char_t *)_lines[row].bytes;
    NSIndexSet *selectedIndexes = _selectedIndexes[row];
    NSData *findMatches = _matches[@(row)];
    iTermTextColorKey keys[2];
    iTermTextColorKey *currentColorKey = &keys[0];
    iTermTextColorKey *previousColorKey = &keys[1];
    iTermBackgroundColorKey lastBackgroundKey;
    NSRange underlinedRange = [_underlinedRanges[@(row)] rangeValue];
    int rles = 0;

    int lastDrawableGlyph = -1;
    for (int x = 0; x < width; x++) {
        BOOL selected = [selectedIndexes containsIndex:x];
        BOOL findMatch = NO;
        if (findMatches && !selected) {
            findMatch = CheckFindMatchAtIndex(findMatches, x);
        }
        const BOOL inUnderlinedRange = NSLocationInRange(x, underlinedRange);

        // Background colors
        iTermBackgroundColorKey backgroundKey = {
            .bgColor = line[x].backgroundColor,
            .bgGreen = line[x].bgGreen,
            .bgBlue = line[x].bgBlue,
            .bgColorMode = line[x].backgroundColorMode,
            .selected = selected,
            .isMatch = findMatch,
        };

        vector_float4 backgroundColor;
        if (x > 0 &&
            backgroundKey.bgColor == lastBackgroundKey.bgColor &&
            backgroundKey.bgGreen == lastBackgroundKey.bgGreen &&
            backgroundKey.bgBlue == lastBackgroundKey.bgBlue &&
            backgroundKey.bgColorMode == lastBackgroundKey.bgColorMode &&
            backgroundKey.selected == lastBackgroundKey.selected &&
            backgroundKey.isMatch == lastBackgroundKey.isMatch) {

            const int previousRLE = rles - 1;
            backgroundColor = backgroundRLE[previousRLE].color;
            backgroundRLE[previousRLE].count++;
        } else {
            vector_float4 unprocessed = [self unprocessedColorForBackgroundColorKey:&backgroundKey];
            // The unprocessed color is needed for minimum contrast computation for text color.
            backgroundRLE[rles].color = [_colorMap fastProcessedBackgroundColorForBackgroundColor:unprocessed];
            backgroundRLE[rles].origin = x;
            backgroundRLE[rles].count = 1;
            if (_backgroundImage) {
                // This is kind of ugly but it simplifies things a lot to do it
                // here. The alpha value for background colors should be 1
                // except when there's a background image, in which case the
                // default background color gets a user-defined alpha value.
                const BOOL isDefaultBackgroundColor = (backgroundKey.bgColorMode == ColorModeAlternate &&
                                                       backgroundKey.bgColor == ALTSEM_DEFAULT &&
                                                       !selected &&
                                                       !findMatch);
                backgroundRLE[rles].color.w = isDefaultBackgroundColor ? (1 - _backgroundImageBlending) : 1;
            }
            backgroundColor = backgroundRLE[rles].color;
            rles++;
        }
        lastBackgroundKey = backgroundKey;
        attributes[x].backgroundColor = backgroundColor;
        attributes[x].backgroundColor.w = 1;

        // Foreground colors
        // Build up a compact key describing all the inputs to a text color
        currentColorKey->isMatch = findMatch;
        currentColorKey->inUnderlinedRange = inUnderlinedRange;
        currentColorKey->selected = selected;
        currentColorKey->foregroundColor = line[x].foregroundColor;
        currentColorKey->fgGreen = line[x].fgGreen;
        currentColorKey->fgBlue = line[x].fgBlue;
        currentColorKey->bold = line[x].bold;
        currentColorKey->faint = line[x].faint;
        currentColorKey->background = backgroundColor;
        if (x > 0 &&
            currentColorKey->isMatch == previousColorKey->isMatch &&
            currentColorKey->inUnderlinedRange == previousColorKey->inUnderlinedRange &&
            currentColorKey->selected == previousColorKey->selected &&
            currentColorKey->foregroundColor == previousColorKey->foregroundColor &&
            currentColorKey->fgGreen == previousColorKey->fgGreen &&
            currentColorKey->fgBlue == previousColorKey->fgBlue &&
            currentColorKey->bold == previousColorKey->bold &&
            currentColorKey->faint == previousColorKey->faint &&
            simd_equal(currentColorKey->background, previousColorKey->background)) {
            attributes[x].foregroundColor = attributes[x - 1].foregroundColor;
        } else {
            vector_float4 textColor = [self textColorForCharacter:&line[x]
                                                             line:row
                                                  backgroundColor:backgroundColor
                                                         selected:selected
                                                        findMatch:findMatch
                                                inUnderlinedRange:inUnderlinedRange
                                                            index:x];
            attributes[x].foregroundColor = textColor;
            attributes[x].foregroundColor.w = 1;
        }
        if (line[x].underline || inUnderlinedRange) {
            if (line[x].urlCode) {
                attributes[x].underlineStyle = iTermMetalGlyphAttributesUnderlineDouble;
            } else {
                attributes[x].underlineStyle = iTermMetalGlyphAttributesUnderlineSingle;
            }
        } else if (line[x].urlCode) {
            attributes[x].underlineStyle = iTermMetalGlyphAttributesUnderlineDashedSingle;
        } else {
            attributes[x].underlineStyle = iTermMetalGlyphAttributesUnderlineNone;
        }

        // Swap current and previous
        iTermTextColorKey *temp = currentColorKey;
        currentColorKey = previousColorKey;
        previousColorKey = temp;

        // Also need to take into account which font will be used (bold, italic, nonascii, etc.) plus
        // box drawing and images. If I want to support subpixel rendering then background color has
        // to be a factor also.
        glyphKeys[x].code = line[x].code;
        glyphKeys[x].isComplex = line[x].complexChar;
        glyphKeys[x].image = line[x].image;
        glyphKeys[x].boxDrawing = NO;
        glyphKeys[x].thinStrokes = [self useThinStrokesWithAttributes:&attributes[x]];

        const int boldBit = line[x].bold ? (1 << 0) : 0;
        const int italicBit = line[x].italic ? (1 << 1) : 0;
        glyphKeys[x].typeface = (boldBit | italicBit);

        if (iTermTextDrawingHelperIsCharacterDrawable(&line[x],
                                                      ScreenCharToStr(&line[x]) != nil,
                                                      _blinkingItemsVisible,
                                                      _blinkAllowed)) {
            lastDrawableGlyph = x;
            glyphKeys[x].drawable = YES;
        } else {
            glyphKeys[x].drawable = NO;
        }
    }
    *rleCount = rles;
    *drawableGlyphsPtr = lastDrawableGlyph + 1;

    // Tweak the text color for the cell that has a box cursor.
    if (row == _cursorInfo.coord.y &&
        _cursorInfo.type == CURSOR_BOX &&
        _cursorInfo.cursorVisible &&
        !_cursorInfo.frameOnly) {
        vector_float4 cursorTextColor;
        if (_cursorInfo.shouldDrawText) {
            cursorTextColor = _cursorInfo.textColor;
        } else if (_reverseVideo) {
            cursorTextColor = VectorForColor([_colorMap colorForKey:kColorMapBackground]);
        } else {
            cursorTextColor = [self colorForCode:ALTSEM_CURSOR
                                           green:0
                                            blue:0
                                       colorMode:ColorModeAlternate
                                            bold:NO
                                           faint:NO
                                    isBackground:NO];
        }
        attributes[_cursorInfo.coord.x].foregroundColor = cursorTextColor;
        attributes[_cursorInfo.coord.x].foregroundColor.w = 1;
    }
}

- (BOOL)useThinStrokesWithAttributes:(iTermMetalGlyphAttributes *)attributes {
    switch (_thinStrokes) {
        case iTermThinStrokesSettingAlways:
            return YES;

        case iTermThinStrokesSettingDarkBackgroundsOnly:
            break;

        case iTermThinStrokesSettingNever:
            return NO;

        case iTermThinStrokesSettingRetinaDarkBackgroundsOnly:
            if (!_isRetina) {
                return NO;
            }
            break;

        case iTermThinStrokesSettingRetinaOnly:
            return _isRetina;
    }

    const float backgroundBrightness = SIMDPerceivedBrightness(attributes->backgroundColor);
    const float foregroundBrightness = SIMDPerceivedBrightness(attributes->foregroundColor);
    return backgroundBrightness < foregroundBrightness;
}

- (vector_float4)selectionColorForCurrentFocus {
    if (_isFrontTextView) {
        return VectorForColor([_colorMap processedBackgroundColorForBackgroundColor:[_colorMap colorForKey:kColorMapSelection]]);
    } else {
        return _unfocusedSelectionColor;
    }
}

- (vector_float4)unprocessedColorForBackgroundColorKey:(iTermBackgroundColorKey *)colorKey {
    vector_float4 color = { 0, 0, 0, 0 };
    CGFloat alpha = _transparencyAlpha;
    if (colorKey->selected) {
        color = [self selectionColorForCurrentFocus];
        if (_transparencyAffectsOnlyDefaultBackgroundColor) {
            alpha = 1;
        }
    } else if (colorKey->isMatch) {
        color = (vector_float4){ 1, 1, 0, 1 };
    } else {
        const BOOL defaultBackground = (colorKey->bgColor == ALTSEM_DEFAULT &&
                                        colorKey->bgColorMode == ColorModeAlternate);
        // When set in preferences, applies alpha only to the defaultBackground
        // color, useful for keeping Powerline segments opacity(background)
        // consistent with their seperator glyphs opacity(foreground).
        if (_transparencyAffectsOnlyDefaultBackgroundColor && !defaultBackground) {
            alpha = 1;
        }
        if (_reverseVideo && defaultBackground) {
            // Reverse video is only applied to default background-
            // color chars.
            color = [self colorForCode:ALTSEM_DEFAULT
                                 green:0
                                  blue:0
                             colorMode:ColorModeAlternate
                                  bold:NO
                                 faint:NO
                          isBackground:NO];
        } else {
            // Use the regular background color.
            color = [self colorForCode:colorKey->bgColor
                                 green:colorKey->bgGreen
                                  blue:colorKey->bgBlue
                             colorMode:colorKey->bgColorMode
                                  bold:NO
                                 faint:NO
                          isBackground:YES];
        }

//        if (defaultBackground && _hasBackgroundImage) {
//            alpha = 1 - _blend;
//        }
    }
    color.w = alpha;
    return color;
}

- (vector_float4)colorForCode:(int)theIndex
                        green:(int)green
                         blue:(int)blue
                    colorMode:(ColorMode)theMode
                         bold:(BOOL)isBold
                        faint:(BOOL)isFaint
                 isBackground:(BOOL)isBackground {
    iTermColorMapKey key = [self colorMapKeyForCode:theIndex
                                              green:green
                                               blue:blue
                                          colorMode:theMode
                                               bold:isBold
                                       isBackground:isBackground];
    if (isBackground) {
        return VectorForColor([_colorMap colorForKey:key]);
    } else {
        vector_float4 color = VectorForColor([_colorMap colorForKey:key]);
        if (isFaint) {
            color.w = 0.5;
        }
        return color;
    }
}

- (iTermColorMapKey)colorMapKeyForCode:(int)theIndex
                                 green:(int)green
                                  blue:(int)blue
                             colorMode:(ColorMode)theMode
                                  bold:(BOOL)isBold
                          isBackground:(BOOL)isBackground {
    BOOL isBackgroundForDefault = isBackground;
    switch (theMode) {
        case ColorModeAlternate:
            switch (theIndex) {
                case ALTSEM_SELECTED:
                    if (isBackground) {
                        return kColorMapSelection;
                    } else {
                        return kColorMapSelectedText;
                    }
                case ALTSEM_CURSOR:
                    if (isBackground) {
                        return kColorMapCursor;
                    } else {
                        return kColorMapCursorText;
                    }
                case ALTSEM_REVERSED_DEFAULT:
                    isBackgroundForDefault = !isBackgroundForDefault;
                    // Fall through.
                case ALTSEM_DEFAULT:
                    if (isBackgroundForDefault) {
                        return kColorMapBackground;
                    } else {
                        if (isBold && _useBrightBold) {
                            return kColorMapBold;
                        } else {
                            return kColorMapForeground;
                        }
                    }
            }
            break;
        case ColorMode24bit:
            return [iTermColorMap keyFor8bitRed:theIndex green:green blue:blue];
        case ColorModeNormal:
            // Render bold text as bright. The spec (ECMA-48) describes the intense
            // display setting (esc[1m) as "bold or bright". We make it a
            // preference.
            if (isBold &&
                _useBrightBold &&
                (theIndex < 8) &&
                !isBackground) { // Only colors 0-7 can be made "bright".
                theIndex |= 8;  // set "bright" bit.
            }
            return kColorMap8bitBase + (theIndex & 0xff);

        case ColorModeInvalid:
            return kColorMapInvalid;
    }
    NSAssert(ok, @"Bogus color mode %d", (int)theMode);
    return kColorMapInvalid;
}

- (id)metalASCIICreationIdentifier {
    return @{ @"font": _asciiFont.font ?: [NSNull null],
              @"boldFont": _asciiFont.boldVersion ?: [NSNull null],
              @"boldItalicFont": _asciiFont.boldItalicVersion ?: [NSNull null],
              @"useBold": @(_useBoldFont),
              @"useItalic": @(_useItalicFont),
              @"asciiAntialiased": @(_asciiAntialias),
              @"nonasciiAntialiased": @(_nonasciiAntialias) };
}

- (NSDictionary<NSNumber *, iTermCharacterBitmap *> *)metalImagesForGlyphKey:(iTermMetalGlyphKey *)glyphKey
                                                                        size:(CGSize)size
                                                                       scale:(CGFloat)scale
                                                                       emoji:(nonnull BOOL *)emoji {
    BOOL fakeBold = !!(glyphKey->typeface & iTermMetalGlyphKeyTypefaceBold);
    BOOL fakeItalic = !!(glyphKey->typeface & iTermMetalGlyphKeyTypefaceItalic);
    const BOOL isAscii = !glyphKey->isComplex && (glyphKey->code < 128);
    PTYFontInfo *fontInfo = [PTYFontInfo fontForAsciiCharacter:isAscii
                                                     asciiFont:_asciiFont
                                                  nonAsciiFont:_nonAsciiFont
                                                   useBoldFont:_useBoldFont
                                                 useItalicFont:_useItalicFont
                                              usesNonAsciiFont:_useNonAsciiFont
                                                    renderBold:&fakeBold
                                                  renderItalic:&fakeItalic];
    NSFont *font = fontInfo.font;
    assert(font);

    iTermCharacterSource *characterSource =
        [[iTermCharacterSource alloc] initWithCharacter:CharToStr(glyphKey->code, glyphKey->isComplex)
                                                   font:font
                                                   size:size
                                         baselineOffset:fontInfo.baselineOffset
                                                  scale:scale
                                         useThinStrokes:glyphKey->thinStrokes
                                               fakeBold:fakeBold
                                             fakeItalic:fakeItalic
                                            antialiased:isAscii ? _asciiAntialias : _nonasciiAntialias];
    if (characterSource == nil) {
        return nil;
    }

    NSMutableDictionary<NSNumber *, iTermCharacterBitmap *> *result = [NSMutableDictionary dictionary];
    [characterSource.parts enumerateObjectsUsingBlock:^(NSNumber * _Nonnull partNumber, NSUInteger idx, BOOL * _Nonnull stop) {
        int part = partNumber.intValue;
        result[partNumber] = [characterSource bitmapForPart:part];
    }];
    if (emoji) {
        *emoji = characterSource.emoji;
    }
    return result;
}

- (void)metalGetUnderlineDescriptorsForASCII:(out iTermMetalUnderlineDescriptor *)ascii
                                    nonASCII:(out iTermMetalUnderlineDescriptor *)nonAscii {
    *ascii = _asciiUnderlineDescriptor;
    *nonAscii = _nonAsciiUnderlineDescriptor;
}

#pragma mark - Color

- (vector_float4)textColorForCharacter:(screen_char_t *)c
                                  line:(int)line
                       backgroundColor:(vector_float4)backgroundColor
                              selected:(BOOL)selected
                             findMatch:(BOOL)findMatch
                     inUnderlinedRange:(BOOL)inUnderlinedRange
                                 index:(int)index {
    vector_float4 rawColor = { 0, 0, 0, 0 };
    BOOL isMatch = NO;
    iTermColorMap *colorMap = _colorMap;
    const BOOL needsProcessing = (colorMap.minimumContrast > 0.001 ||
                                  colorMap.dimmingAmount > 0.001 ||
                                  colorMap.mutingAmount > 0.001 ||
                                  c->faint);  // faint implies alpha<1 and is faster than getting the alpha component


    if (isMatch) {
        // Black-on-yellow search result.
        rawColor = (vector_float4){ 0, 0, 0, 1 };
        _havePreviousCharacterAttributes = NO;
    } else if (inUnderlinedRange) {
        // Blue link text.
        rawColor = VectorForColor([_colorMap colorForKey:kColorMapLink]);
        _havePreviousCharacterAttributes = NO;
    } else if (selected) {
        // Selected text.
        rawColor = VectorForColor([colorMap colorForKey:kColorMapSelectedText]);
        _havePreviousCharacterAttributes = NO;
    } else if (_reverseVideo &&
               ((c->foregroundColor == ALTSEM_DEFAULT && c->foregroundColorMode == ColorModeAlternate) ||
                (c->foregroundColor == ALTSEM_CURSOR && c->foregroundColorMode == ColorModeAlternate))) {
           // Reverse video is on. Either is cursor or has default foreground color. Use
           // background color.
           rawColor = VectorForColor([colorMap colorForKey:kColorMapBackground]);
           _havePreviousCharacterAttributes = NO;
    } else if (!_havePreviousCharacterAttributes ||
               c->foregroundColor != _previousCharacterAttributes.foregroundColor ||
               c->fgGreen != _previousCharacterAttributes.fgGreen ||
               c->fgBlue != _previousCharacterAttributes.fgBlue ||
               c->foregroundColorMode != _previousCharacterAttributes.foregroundColorMode ||
               c->bold != _previousCharacterAttributes.bold ||
               c->faint != _previousCharacterAttributes.faint ||
               !_havePreviousForegroundColor) {
        // "Normal" case for uncached text color. Recompute the unprocessed color from the character.
        _previousCharacterAttributes = *c;
        _havePreviousCharacterAttributes = YES;
        rawColor = [self colorForCode:c->foregroundColor
                                green:c->fgGreen
                                 blue:c->fgBlue
                            colorMode:c->foregroundColorMode
                                 bold:c->bold
                                faint:c->faint
                         isBackground:NO];
    } else {
        // Foreground attributes are just like the last character. There is a cached foreground color.
        if (needsProcessing) {
            // Process the text color for the current background color, which has changed since
            // the last cell.
            rawColor = _lastUnprocessedColor;
        } else {
            // Text color is unchanged. Either it's independent of the background color or the
            // background color has not changed.
            return _previousForegroundColor;
        }
    }

    _lastUnprocessedColor = rawColor;

    vector_float4 result;
    if (needsProcessing) {
        result = VectorForColor([_colorMap processedTextColorForTextColor:ColorForVector(rawColor)
                                                      overBackgroundColor:ColorForVector(backgroundColor)]);
    } else {
        result = rawColor;
    }
    _previousForegroundColor = result;
    _havePreviousForegroundColor = YES;
    return result;
}

- (NSColor *)backgroundColorForCursor {
    NSColor *color;
    if (_reverseVideo) {
        color = [[_colorMap colorForKey:kColorMapCursorText] colorWithAlphaComponent:1.0];
    } else {
        color = [[_colorMap colorForKey:kColorMapCursor] colorWithAlphaComponent:1.0];
    }
    return [_colorMap colorByDimmingTextColor:color];
}

#pragma mark - iTermSmartCursorColorDelegate

- (iTermCursorNeighbors)cursorNeighbors {
    return [iTermSmartCursorColor neighborsForCursorAtCoord:_cursorInfo.coord
                                                   gridSize:_gridSize
                                                 lineSource:^screen_char_t *(int y) {
                                                     const int i = y + _numberOfScrollbackLines - _visibleRange.start.y;
                                                     if (i >= 0 && i < _lines.count) {
                                                         return (screen_char_t *)_lines[i].bytes;
                                                     } else {
                                                         return nil;
                                                     }
                                                 }];
}

- (vector_float4)fastCursorColorForCharacter:(screen_char_t)screenChar
                              wantBackground:(BOOL)wantBackgroundColor
                                       muted:(BOOL)muted {
    BOOL isBackground = [iTermTextDrawingHelper cursorUsesBackgroundColorForScreenChar:screenChar
                                                                        wantBackground:wantBackgroundColor
                                                                          reverseVideo:_reverseVideo];

    vector_float4 color;
    if (wantBackgroundColor) {
        color = [self colorForCode:screenChar.backgroundColor
                             green:screenChar.bgGreen
                              blue:screenChar.bgBlue
                         colorMode:screenChar.backgroundColorMode
                              bold:screenChar.bold
                             faint:screenChar.faint
                      isBackground:isBackground];
    } else {
        color = [self colorForCode:screenChar.foregroundColor
                             green:screenChar.fgGreen
                              blue:screenChar.fgBlue
                         colorMode:screenChar.foregroundColorMode
                              bold:screenChar.bold
                             faint:screenChar.faint
                      isBackground:isBackground];
    }
    if (muted) {
        color = [_colorMap fastColorByMutingColor:color];
    }
    return color;
}

- (NSColor *)cursorColorForCharacter:(screen_char_t)screenChar
                      wantBackground:(BOOL)wantBackgroundColor
                               muted:(BOOL)muted {
    vector_float4 v = [self fastCursorColorForCharacter:screenChar wantBackground:wantBackgroundColor muted:muted];
    return [NSColor colorWithRed:v.x green:v.y blue:v.z alpha:v.w];
}

- (NSColor *)cursorColorByDimmingSmartColor:(NSColor *)color {
    return [_colorMap colorByDimmingTextColor:color];
}

- (NSColor *)cursorWhiteColor {
    NSColor *whiteColor = [NSColor colorWithCalibratedRed:1
                                                    green:1
                                                     blue:1
                                                    alpha:1];
    return [_colorMap colorByDimmingTextColor:whiteColor];
}

- (NSColor *)cursorBlackColor {
    NSColor *blackColor = [NSColor colorWithCalibratedRed:0
                                                    green:0
                                                     blue:0
                                                    alpha:1];
    return [_colorMap colorByDimmingTextColor:blackColor];
}

#pragma mark - Cursor Logic

- (BOOL)shouldDrawCursor {
    BOOL hideCursorBecauseBlinking = [self hideCursorBecauseBlinking];

    // Draw the regular cursor only if there's not an IME open as it draws its
    // own cursor. Also, it must be not blinked-out, and it must be within the expected bounds of
    // the screen (which is just a sanity check, really).
    BOOL result = (![self hasMarkedText] &&
                   _cursorVisible &&
                   !hideCursorBecauseBlinking);
    DLog(@"shouldDrawCursor: hasMarkedText=%d, cursorVisible=%d, hideCursorBecauseBlinking=%d, result=%@",
         (int)[self hasMarkedText], (int)_cursorVisible, (int)hideCursorBecauseBlinking, @(result));
    return result;
}

- (BOOL)hideCursorBecauseBlinking {
    if (_cursorBlinking &&
        _isInKeyWindow &&
        _textViewIsActiveSession &&
        _timeSinceCursorMoved > 0.5) {
        // Allow the cursor to blink if it is configured, the window is key, this session is active
        // in the tab, and the cursor has not moved for half a second.
        return !_blinkingItemsVisible;
    } else {
        return NO;
    }
}

- (BOOL)hasMarkedText {
    return _inputMethodMarkedRange.length > 0;
}


@end

NS_ASSUME_NONNULL_END
