//
//  LegacyRendererSGRSplitColorTests.m
//  ModernTests
//
//  On a bidi line the attributed-string builder merges runs that differ only in
//  foreground color into one string so CoreText shapes an Arabic word as a whole
//  (the legacy CoreGraphics renderer then fills each color span separately). With
//  zippy text drawing on (the default), a color change after some characters had
//  been appended used to snapshot them into a cheap single-attribute string that
//  shared its character buffer with the builder. Characters appended after the
//  color change landed in that same buffer, so the whole word took the first
//  color: `سلام \e[31mدن\e[32mیا` drew all of دنیا in red.
//
//  Objective-C rather than Swift for the same reason as
//  AttributedStringBuilderSpacingMarkTests.m.
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>

#import "CVector.h"
#import "ScreenChar.h"
#import "ScreenCharArray.h"
#import "iTermAttributedStringBuilder.h"
#import "iTermBackgroundColorRun.h"
#import "iTermColorMap.h"
#import "iTermMutableAttributedStringBuilder.h"
#import "NSObject+iTerm.h"
#import "iTermTextDrawingHelper.h"

// Swift classes ModernTests cannot see through iTerm2SharedARC-Swift.h; declare
// just what these tests use.
@interface iTermFontTable : NSObject
@end

@interface iTermBidiDisplayInfo : NSObject
- (instancetype)initWithScreenCharArray:(ScreenCharArray *)sca paddedTo:(int)width;
+ (BOOL)annotateWithBidiInfo:(iTermBidiDisplayInfo *)bidiInfo msca:(MutableScreenCharArray *)msca;
- (const int *)lut;
@end

@interface LegacyRendererSGRSplitColorTests : XCTestCase<iTermAttributedStringBuilderDelegate>
@end

@implementation LegacyRendererSGRSplitColorTests {
    iTermColorMap *_colorMap;
    iTermAttributedStringBuilderStats _stats;
    BOOL _useSelectedTextColor;
}

- (iTermAttributedStringBuilder *)builder {
    return [self builderWithFontTable:YES];
}

// Without a font table the builder's shortcut that reuses the previous cell's
// attributes for an equivalent cell is live (the font table's special-exception
// check otherwise disables it), so per-cell highlight changes must stop it.
- (iTermAttributedStringBuilder *)builderWithFontTable:(BOOL)withFontTable {
    _colorMap = [[iTermColorMap alloc] init];
    [_colorMap setColor:[NSColor whiteColor] forKey:kColorMapForeground];
    [_colorMap setColor:[NSColor blackColor] forKey:kColorMapBackground];
    [_colorMap setColor:[NSColor blueColor] forKey:kColorMapSelectedText];
    [_colorMap setColor:[NSColor yellowColor] forKey:kColorMapMatch];
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
                   zippy:YES
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
               fontTable:withFontTable ? fontTable : nil
                delegate:self];
    return builder;
}

static NSColor *ColorAt(NSAttributedString *string, NSUInteger i) {
    CGColorRef cgColor = (__bridge CGColorRef)[string attribute:(NSString *)kCTForegroundColorAttributeName
                                                        atIndex:i
                                                 effectiveRange:nil];
    return cgColor ? [NSColor colorWithCGColor:cgColor] : nil;
}

