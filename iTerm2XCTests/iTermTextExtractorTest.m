//
//  iTermTextExtractorTest.m
//  iTerm2
//
//  Created by George Nachman on 2/27/16.
//
//

#import <XCTest/XCTest.h>
#import "iTermAdvancedSettingsModel.h"
#import "iTermFakeUserDefaults.h"
#import "iTermMalloc.h"
#import "iTermPreferences.h"
#import "iTermSelectorSwizzler.h"
#import "iTermTextExtractor.h"
#import "NSStringITerm.h"
#import "ScreenChar.h"
#import "SmartSelectionController.h"

static const NSInteger kUnicodeVersion = 9;

@interface iTermTextExtractorTest : XCTestCase<iTermTextDataSource>

@end

@implementation iTermTextExtractorTest {
    screen_char_t *_buffer;
    NSArray *_lines;  // Contains either NSString* or NSData*.
}

- (void)tearDown {
    if (_buffer) {
        free(_buffer);
    }
}

- (void)testASCIIWordSelection {
    NSString *line = @"word 123   abc/def afl-cio !@-";
    NSArray *words = @[ @"word",
                        @"word",
                        @"word",
                        @"word",
                        @" ",
                        @"123",
                        @"123",
                        @"123",
                        @"   ",
                        @"   ",
                        @"   ",
                        @"abc",
                        @"abc",
                        @"abc",
                        @"/",
                        @"def",
                        @"def",
                        @"def",
                        @" ",
                        @"afl-cio",
                        @"afl-cio",
                        @"afl-cio",
                        @"afl-cio",
                        @"afl-cio",
                        @"afl-cio",
                        @"afl-cio",
                        @" ",
                        @"!",
                        @"@",
                        @"-" ];
    [self performTestForWordSelectionUsingLine:line
                          wordForEachCharacter:words
                           extraWordCharacters:@"-"];
}

- (void)testChineseWordSelection {
    NSString *line = @"翻真的翻";
    NSArray *words = @[
                       @"翻",
                       @"翻",  // double-width extension
                       @"真的",
                       @"真的",  // double-width extension
                       @"真的",
                       @"真的",  // double-width extension
                       @"翻",
                       @"翻" ];  // double-width extension
    [self performTestForWordSelectionUsingLine:line
                          wordForEachCharacter:words
                           extraWordCharacters:@"-"];
}

- (void)testChineseWithWhitelistedCharacters {
    NSString *line = @"真的-真的";
    NSArray *words = @[ @"真的-真的",  // 真
                        @"真的-真的",  // 真 DWC
                        @"真的-真的",  // 的
                        @"真的-真的",  // 的 DWC
                        @"真的-真的",  // -
                        @"真的-真的",  // 真
                        @"真的-真的",  // 真 DWC
                        @"真的-真的",  // 的
                        @"真的-真的" ];  // 的 DWC
    [self performTestForWordSelectionUsingLine:line
                          wordForEachCharacter:words
                           extraWordCharacters:@"-"];
}

- (void)testSurrogatePairWordSelection {
    NSString *line = @"𦍌次";
    NSArray *words = @[ @"𦍌",
                        @"𦍌",  // DWC_RIGHT
                        @"次",
                        @"次"];  // DWC_RIGHT
    [self performTestForWordSelectionUsingLine:line
                          wordForEachCharacter:words
                           extraWordCharacters:@"-"];
}

