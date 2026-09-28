//
//  AttributedStringBuilderSpacingMarkTests.m
//  ModernTests
//
//  A spacing combining mark gets its own cell but is appended to its base's attributed
//  string so CoreText shapes the two together. That only makes sense when the base is
//  shaped text. The Metal renderer skips box-drawing and image cells and shapes the rest
//  of the row by handing each string to CoreText from its first remaining cell, asserting
//  if that string is tagged as box drawing or as an image. A mark appended to a notcurses
//  border crashed the Metal renderer on notcurses-demo's uniblock demo (issue 13073).
//
//  This is Objective-C rather than Swift because reading the builder's output needs
//  iTermMutableAttributedStringBuilder.h, which makes NSMutableAttributedString conform to
//  iTermAttributedString. Exposing that to Swift through the bridging header retypes
//  NSAttributedString's length as UInt for every Swift file in iTerm2SharedARC and breaks
//  the build.
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#import "CVector.h"
#import "ScreenChar.h"
#import "iTermAttributedStringBuilder.h"
#import "iTermBackgroundColorRun.h"
#import "iTermColorMap.h"
#import "iTermMutableAttributedStringBuilder.h"
#import "iTermTextDrawingHelper.h"

// iTermFontTable is a Swift class (@objc(iTermFontTable) FontTable) that conforms to
// FontProviderProtocol. ModernTests cannot import iTerm2SharedARC-Swift.h, so declare
// just enough to create one with its default initializer.
@interface iTermFontTable : NSObject
@end

@interface AttributedStringBuilderSpacingMarkTests : XCTestCase<iTermAttributedStringBuilderDelegate>
@end

@implementation AttributedStringBuilderSpacingMarkTests {
    iTermColorMap *_colorMap;
    iTermAttributedStringBuilderStats _stats;
}

- (iTermAttributedStringBuilder *)builder {
    _colorMap = [[iTermColorMap alloc] init];
    [_colorMap setColor:[NSColor whiteColor] forKey:kColorMapForeground];
    [_colorMap setColor:[NSColor blackColor] forKey:kColorMapBackground];

    iTermFontTable *fontTable = [[iTermFontTable alloc] init];
    iTermAttributedStringBuilderStatsPointers pointers = {
        .attrsForChar = &_stats.attrsForChar,
        .shouldSegment = &_stats.shouldSegment,
        .buildMutableAttributedString = &_stats.buildMutableAttributedString,
        .combineAttributes = &_stats.combineAttributes,
        .updateBuilder = &_stats.updateBuilder,
        .advances = &_stats.advances,
    };
    iTermPreciseTimerStatsInit(pointers.attrsForChar, "attrsForChar");
    iTermPreciseTimerStatsInit(pointers.shouldSegment, "shouldSegment");
    iTermPreciseTimerStatsInit(pointers.buildMutableAttributedString, "build");
    iTermPreciseTimerStatsInit(pointers.combineAttributes, "combine");
    iTermPreciseTimerStatsInit(pointers.updateBuilder, "update");
    iTermPreciseTimerStatsInit(pointers.advances, "advances");
    iTermAttributedStringBuilder *builder = [[iTermAttributedStringBuilder alloc] initWithStats:pointers];
    [builder setColorMap:_colorMap
            reverseVideo:NO
         minimumContrast:0
                   zippy:NO
 asciiLigaturesAvailable:NO
          asciiLigatures:NO
preferSpeedToFullLigatureSupport:YES
     lowFiCombiningMarks:NO
                cellSize:NSMakeSize(7, 14)
    blinkingItemsVisible:YES
            blinkAllowed:NO
         useNonAsciiFont:NO
          asciiAntiAlias:YES
       nonAsciiAntiAlias:YES
                isRetina:YES
forceAntialiasingOnRetina:NO
             boldAllowed:YES
           italicAllowed:YES
       nonAsciiLigatures:NO
useNativePowerlineGlyphs:NO
            fontProvider:(id<FontProviderProtocol>)fontTable
               fontTable:fontTable
                delegate:self];
    return builder;
}

// Builds attributed strings for a two-cell row made from `base` and `mark`. `mutate`, if
// given, may edit the converted cells before the builder sees them.
- (NSArray<id<iTermAttributedString>> *)attributedStringsForBase:(unichar)base
                                                            mark:(unichar)mark
                                                          mutate:(void (^)(screen_char_t *line))mutate {
    const unichar chars[] = { base, mark };
    screen_char_t line[iTermStringToScreenCharsCapacity(2)] = { 0 };
    screen_char_t fg = { 0 };
    screen_char_t bg = { 0 };
    int width = 0;
    BOOL foundDwc = NO;
    BOOL rtlFound = NO;
    StringToScreenChars([NSString stringWithCharacters:chars length:2], line, fg, bg, &width,
                        NO, NULL, &foundDwc, iTermUnicodeNormalizationNone, 9, NO, &rtlFound);
    XCTAssertEqual(width, 2, @"The spacing mark should get its own cell");
    if (mutate) {
        mutate(line);
    }

    iTermBackgroundColorRun run = {
        .modelRange = NSMakeRange(0, width),
        .visualRange = NSMakeRange(0, width),
        .bgColor = ALTSEM_DEFAULT,
        .bgColorMode = ColorModeAlternate,
    };
    CTVector(CGFloat) positions;
    CTVectorCreate(&positions, width);
    NSArray<id<iTermAttributedString>> *strings =
        [[self builder] attributedStringsForLine:line
                                        bidiInfo:nil
                              externalAttributes:nil
                                           range:NSMakeRange(0, width)
                                 hasSelectedText:NO
                                 backgroundColor:[NSColor blackColor]
                                  forceTextColor:nil
                                        colorRun:&run
                                     findMatches:nil
                                 underlinedRange:NSMakeRange(0, 0)
                                       positions:&positions];
    CTVectorDestroy(&positions);
    return strings;
}

