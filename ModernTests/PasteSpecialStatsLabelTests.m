//
//  PasteSpecialStatsLabelTests.m
//  ModernTests
//
//  Regression test for the Paste Special stats label. The collapsed format
//  "%1$@ bytes in %2$@ lines." could not pluralize, so a single character showed
//  "One bytes in one lines." in English. The label now passes integer counts and
//  the catalog entry pluralizes each count independently.
//

#import <XCTest/XCTest.h>

#import "iTermPasteSpecialWindowController.h"
#import "NSStringITerm.h"

@interface PasteSpecialStatsLabelTests : XCTestCase
@end

@implementation PasteSpecialStatsLabelTests

- (void)testSingleByteAndLineAreSingular {
    NSString *s = [iTermPasteSpecialWindowController statsLabelStringForByteCount:1 lineCount:1];
    XCTAssertTrue([s containsString:@"byte"], @"expected singular 'byte', got: %@", s);
    XCTAssertFalse([s containsString:@"bytes"], @"1 byte must not be plural, got: %@", s);
    XCTAssertTrue([s containsString:@"line"], @"expected singular 'line', got: %@", s);
    XCTAssertFalse([s containsString:@"lines"], @"1 line must not be plural, got: %@", s);
}

- (void)testMultipleBytesAndLinesArePlural {
    NSString *s = [iTermPasteSpecialWindowController statsLabelStringForByteCount:5 lineCount:3];
    XCTAssertTrue([s containsString:@"bytes"], @"expected plural 'bytes', got: %@", s);
    XCTAssertTrue([s containsString:@"lines"], @"expected plural 'lines', got: %@", s);
}

// A mixed case: one byte but several lines keeps each count's own inflection.
- (void)testMixedCountsInflectIndependently {
    NSString *s = [iTermPasteSpecialWindowController statsLabelStringForByteCount:1 lineCount:4];
    XCTAssertTrue([s containsString:@"byte"], @"got: %@", s);
    XCTAssertFalse([s containsString:@"bytes"], @"got: %@", s);
    XCTAssertTrue([s containsString:@"lines"], @"got: %@", s);
}

// F-303: the label counted lines with -numberOfLines, which NSString(iTermTextDataSource)
// overrides with a split on LF, so CR-converted text read as one line and a trailing LF
// added a line.
- (void)testPreviewLineCountHandlesCRAndTrailingNewline {
    XCTAssertEqualObjects([iTermPasteSpecialWindowController statsLabelStringForPreviewString:@"1\r2\r3\r4\r5\r"],
                          [iTermPasteSpecialWindowController statsLabelStringForByteCount:10 lineCount:5]);
    XCTAssertEqualObjects([iTermPasteSpecialWindowController statsLabelStringForPreviewString:@"1\n2\n3\n4\n5\n"],
                          [iTermPasteSpecialWindowController statsLabelStringForByteCount:10 lineCount:5]);
}

- (void)testLineCount {
    XCTAssertEqual([@"" it_lineCount], 0u);
    XCTAssertEqual([@"abc" it_lineCount], 1u);
    XCTAssertEqual([@"a\nb" it_lineCount], 2u);
    XCTAssertEqual([@"a\r\nb\r\n" it_lineCount], 2u);
    XCTAssertEqual([@"a\n\nb" it_lineCount], 3u);
}

@end