- (void)performTestForWordSelectionUsingLine:(NSString *)line
                        wordForEachCharacter:(NSArray<NSString *> *)expected
                         extraWordCharacters:(NSString *)extraWordCharacters {
    iTermFakeUserDefaults *fakeDefaults = [[[iTermFakeUserDefaults alloc] init] autorelease];
    [fakeDefaults setFakeObject:extraWordCharacters forKey:kPreferenceKeyCharactersConsideredPartOfAWordForSelection];
    _lines = @[ line ];
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];

    [iTermSelectorSwizzler swizzleSelector:@selector(standardUserDefaults)
                                 fromClass:[NSUserDefaults class]
                                 withBlock:^ id { return fakeDefaults; }
                                  forBlock:^{
                                      [iTermAdvancedSettingsModel loadAdvancedSettingsFromUserDefaults];
                                      VT100GridWindowedRange range;
                                      for (int i = 0; i < line.length; i++) {
                                          range = [extractor rangeForWordAt:VT100GridCoordMake(i, 0)
                                                              maximumLength:kReasonableMaximumWordLength];
                                          NSString *actual = [self stringForRange:range];
                                          XCTAssertEqualObjects(actual, expected[i],
                                                                @"For click at %@ got a range of %@ giving “%@”, while I expected “%@”",
                                                                @(i), VT100GridWindowedRangeDescription(range), actual, expected[i]);
                                      }
                                  }];
}

- (void)testSmartSelectionRulesPlistParseable {
    NSArray *rules = [SmartSelectionController defaultRules];
    XCTAssertTrue(rules.count > 0, @"No default smart selection rules");
}

// Ensures double-width characters are handled properly.
- (void)testDoubleWidthCharacterSmartSelection {
    _lines = @[ @"blah 页页的翻真的很不方便.txt blah" ];
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    VT100GridWindowedRange range;
    NSDictionary *rule = @{ kRegexKey: @"\\S+",
                            kPrecisionKey: kVeryHighPrecision };

    SmartMatch *match = [extractor smartSelectionAt:VT100GridCoordMake(10, 0)
                                          withRules:@[ rule ]
                                     actionRequired:NO
                                              range:&range
                                   ignoringNewlines:NO];
    XCTAssertNotNil(match);
    XCTAssertEqual(match.startX, 5);
    XCTAssertEqual(match.endX, 29);
    XCTAssertEqual(match.absStartY, 0);
    XCTAssertEqual(match.absEndY, 0);
}

// TODO(georgen): Support windowed ranges.
- (NSString *)stringForRange:(VT100GridWindowedRange)range {
    NSMutableString *string = [NSMutableString string];
    int width = self.width;
    int x = range.coordRange.start.x;
    for (int y = range.coordRange.start.y; y <= range.coordRange.end.y; y++) {
        screen_char_t temp[100];
        [self lengthOfLineAtIndex:y withBuffer:temp];
        int xLimit;
        if (y == range.coordRange.end.y) {
            xLimit = range.coordRange.end.x;
        } else {
            xLimit = width;
        }
        while (x < xLimit) {
            if (temp[x].code != DWC_RIGHT && temp[x].code != DWC_SKIP) {
                [string appendString:ScreenCharToStr(temp + x)];
            }
            x++;
        }
    }
    return string;
}

- (void)testRangeByTrimmingWhitespace_TrimBothEnds {
  _lines = @[ @"  foo  " ];
  iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
  VT100GridAbsCoordRange actual = [extractor rangeByTrimmingWhitespaceFromRange:VT100GridAbsCoordRangeMake(0, 0, 7, 0)];
  VT100GridAbsCoordRange expected = VT100GridAbsCoordRangeMake(2, 0, 5, 0);
  XCTAssertEqual(actual.start.x, expected.start.x);
  XCTAssertEqual(actual.start.y, expected.start.y);
  XCTAssertEqual(actual.end.x, expected.end.x);
  XCTAssertEqual(actual.end.y, expected.end.y);
}

- (void)testRangeByTrimmingWhitespace_TrimLeft {
  _lines = @[ @"  foo" ];
  iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
  VT100GridAbsCoordRange actual = [extractor rangeByTrimmingWhitespaceFromRange:VT100GridAbsCoordRangeMake(0, 0, 5, 0)];
  VT100GridAbsCoordRange expected = VT100GridAbsCoordRangeMake(2, 0, 5, 0);
  XCTAssertEqual(actual.start.x, expected.start.x);
  XCTAssertEqual(actual.start.y, expected.start.y);
  XCTAssertEqual(actual.end.x, expected.end.x);
  XCTAssertEqual(actual.end.y, expected.end.y);
}