static NSDictionary *AttributesOfString(id<iTermAttributedString> string) {
    iTermCheapAttributedString *cheap = [iTermCheapAttributedString castFrom:string];
    if (cheap) {
        return cheap.attributes;
    }
    return [(NSAttributedString *)string attributesAtIndex:0 effectiveRange:nil];
}

// Asserts that the base and the mark are in separate strings and that the mark's string is
// plain text, so it draws on its own.
- (void)assertMarkIsStandalone:(NSArray<id<iTermAttributedString>> *)strings {
    XCTAssertEqual(strings.count, 2);
    if (strings.count != 2) {
        return;
    }
    XCTAssertTrue(NSEqualRanges([strings[0] sourceColumnRange], NSMakeRange(0, 1)));
    XCTAssertTrue(NSEqualRanges([strings[1] sourceColumnRange], NSMakeRange(1, 1)));
    NSDictionary *markAttributes = AttributesOfString(strings[1]);
    XCTAssertFalse([markAttributes[iTermIsBoxDrawingAttribute] boolValue]);
    XCTAssertNil(markAttributes[iTermImageCodeAttribute]);
}

- (void)testSpacingMarkAfterBoxDrawingCharacterIsStandalone {
    // U+2502 BOX DRAWINGS LIGHT VERTICAL (a notcurses border) followed by
    // U+0903 DEVANAGARI SIGN VISARGA.
    NSArray<id<iTermAttributedString>> *strings = [self attributedStringsForBase:0x2502 mark:0x0903 mutate:nil];
    [self assertMarkIsStandalone:strings];
    XCTAssertTrue([AttributesOfString(strings.firstObject)[iTermIsBoxDrawingAttribute] boolValue]);
}

- (void)testSpacingMarkAfterImageCellIsStandalone {
    // An inline-image cell whose code is not ASCII, followed by U+093E DEVANAGARI VOWEL SIGN AA.
    NSArray<id<iTermAttributedString>> *strings = [self attributedStringsForBase:0x0915
                                                                           mark:0x093E
                                                                         mutate:^(screen_char_t *line) {
        screen_char_t image = { 0 };
        image.image = 1;
        image.code = 200;
        line[0] = image;
    }];
    [self assertMarkIsStandalone:strings];
    XCTAssertEqualObjects(AttributesOfString(strings.firstObject)[iTermImageCodeAttribute], @200);
}

- (void)testSpacingMarkStillJoinsTextBase {
    // U+0915 DEVANAGARI LETTER KA followed by U+093E DEVANAGARI VOWEL SIGN AA. The mark must
    // stay in its base's string so CoreText can shape them together.
    NSArray<id<iTermAttributedString>> *strings = [self attributedStringsForBase:0x0915 mark:0x093E mutate:nil];
    XCTAssertEqual(strings.count, 1);
    XCTAssertTrue(NSEqualRanges([strings.firstObject sourceColumnRange], NSMakeRange(0, 2)));
}

- (void)testWhichBasesCanHostASpacingMark {
    // This predicate also decides whether the Metal renderer folds the mark into the base's
    // glyph (combiningSuccessor), so check it directly.
    screen_char_t c = { 0 };
    c.code = 'a';
    XCTAssertFalse(iTermScreenCharCanHostSpacingMark(&c, NO), @"ASCII");
    c.code = 0x0915;
    XCTAssertTrue(iTermScreenCharCanHostSpacingMark(&c, NO), @"Devanagari letter");
    c.code = 0x2502;
    XCTAssertFalse(iTermScreenCharCanHostSpacingMark(&c, NO), @"Box drawing");
    c.code = 0xE0B0;
    XCTAssertTrue(iTermScreenCharCanHostSpacingMark(&c, NO), @"Powerline drawn from the font");
    XCTAssertFalse(iTermScreenCharCanHostSpacingMark(&c, YES), @"Powerline drawn natively");
    c.code = 200;
    c.image = 1;
    XCTAssertFalse(iTermScreenCharCanHostSpacingMark(&c, NO), @"Image");
}

#pragma mark - iTermAttributedStringBuilderDelegate

- (BOOL)useSelectedTextColor {
    return NO;
}

- (NSColor *)unprocessedColorForBackgroundRun:(const iTermBackgroundColorRun *)run
                               enableBlending:(BOOL)enableBlending {
    return [NSColor blackColor];
}

- (NSColor *)colorForCode:(int)theIndex
                    green:(int)green
                     blue:(int)blue
                colorMode:(ColorMode)theMode
                     bold:(BOOL)isBold
                    faint:(BOOL)isFaint
             isBackground:(BOOL)isBackground {
    return isBackground ? [NSColor blackColor] : [NSColor whiteColor];
}

@end
