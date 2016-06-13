//
//  iTermTextExtractorTest.m
//  iTerm2
//
//  Created by George Nachman on 2/27/16.
//
//

#import <XCTest/XCTest.h>
#import "iTermPreferences.h"
#import "iTermSelectorSwizzler.h"
#import "iTermTextExtractor.h"
#import "ScreenChar.h"
#import "SmartSelectionController.h"
#import <OCHamcrest/OCHamcrest.h>
#import <OCMockito/OCMockito.h>

@interface iTermTextExtractorTest : XCTestCase<iTermTextDataSource>

@end

@implementation iTermTextExtractorTest {
    screen_char_t *_buffer;
    NSArray<NSString *> *_lines;
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
    NSUserDefaults *mockDefaults = MKTMock([NSUserDefaults class]);
    [MKTGiven([mockDefaults objectForKey:kPreferenceKeyCharactersConsideredPartOfAWordForSelection]) willReturn:extraWordCharacters];
    _lines = @[ line ];
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self];
    
    [iTermSelectorSwizzler swizzleSelector:@selector(standardUserDefaults)
                                 fromClass:[NSUserDefaults class]
                                 withBlock:^ id { return mockDefaults; }
                                  forBlock:^{
                                      VT100GridWindowedRange range;
                                      for (int i = 0; i < line.length; i++) {
                                          range = [extractor rangeForWordAt:VT100GridCoordMake(i, 0)];
                                          NSString *actual = [self stringForRange:range];
                                          XCTAssertEqualObjects(actual, expected[i],
                                                                @"For click at %@ got a range of %@ giving “%@”, while I expected “%@”",
                                                                @(i), VT100GridWindowedRangeDescription(range), actual, expected[i]);
                                      }
                                  }];
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


#pragma mark - iTermTextDataSource

- (int)lengthOfLineAtIndex:(int)theIndex withBuffer:(screen_char_t *)buffer {
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
                        NO);
    return len;
}

- (int)width {
    assert([_lines[0] length] < 50);
    screen_char_t temp[100];
    return [self lengthOfLineAtIndex:0 withBuffer:temp];
}

- (int)numberOfLines {
    return _lines.count;
}

- (screen_char_t *)getLineAtIndex:(int)theIndex {
    if (_buffer) {
        free(_buffer);
    }
    _buffer = malloc(sizeof(screen_char_t) * (self.width + 1));

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
                        NO);
    _buffer[len].code = EOL_SOFT;
    
    return _buffer;
}

- (long long)totalScrollbackOverflow {
    return 0;
}

@end