- (void)testRangeByTrimmingWhitespace_TrimRight {
  _lines = @[ @"foo  " ];
  iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
  VT100GridAbsCoordRange actual = [extractor rangeByTrimmingWhitespaceFromRange:VT100GridAbsCoordRangeMake(0, 0, 5, 0)];
  VT100GridAbsCoordRange expected = VT100GridAbsCoordRangeMake(0, 0, 3, 0);
  XCTAssertEqual(actual.start.x, expected.start.x);
  XCTAssertEqual(actual.start.y, expected.start.y);
  XCTAssertEqual(actual.end.x, expected.end.x);
  XCTAssertEqual(actual.end.y, expected.end.y);
}

- (void)testRangeByTrimmingWhitespace_NothingToTrim {
  _lines = @[ @"foo" ];
  iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
  VT100GridAbsCoordRange actual = [extractor rangeByTrimmingWhitespaceFromRange:VT100GridAbsCoordRangeMake(0, 0, 3, 0)];
  VT100GridAbsCoordRange expected = VT100GridAbsCoordRangeMake(0, 0, 3, 0);
  XCTAssertEqual(actual.start.x, expected.start.x);
  XCTAssertEqual(actual.start.y, expected.start.y);
  XCTAssertEqual(actual.end.x, expected.end.x);
  XCTAssertEqual(actual.end.y, expected.end.y);
}

- (void)testRangeByTrimmingWhitespace_MultiLine {
  _lines = @[ @"  fooba", @"123456 ", @"       " ];
  iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
  VT100GridAbsCoordRange actual = [extractor rangeByTrimmingWhitespaceFromRange:VT100GridAbsCoordRangeMake(0, 0, 7, 2)];
  VT100GridAbsCoordRange expected = VT100GridAbsCoordRangeMake(2, 0, 6, 1);
  XCTAssertEqual(actual.start.x, expected.start.x);
  XCTAssertEqual(actual.start.y, expected.start.y);
  XCTAssertEqual(actual.end.x, expected.end.x);
  XCTAssertEqual(actual.end.y, expected.end.y);
}

- (void)testContentInRange_TruncateHeadSearchingBackwards_Huge {
    // Make a big array like
    // abc
    // ***
    // ... repeats many times ...
    // ***
    // xyz
    NSMutableArray *temp = [NSMutableArray array];
    NSUInteger length = 0;
    [temp addObject:@"abc"];
    while (length < 1024*200) {
        [temp addObject:@"***"];
        length += 3;
    }
    [temp addObject:@"xyz"];
    _lines = temp;

    // Extract the whole range but truncate it 3 bytes at the head.
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    VT100GridWindowedRange range = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 3, _lines.count), 0, 0);
    NSMutableArray *coords = [NSMutableArray array];
    NSString *actual = [extractor contentInRange:range
                               attributeProvider:nil
                                      nullPolicy:kiTermTextExtractorNullPolicyFromLastToEnd
                                             pad:NO
                              includeLastNewline:NO
                          trimTrailingWhitespace:NO
                                    cappedAtSize:3
                                    truncateTail:NO
                               continuationChars:nil
                                          coords:coords];
    XCTAssertEqualObjects(@"xyz", actual);
    XCTAssertEqual(coords.count, 3);
}

- (void)testContentInRange_TruncateHeadSearchingBackwards_NotHuge {
    // Make a big array like
    // abc
    // ***
    // ... repeats many times ...
    // ***
    // xyz
    NSMutableArray *temp = [NSMutableArray array];
    NSUInteger length = 0;
    [temp addObject:@"abc"];
    while (length < 5) {
        [temp addObject:@"***"];
        length += 3;
    }
    [temp addObject:@"xyz"];
    _lines = temp;

    // Extract the whole range but truncate it 3 bytes at the head.
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    VT100GridWindowedRange range = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 3, _lines.count), 0, 0);
    NSMutableArray *coords = [NSMutableArray array];
    NSString *actual = [extractor contentInRange:range
                               attributeProvider:nil
                                      nullPolicy:kiTermTextExtractorNullPolicyFromLastToEnd
                                             pad:NO
                              includeLastNewline:NO
                          trimTrailingWhitespace:NO
                                    cappedAtSize:3
                                    truncateTail:NO
                               continuationChars:nil
                                          coords:coords];
    XCTAssertEqualObjects(@"xyz", actual);
    XCTAssertEqual(coords.count, 3);
}