static BOOL ColorIs(NSColor *actual, NSColor *expected) {
    NSColor *a = [actual colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    NSColor *e = [expected colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    if (!a || !e) {
        return NO;
    }
    return (fabs(a.redComponent - e.redComponent) < 0.01 &&
            fabs(a.greenComponent - e.greenComponent) < 0.01 &&
            fabs(a.blueComponent - e.blueComponent) < 0.01);
}

// The low-level builder: a zippy, fast-path-eligible builder that gets a second
// attribute dictionary after some characters were appended must keep each
// character's own attributes.
- (void)testAttributeChangeMidStringKeepsEachRunsAttributes {
    iTermMutableAttributedStringBuilder *builder =
        [[iTermMutableAttributedStringBuilder alloc] initWithPreferSpeedToFullLigatureSupport:YES
                                                                          lowFiCombiningMarks:NO];
    builder.zippy = YES;
    builder.startColumn = 0;
    NSDictionary *red = @{ @"color": @"red" };
    NSDictionary *green = @{ @"color": @"green" };
    [builder setAttributes:red];
    [builder appendCharacter:'a' rtl:NO sourceCell:0 drawInCell:0];
    [builder appendCharacter:'b' rtl:NO sourceCell:1 drawInCell:1];
    [builder setAttributes:green];
    [builder appendCharacter:'c' rtl:NO sourceCell:2 drawInCell:2];
    [builder appendCharacter:'d' rtl:NO sourceCell:3 drawInCell:3];
    builder.endColumn = 4;

    NSAttributedString *string = [NSAttributedString castFrom:builder.attributedString];
    XCTAssertNotNil(string, @"Two attribute runs cannot be represented by a single-attribute cheap string");
    XCTAssertEqualObjects(string.string, @"abcd");
    for (NSUInteger i = 0; i < string.length; i++) {
        NSString *expected = i < 2 ? @"red" : @"green";
        XCTAssertEqualObjects([string attribute:@"color" atIndex:i effectiveRange:nil], expected, @"index %@", @(i));
    }
}

// End to end through iTermAttributedStringBuilder with zippy on, as in the app:
// `سلام \e[31mدن\e[32mیا خوب` on a bidi line. دنیا must stay one string (so it is
// shaped joined) with دن red and یا green. This reaches the bug only because the
// builder for a segment after the first is fast-path eligible; the builder-level
// test above is the guard that does not depend on that.
- (void)testSGRColorSplitInsideRTLWordKeepsBothColors {
    NSString *text = @"سلام دنیا خوب";
    const NSRange redRange = NSMakeRange(5, 2);    // دن
    const NSRange greenRange = NSMakeRange(7, 2);  // یا
    screen_char_t line[iTermStringToScreenCharsCapacity(32)] = { 0 };
    screen_char_t fg = { 0 };
    screen_char_t bg = { 0 };
    int width = 0;
    BOOL foundDwc = NO;
    BOOL rtlFound = NO;
    StringToScreenChars(text, line, fg, bg, &width, NO, NULL, &foundDwc, iTermUnicodeNormalizationNone, 9, NO, &rtlFound);
    XCTAssertEqual(width, (int)text.length);
    for (int i = 0; i < width; i++) {
        if (NSLocationInRange(i, redRange)) {
            line[i].foregroundColorMode = ColorModeNormal;
            line[i].foregroundColor = 1;
        } else if (NSLocationInRange(i, greenRange)) {
            line[i].foregroundColorMode = ColorModeNormal;
            line[i].foregroundColor = 2;
        }
    }
    screen_char_t continuation = { 0 };
    MutableScreenCharArray *msca = [[[ScreenCharArray alloc] initWithCopyOfLine:line
                                                                         length:width
                                                                   continuation:continuation] mutableCopy];
    iTermBidiDisplayInfo *bidi = [[iTermBidiDisplayInfo alloc] initWithScreenCharArray:msca paddedTo:width];
    XCTAssertNotNil(bidi);
    [iTermBidiDisplayInfo annotateWithBidiInfo:bidi msca:msca];

    iTermBackgroundColorRun run = {
        .modelRange = NSMakeRange(0, width),
        .visualRange = NSMakeRange(0, width),
        .bgColor = ALTSEM_DEFAULT,
        .bgColorMode = ColorModeAlternate,
    };
    CTVector(CGFloat) positions;
    CTVectorCreate(&positions, width);
    NSArray<id<iTermAttributedString>> *strings =
        [[self builder] attributedStringsForLine:msca.line
                                        bidiInfo:bidi
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

    NSAttributedString *word = nil;
    for (id<iTermAttributedString> candidate in strings) {
        const NSRange columns = [candidate sourceColumnRange];
        if (NSLocationInRange(redRange.location, columns)) {
            word = [NSAttributedString castFrom:candidate];
            break;
        }
    }
    XCTAssertNotNil(word, @"دن should be in a full attributed string");
    XCTAssertEqualObjects(word.string, @"دنیا", @"The color split must not break the word into separately shaped strings");
    if (word.length != 4) {
        return;
    }
    for (NSUInteger i = 0; i < 2; i++) {
        XCTAssertTrue(ColorIs(ColorAt(word, i), [NSColor redColor]), @"index %@ is %@", @(i), ColorAt(word, i));
    }
    for (NSUInteger i = 2; i < 4; i++) {
        XCTAssertTrue(ColorIs(ColorAt(word, i), [NSColor greenColor]), @"index %@ is %@", @(i), ColorAt(word, i));
    }
}

// QA finding F-078. Underline and strikethrough are drawn from the leftmost
// drawn position of their run. Positions are visual on a bidi line, so for a
// right-to-left run the first character of the range is the rightmost one; the
// legacy renderer started the line there, about a word's width too far right.
- (void)testUnderlineAndStrikethroughStartAtLeftmostDrawnCellOfRTLRun {
    NSString *text = @"سلام دنیا خوب تمام";
    const NSRange underlineRange = NSMakeRange(5, 4);  // دنیا
    const NSRange strikeRange = NSMakeRange(10, 3);    // خوب
    screen_char_t line[iTermStringToScreenCharsCapacity(32)] = { 0 };
    screen_char_t fg = { 0 };
    screen_char_t bg = { 0 };
    int width = 0;
    BOOL foundDwc = NO;
    BOOL rtlFound = NO;
    StringToScreenChars(text, line, fg, bg, &width, NO, NULL, &foundDwc, iTermUnicodeNormalizationNone, 9, NO, &rtlFound);
    XCTAssertEqual(width, (int)text.length);
    for (int i = 0; i < width; i++) {
        line[i].underline = NSLocationInRange(i, underlineRange);
        line[i].strikethrough = NSLocationInRange(i, strikeRange);
    }
    screen_char_t continuation = { 0 };
    MutableScreenCharArray *msca = [[[ScreenCharArray alloc] initWithCopyOfLine:line
                                                                         length:width
                                                                   continuation:continuation] mutableCopy];
    iTermBidiDisplayInfo *bidi = [[iTermBidiDisplayInfo alloc] initWithScreenCharArray:msca paddedTo:width];
    XCTAssertNotNil(bidi);
    [iTermBidiDisplayInfo annotateWithBidiInfo:bidi msca:msca];

    iTermBackgroundColorRun run = {
        .modelRange = NSMakeRange(0, width),
        .visualRange = NSMakeRange(0, width),
        .bgColor = ALTSEM_DEFAULT,
        .bgColorMode = ColorModeAlternate,
    };
    CTVector(CGFloat) positions;
    CTVectorCreate(&positions, width);
    NSArray<id<iTermAttributedString>> *strings =
        [[self builder] attributedStringsForLine:msca.line
                                        bidiInfo:bidi
                              externalAttributes:nil
                                           range:NSMakeRange(0, width)
                                 hasSelectedText:NO
                                 backgroundColor:[NSColor blackColor]
                                  forceTextColor:nil
                                        colorRun:&run
                                     findMatches:nil
                                 underlinedRange:NSMakeRange(0, 0)
                                       positions:&positions];

    const int *lut = [bidi lut];
    const CGFloat cellWidth = 7;
    NSArray<NSString *> *attributeNames = @[ NSUnderlineStyleAttributeName, NSStrikethroughStyleAttributeName ];
    NSArray<NSValue *> *logicalRanges = @[ [NSValue valueWithRange:underlineRange], [NSValue valueWithRange:strikeRange] ];
    for (NSUInteger k = 0; k < attributeNames.count; k++) {
        const NSRange logical = logicalRanges[k].rangeValue;
        int leftmostCell = INT_MAX;
        int rightmostCell = INT_MIN;
        for (NSUInteger i = logical.location; i < NSMaxRange(logical); i++) {
            leftmostCell = MIN(leftmostCell, lut[i]);
            rightmostCell = MAX(rightmostCell, lut[i]);
        }
        XCTAssertGreaterThan(rightmostCell, leftmostCell);

        __block BOOL found = NO;
        NSUInteger offset = 0;
        for (id<iTermAttributedString> candidate in strings) {
            NSAttributedString *string = [NSAttributedString castFrom:candidate];
            iTermCheapAttributedString *cheap = [iTermCheapAttributedString castFrom:candidate];
            if (cheap) {
                string = [[NSAttributedString alloc] initWithString:[NSString stringWithCharacters:cheap.characters
                                                                                            length:cheap.length]
                                                         attributes:cheap.attributes];
            }
            const NSUInteger length = [candidate length];
            if (string) {
                CGFloat *subpositions = CTVectorElementsFromIndex(&positions, offset);
                [string enumerateAttribute:attributeNames[k]
                                   inRange:NSMakeRange(0, string.length)
                                   options:0
                                usingBlock:^(NSNumber *value, NSRange range, BOOL *stop) {
                    if (value.integerValue == NSUnderlineStyleNone) {
                        return;
                    }
                    found = YES;
                    // The old code used the range's first position: the rightmost cell.
                    XCTAssertEqual(subpositions[range.location], rightmostCell * cellWidth,
                                   @"precondition: %@ run's first character is drawn rightmost", attributeNames[k]);
                    XCTAssertEqual(iTermLeftmostStringPosition(subpositions, range), leftmostCell * cellWidth,
                                   @"%@ must start at the leftmost drawn cell", attributeNames[k]);
                }];
            }
            offset += length;
        }
        XCTAssertTrue(found, @"no %@ run found", attributeNames[k]);
    }
    CTVectorDestroy(&positions);
}

#pragma mark - QA finding F-080

static MutableScreenCharArray *BidiLine(NSString *text, iTermBidiDisplayInfo **bidiOut) {
    screen_char_t line[iTermStringToScreenCharsCapacity(32)] = { 0 };
    screen_char_t fg = { 0 };
    screen_char_t bg = { 0 };
    int width = 0;
    BOOL foundDwc = NO;
    BOOL rtlFound = NO;
    StringToScreenChars(text, line, fg, bg, &width, NO, NULL, &foundDwc, iTermUnicodeNormalizationNone, 9, NO, &rtlFound);
    screen_char_t continuation = { 0 };
    MutableScreenCharArray *msca = [[[ScreenCharArray alloc] initWithCopyOfLine:line
                                                                         length:width
                                                                   continuation:continuation] mutableCopy];
    iTermBidiDisplayInfo *bidi = [[iTermBidiDisplayInfo alloc] initWithScreenCharArray:msca paddedTo:width];
    [iTermBidiDisplayInfo annotateWithBidiInfo:bidi msca:msca];
    *bidiOut = bidi;
    return msca;
}

static iTermBoxedBackgroundColorRun *BoxedRun(NSRange range, BOOL selected, BOOL isMatch, BOOL faint) {
    iTermBackgroundColorRun run = {
        .modelRange = range,
        .visualRange = range,
        .bgColor = ALTSEM_DEFAULT,
        .bgColorMode = ColorModeAlternate,
        .selected = selected,
        .isMatch = isMatch,
        .beneathFaintText = faint,
    };
    return [iTermBoxedBackgroundColorRun boxedBackgroundColorRunWithValue:run];
}

// The legacy renderer shapes each background run separately. A selection edge
// splits the background runs, so on a bidi line they must be combined or the
// Arabic word under the edge loses its joining.
- (void)testSelectionAndMatchEdgesDoNotSplitForegroundRunsOnBidiLine {
    NSArray<iTermBoxedBackgroundColorRun *> *runs = @[ BoxedRun(NSMakeRange(0, 5), NO, NO, NO),
                                                       BoxedRun(NSMakeRange(5, 2), YES, NO, NO),
                                                       BoxedRun(NSMakeRange(7, 2), NO, YES, NO),
                                                       BoxedRun(NSMakeRange(9, 4), NO, NO, NO) ];
    NSArray<iTermBoxedBackgroundColorRun *> *bidiRuns = iTermCombineBackgroundRunsForUnprocessedForeground(runs, YES);
    XCTAssertEqual(bidiRuns.count, 1u);
    XCTAssertTrue(NSEqualRanges(bidiRuns.firstObject.valuePointer->modelRange, NSMakeRange(0, 13)));
    XCTAssertFalse(bidiRuns.firstObject.valuePointer->selected,
                   @"A partly selected combined run must leave selection to the per-cell check");
    XCTAssertFalse(bidiRuns.firstObject.valuePointer->isMatch);

    // Left-to-right lines keep the old splitting.
    XCTAssertEqual(iTermCombineBackgroundRunsForUnprocessedForeground(runs, NO).count, 4u);

    // A fully selected combination stays selected.
    NSArray<iTermBoxedBackgroundColorRun *> *selectedRuns = @[ BoxedRun(NSMakeRange(0, 2), YES, NO, NO),
                                                               BoxedRun(NSMakeRange(2, 2), YES, NO, NO) ];
    NSArray<iTermBoxedBackgroundColorRun *> *combinedSelected = iTermCombineBackgroundRunsForUnprocessedForeground(selectedRuns, YES);
    XCTAssertEqual(combinedSelected.count, 1u);
    XCTAssertTrue(combinedSelected.firstObject.valuePointer->selected);

    // Faint text still splits, even on a bidi line.
    NSArray<iTermBoxedBackgroundColorRun *> *faintRuns = @[ BoxedRun(NSMakeRange(0, 5), NO, NO, NO),
                                                            BoxedRun(NSMakeRange(5, 2), YES, NO, YES) ];
    XCTAssertEqual(iTermCombineBackgroundRunsForUnprocessedForeground(faintRuns, YES).count, 2u);
}

- (NSAttributedString *)wordContainingColumn:(NSUInteger)column
                                          in:(NSArray<id<iTermAttributedString>> *)strings {
    for (id<iTermAttributedString> candidate in strings) {
        if (NSLocationInRange(column, [candidate sourceColumnRange])) {
            return [NSAttributedString castFrom:candidate];
        }
    }
    return nil;
}

// With the runs combined, one builder call spans the selection edge. The
// selected letters must get the selected text color and the rest keep theirs,
// all in one string so CoreText shapes the word joined. Every cell has the same
// screen_char_t attributes, which also exercises the builder's shortcut that
// reuses the previous cell's attributes.
- (void)testSelectionEdgeInsideRTLWordColorsPerCellInOneString {
    [self checkSelectionEdgeInsideRTLWordWithFontTable:YES];
}

- (void)testSelectionEdgeInsideRTLWordColorsPerCellWhenEquivalentCellsShareAttributes {
    [self checkSelectionEdgeInsideRTLWordWithFontTable:NO];
}

- (void)checkSelectionEdgeInsideRTLWordWithFontTable:(BOOL)withFontTable {
    _useSelectedTextColor = YES;
    iTermBidiDisplayInfo *bidi = nil;
    MutableScreenCharArray *msca = BidiLine(@"سلام دنیا خوب", &bidi);
    XCTAssertNotNil(bidi);
    const int width = msca.length;
    NSIndexSet *selected = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(5, 2)];  // دن
    iTermBackgroundColorRun run = {
        .modelRange = NSMakeRange(0, width),
        .visualRange = NSMakeRange(0, width),
        .bgColor = ALTSEM_DEFAULT,
        .bgColorMode = ColorModeAlternate,
    };
    CTVector(CGFloat) positions;
    CTVectorCreate(&positions, width);
    NSArray<id<iTermAttributedString>> *strings =
        [[self builderWithFontTable:withFontTable] attributedStringsForLine:msca.line
                                        bidiInfo:bidi
                              externalAttributes:nil
                                           range:NSMakeRange(0, width)
                                 hasSelectedText:NO
                                 selectedIndexes:selected
                                 backgroundColor:nil
                                  forceTextColor:nil
                                        colorRun:&run
                                     findMatches:nil
                                 underlinedRange:NSMakeRange(0, 0)
                                       positions:&positions];
    CTVectorDestroy(&positions);

    NSAttributedString *word = [self wordContainingColumn:5 in:strings];
    XCTAssertEqualObjects(word.string, @"دنیا", @"The selection edge must not break the word into separately shaped strings");
    if (word.length != 4) {
        return;
    }
    for (NSUInteger i = 0; i < 2; i++) {
        XCTAssertTrue(ColorIs(ColorAt(word, i), [NSColor blueColor]), @"selected index %@ is %@", @(i), ColorAt(word, i));
    }
    for (NSUInteger i = 2; i < 4; i++) {
        XCTAssertTrue(ColorIs(ColorAt(word, i), [NSColor whiteColor]), @"unselected index %@ is %@", @(i), ColorAt(word, i));
    }
    NSAttributedString *first = [self wordContainingColumn:0 in:strings];
    XCTAssertTrue(ColorIs(ColorAt(first, 0), [NSColor whiteColor]), @"unselected letter is %@", ColorAt(first, 0));
}

// Same for a find match edge inside a word: the match colors only its cells,
// and a selected cell takes the selection color instead of the match color.
- (void)testFindMatchEdgeInsideRTLWordColorsPerCellInOneString {
    _useSelectedTextColor = YES;
    iTermBidiDisplayInfo *bidi = nil;
    MutableScreenCharArray *msca = BidiLine(@"سلام دنیا خوب", &bidi);
    XCTAssertNotNil(bidi);
    const int width = msca.length;
    // The match covers columns 5 through 7; the selection covers column 7.
    unsigned char bits[2] = { 0, 0 };
    for (int i = 5; i <= 7; i++) {
        bits[i / 8] |= (1 << (i & 7));
    }
    NSData *matches = [NSData dataWithBytes:bits length:sizeof(bits)];
    iTermBackgroundColorRun run = {
        .modelRange = NSMakeRange(0, width),
        .visualRange = NSMakeRange(0, width),
        .bgColor = ALTSEM_DEFAULT,
        .bgColorMode = ColorModeAlternate,
    };
    CTVector(CGFloat) positions;
    CTVectorCreate(&positions, width);
    NSArray<id<iTermAttributedString>> *strings =
        [[self builder] attributedStringsForLine:msca.line
                                        bidiInfo:bidi
                              externalAttributes:nil
                                           range:NSMakeRange(0, width)
                                 hasSelectedText:NO
                                 selectedIndexes:[NSIndexSet indexSetWithIndex:7]
                                 backgroundColor:nil
                                  forceTextColor:nil
                                        colorRun:&run
                                     findMatches:matches
                                 underlinedRange:NSMakeRange(0, 0)
                                       positions:&positions];
    CTVectorDestroy(&positions);

    NSAttributedString *word = [self wordContainingColumn:5 in:strings];
    XCTAssertEqualObjects(word.string, @"دنیا");
    if (word.length != 4) {
        return;
    }
    NSColor *matchText = ColorAt(word, 0);
    XCTAssertFalse(ColorIs(matchText, [NSColor whiteColor]), @"matched letter should use the match text color");
    XCTAssertTrue(ColorIs(ColorAt(word, 1), matchText));
    XCTAssertTrue(ColorIs(ColorAt(word, 2), [NSColor blueColor]), @"selected letter is %@", ColorAt(word, 2));
    XCTAssertTrue(ColorIs(ColorAt(word, 3), [NSColor whiteColor]), @"unhighlighted letter is %@", ColorAt(word, 3));
}

#pragma mark - iTermAttributedStringBuilderDelegate

- (BOOL)useSelectedTextColor {
    return _useSelectedTextColor;
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
    if (isBackground) {
        return [NSColor blackColor];
    }
    if (theMode == ColorModeNormal && theIndex == 1) {
        return [NSColor redColor];
    }
    if (theMode == ColorModeNormal && theIndex == 2) {
        return [NSColor greenColor];
    }
    return [NSColor whiteColor];
}
@end