- (void)testContentInRange_TruncateHeadAndTail {
    // Make a big array like
    // abc
    // ***
    // ... repeats many times ...
    // ***
    // xyz
    NSMutableArray *temp = [NSMutableArray array];
    NSUInteger length = 0;
    [temp addObject:@"abc"];
    while (length < 1024*200) {
        [temp addObject:@"***"];
        length += 3;
    }
    [temp addObject:@"xyz"];
    _lines = temp;

    // Extract the whole range but truncate it 3 bytes at the head.
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    VT100GridWindowedRange range = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 3, _lines.count), 0, 0);
    NSString *actual = [extractor contentInRange:range
                               attributeProvider:nil
                                      nullPolicy:kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal
                                             pad:NO
                              includeLastNewline:NO
                          trimTrailingWhitespace:NO
                                    cappedAtSize:3
                                    truncateTail:NO
                               continuationChars:nil
                                          coords:nil];
    XCTAssertEqualObjects(@"xyz", actual);

    // Same thing but truncate to 3 bytes at the tail.
    actual = [extractor contentInRange:range
                     attributeProvider:nil
                            nullPolicy:kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal
                                   pad:NO
                    includeLastNewline:NO
                trimTrailingWhitespace:NO
                          cappedAtSize:3
                          truncateTail:YES
                     continuationChars:nil
                                coords:nil];
    XCTAssertEqualObjects(@"abc", actual);
}

- (void)testContentInRange_RemoveTabFillers {
    NSString *line = @"a\uf001\uf001\tb";
    NSMutableData *data = [NSMutableData dataWithLength:(line.length + 1) * sizeof(screen_char_t)];

    screen_char_t color = { 0 };
    int len = 0;
    StringToScreenChars(line,
                        data.mutableBytes,
                        color,
                        color,
                        &len,
                        NO,
                        NULL,
                        NULL,
                        NO,
                        kUnicodeVersion,
                        NO);
    screen_char_t *buffer = data.mutableBytes;
    // Turn replacement characters into tab fillers. StringToScreenChars removes private range codes.
    buffer[1].code = TAB_FILLER;
    buffer[2].code = TAB_FILLER;
    buffer[len].code = EOL_SOFT;

    _lines = @[ data ];

    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    VT100GridWindowedRange range = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 5, 1), 0, 0);
    NSString *actual = [extractor contentInRange:range
                               attributeProvider:nil
                                      nullPolicy:kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal
                                             pad:NO
                              includeLastNewline:NO
                          trimTrailingWhitespace:NO
                                    cappedAtSize:-1
                                    truncateTail:NO
                               continuationChars:nil
                                          coords:nil];
    XCTAssertEqualObjects(@"a\tb", actual);

}

- (void)testContentInRange_ConvertOrphanTabFillersToSpaces {
    NSString *line = @"ab\uf001\uf001c";
    NSMutableData *data = [NSMutableData dataWithLength:(line.length + 1) * sizeof(screen_char_t)];

    screen_char_t color = { 0 };
    int len = 0;
    StringToScreenChars(line,
                        data.mutableBytes,
                        color,
                        color,
                        &len,
                        NO,
                        NULL,
                        NULL,
                        NO,
                        kUnicodeVersion,
                        NO);
    screen_char_t *buffer = data.mutableBytes;
    // Turn replacement characters into tab fillers. StringToScreenChars removes private range codes.
    buffer[2].code = TAB_FILLER;
    buffer[3].code = TAB_FILLER;
    buffer[len].code = EOL_SOFT;

    _lines = @[ data ];

    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    VT100GridWindowedRange range = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 5, 1), 0, 0);
    NSString *actual = [extractor contentInRange:range
                               attributeProvider:nil
                                      nullPolicy:kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal
                                             pad:NO
                              includeLastNewline:NO
                          trimTrailingWhitespace:NO
                                    cappedAtSize:-1
                                    truncateTail:NO
                               continuationChars:nil
                                          coords:nil];
    XCTAssertEqualObjects(@"ab  c", actual);
}

- (void)testWrappedString {
    // cell       0     0     12345
    _lines = @[ @"\u2716\ufe0e https://example.com/" ];
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    iTermLocatedString *prefix =
    [extractor wrappedLocatedStringAt:VT100GridCoordMake(5, 0)
                                          forward:NO
                              respectHardNewlines:YES
                                         maxChars:4096
                                continuationChars:[NSMutableIndexSet indexSet]
                              convertNullsToSpace:NO];
    XCTAssertEqualObjects(prefix.string, @"\u2716\ufe0e htt");
    XCTAssertEqual(prefix.coords.count, prefix.string.length);
    int expected[] = { 0, 0, 1, 2, 3, 4 };
    for (int i = 0; i < sizeof(expected) / sizeof(*expected); i++) {
        NSValue *value = prefix.coords[i];
        VT100GridCoord coord = [value gridCoordValue];
        XCTAssertEqual(expected[i], coord.x);
        XCTAssertEqual(0, coord.y);
    }
}

- (void)appendWrappedLine:(NSString *)line width:(int)width eol:(int)eol {
    NSMutableData *data = [NSMutableData dataWithLength:(width + 1) * sizeof(screen_char_t)];
    screen_char_t color = { 0 };
    int len = 0;
    StringToScreenChars(line,
                        data.mutableBytes,
                        color,
                        color,
                        &len,
                        NO,
                        NULL,
                        NULL,
                        NO,
                        kUnicodeVersion,
                        NO);
    screen_char_t *buffer = (screen_char_t *)data.mutableBytes;
    buffer[width].code = eol;
    if (!_lines) {
        _lines = @[];
    }
    _lines = [_lines arrayByAddingObject:data];
}

- (void)testRangeForWrappedLine_MaxChars {
    for (int i = 0; i < 10; i++) {
        [self appendWrappedLine:@"1234567890"
                          width:10
                            eol:i < 9 ? EOL_SOFT : EOL_HARD];
    }
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    VT100GridWindowedRange range = [extractor rangeForWrappedLineEncompassing:VT100GridCoordMake(5, 5) respectContinuations:NO maxChars:20];
    XCTAssertEqual(range.coordRange.start.x, 0);
    XCTAssertEqual(range.coordRange.start.y, 2);
    XCTAssertEqual(range.coordRange.end.x, 10);
    XCTAssertEqual(range.coordRange.end.y, 8);
}

- (void)testRangeForWrappedLine_EOL_DWC {
    [self appendWrappedLine:@"asdf" width:30 eol:EOL_HARD];
    [self appendWrappedLine:[NSString stringWithFormat:@"111111111111111111111111111中%C%C", DWC_RIGHT, DWC_SKIP] width:30 eol:EOL_DWC];
    [self appendWrappedLine:@"文" width:30 eol:EOL_HARD];

    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    VT100GridWindowedRange range = [extractor rangeForWrappedLineEncompassing:VT100GridCoordMake(5, 1) respectContinuations:NO maxChars:1000];
    XCTAssertEqual(range.coordRange.start.x, 0);
    XCTAssertEqual(range.coordRange.start.y, 1);
    XCTAssertEqual(range.coordRange.end.x, 30);
    XCTAssertEqual(range.coordRange.end.y, 2);
}

- (void)testRangeForWrappedLine_EOL_SOFT {
    [self appendWrappedLine:@"asdf" width:30 eol:EOL_HARD];
    [self appendWrappedLine:[NSString stringWithFormat:@"111111111111111111111111111xyz"] width:30 eol:EOL_SOFT];
    [self appendWrappedLine:@"hello world" width:30 eol:EOL_HARD];

    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    VT100GridWindowedRange range = [extractor rangeForWrappedLineEncompassing:VT100GridCoordMake(5, 1) respectContinuations:NO maxChars:1000];
    XCTAssertEqual(range.coordRange.start.x, 0);
    XCTAssertEqual(range.coordRange.start.y, 1);
    XCTAssertEqual(range.coordRange.end.x, 30);
    XCTAssertEqual(range.coordRange.end.y, 2);
}

- (void)testRangeForWrappedLine_EOL_HARD {
    [self appendWrappedLine:@"asdf" width:30 eol:EOL_HARD];
    [self appendWrappedLine:[NSString stringWithFormat:@"111111111111111111111111111xyz"] width:30 eol:EOL_HARD];
    [self appendWrappedLine:@"hello world" width:30 eol:EOL_HARD];

    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    VT100GridWindowedRange range = [extractor rangeForWrappedLineEncompassing:VT100GridCoordMake(5, 1) respectContinuations:NO maxChars:1000];
    XCTAssertEqual(range.coordRange.start.x, 0);
    XCTAssertEqual(range.coordRange.start.y, 1);
    XCTAssertEqual(range.coordRange.end.x, 30);
    XCTAssertEqual(range.coordRange.end.y, 1);
}

- (void)testBinarySearch_ExactMatch {
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    NSInteger actual = [extractor indexInSortedArray:@[ @10, @20, @30 ]
                          withValueLessThanOrEqualTo:20
                               searchingBackwardFrom:2];
    XCTAssertEqual(actual, 1);
}

- (void)testBinarySearch_ExactMatchWithMultipleEqualValues {
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    NSInteger actual = [extractor indexInSortedArray:@[ @10, @20, @20, @30 ]
                          withValueLessThanOrEqualTo:20
                               searchingBackwardFrom:3];
    XCTAssertEqual(actual, 2);
}

- (void)testBinarySearch_BetweenValues {
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    NSInteger actual = [extractor indexInSortedArray:@[ @10, @20, @30 ]
                          withValueLessThanOrEqualTo:25
                               searchingBackwardFrom:2];
    XCTAssertEqual(actual, 1);
}

- (void)testBinarySearch_AtEnd {
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    NSInteger actual = [extractor indexInSortedArray:@[ @10, @20, @30 ]
                          withValueLessThanOrEqualTo:40
                               searchingBackwardFrom:2];
    XCTAssertEqual(actual, 2);
}

- (void)testBinarySearch_AtStart {
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    NSInteger actual = [extractor indexInSortedArray:@[ @10, @20, @30 ]
                          withValueLessThanOrEqualTo:5
                               searchingBackwardFrom:2];
    XCTAssertEqual(actual, 0);
}

- (void)testBinarySearch_RespectsStartLocation {
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    NSInteger actual = [extractor indexInSortedArray:@[ @10, @20, @30 ]
                          withValueLessThanOrEqualTo:40
                               searchingBackwardFrom:1];
    XCTAssertEqual(actual, 1);
}

- (void)testHaveNonWhitespaceInFirstLineOfRange_OneLineOfWhitespace {
    // u+2003 is em space
    [self appendWrappedLine:@"  \t \u2003 " width:30 eol:EOL_HARD];
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    VT100GridWindowedRange range = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 0, _lines.count), 0, 0);
    BOOL actual = [extractor haveNonWhitespaceInFirstLineOfRange:range];
    XCTAssertFalse(actual);
}

- (void)testHaveNonWhitespaceInFirstLineOfRange_NonWhitespaceOnSecondLine {
    // u+2003 is em space
    [self appendWrappedLine:@"  \t \u2003 " width:30 eol:EOL_HARD];
    [self appendWrappedLine:@"x" width:30 eol:EOL_HARD];
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    VT100GridWindowedRange range = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 0, _lines.count), 0, 0);
    BOOL actual = [extractor haveNonWhitespaceInFirstLineOfRange:range];
    XCTAssertFalse(actual);
}

- (void)testHaveNonWhitespaceInFirstLineOfRange_NonWhitespaceOnFirstLine {
    // u+2003 is em space
    [self appendWrappedLine:@"  \tx \u2003 " width:30 eol:EOL_HARD];
    [self appendWrappedLine:@"x" width:30 eol:EOL_HARD];
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    VT100GridWindowedRange range = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 0, _lines.count), 0, 0);
    BOOL actual = [extractor haveNonWhitespaceInFirstLineOfRange:range];
    XCTAssertTrue(actual);
}

- (void)testHaveNonWhitespaceInFirstLineOfRange_ComplexNonWhitespaceOnFirstLine {
    // u+2003 is em space
    [self appendWrappedLine:@"  \t😀 \u2003 " width:30 eol:EOL_HARD];
    [self appendWrappedLine:@"x" width:30 eol:EOL_HARD];
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    VT100GridWindowedRange range = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 0, _lines.count), 0, 0);
    BOOL actual = [extractor haveNonWhitespaceInFirstLineOfRange:range];
    XCTAssertTrue(actual);
}

#pragma mark - iTermTextDataSource

- (int)lengthOfLineAtIndex:(int)theIndex withBuffer:(screen_char_t *)buffer {
    if ([_lines[0] isKindOfClass:[NSData class]]) {
        NSData *data = _lines[0];
        int length = (data.length / sizeof(screen_char_t)) - 1;
        memmove(buffer, data.bytes, length * sizeof(screen_char_t));
        return length;
    } else {
        screen_char_t color = { 0 };
        int len = 0;
        StringToScreenChars(_lines[0],
                            buffer,
                            color,
                            color,
                            &len,
                            NO,
                            NULL,
                            NULL,
                            NO,
                            kUnicodeVersion,
                            NO);
        return len;
    }
}

- (int)width {
    if ([_lines[0] isKindOfClass:[NSData class]]) {
        NSData *data = _lines[0];
        return (data.length / sizeof(screen_char_t)) - 1;
    } else {
        assert([_lines[0] length] < 50);
        screen_char_t temp[100];
        return [self lengthOfLineAtIndex:0 withBuffer:temp];
    }
}

- (int)numberOfLines {
    return _lines.count;
}

- (ScreenCharArray *)screenCharArrayForLine:(int)line {
    const screen_char_t *sct = [self getLineAtIndex:line];
    const int width = self.width;
    return [[ScreenCharArray alloc] initWithLine:sct
                                          length:width
                                    continuation:sct[width]];
}

- (const screen_char_t *)getLineAtIndex:(int)theIndex {
    if (_buffer) {
        free(_buffer);
    }
    _buffer = iTermMalloc(sizeof(screen_char_t) * (self.width + 1));
    if ([_lines[0] isKindOfClass:[NSData class]]) {
        NSData *data = _lines[theIndex];
        memmove(_buffer, data.bytes, sizeof(screen_char_t) * (self.width + 1));
    } else {
        screen_char_t color = { 0 };
        int len = 0;
        StringToScreenChars(_lines[theIndex],
                            _buffer,
                            color,
                            color,
                            &len,
                            NO,
                            NULL,
                            NULL,
                            NO,
                            kUnicodeVersion,
                            NO);
        _buffer[len].code = EOL_SOFT;
    }

    return _buffer;
}

- (long long)totalScrollbackOverflow {
    return 0;
}

- (iTermExternalAttributeIndex *)externalAttributeIndexForLine:(int)y {
    return nil;
}

- (id)fetchLine:(int)line block:(id (^ NS_NOESCAPE)(ScreenCharArray *))block {
    ScreenCharArray *sca = [self screenCharArrayForLine:line];
    return block(sca);
}


- (ScreenCharArray *)screenCharArrayAtScreenIndex:(int)index {
    return [self screenCharArrayForLine:index];
}


@end
