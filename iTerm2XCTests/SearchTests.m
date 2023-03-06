//
//  SearchTests.m
//  iTerm2XCTests
//
//  Created by George Nachman on 3/2/23.
//

#import <XCTest/XCTest.h>
#import "LineBlock.h"
#import "LineBufferPosition.h"
#import "iTerm2SharedARC-Swift.h"

@interface SearchTests : XCTestCase

@end

@implementation SearchTests

- (void)setUp {
    [iTermCharacterBufferContext ensureInstanceForQueue:dispatch_get_main_queue()];
}

// `end` is inclusive.
- (ResultRange *)rangeFrom:(int)start to:(int)end {
    ResultRange *rr = [[ResultRange alloc] init];
    rr->position = start;
    rr->length = end - start + 1;
    return rr;
}

- (void)testZalgo {
    NSString *zalgo = [NSString stringWithContentsOfFile:[[NSBundle bundleForClass:[self class]] pathForResource:@"zalgo_for_unit_test" ofType:@"txt"] encoding:NSUTF8StringEncoding error:nil];
    LineBlock *block = [[LineBlock alloc] initWithRawBufferSize:8192];
    screen_char_t buf[8192];
    screen_char_t zero = { 0 };
    int len = 8192;
    BOOL foundDwc = NO;
    StringToScreenChars(zalgo, buf, zero, zero, &len, NO, nil, &foundDwc, iTermUnicodeNormalizationNone, 9, NO);
    screen_char_t eol = { .code = EOL_HARD };
    [block appendLine:buf length:len partial:NO width:80 metadata:iTermMetadataMakeImmutable(iTermMetadataDefault()) continuation:eol];

    NSMutableArray *actual = [NSMutableArray array];
    BOOL includesPartialLastLine = NO;
    [block findSubstring:@"zal"
                 options:FindOptBackwards | FindMultipleResults
                    mode:iTermFindModeSmartCaseSensitivity
                atOffset:-1
                 results:actual
         multipleResults:YES
 includesPartialLastLine:&includesPartialLastLine];

    NSArray<ResultRange *> *expected = @[
        [self rangeFrom:469 to:471],
        [self rangeFrom:0 to:2]
    ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testTrivial {
    NSString *haystack = @"abczal";
    LineBlock *block = [[LineBlock alloc] initWithRawBufferSize:8192];
    screen_char_t buf[8192];
    screen_char_t zero = { 0 };
    int len = 8192;
    BOOL foundDwc = NO;
    StringToScreenChars(haystack, buf, zero, zero, &len, NO, nil, &foundDwc, iTermUnicodeNormalizationNone, 9, NO);
    screen_char_t eol = { .code = EOL_HARD };
    [block appendLine:buf length:len partial:NO width:80 metadata:iTermMetadataMakeImmutable(iTermMetadataDefault()) continuation:eol];

    NSMutableArray *actual = [NSMutableArray array];
    BOOL includesPartialLastLine = NO;
    [block findSubstring:@"zal"
                 options:FindOptBackwards | FindMultipleResults
                    mode:iTermFindModeSmartCaseSensitivity
                atOffset:-1
                 results:actual
         multipleResults:YES
 includesPartialLastLine:&includesPartialLastLine];
    NSArray<ResultRange *> *expected = @[
        [self rangeFrom:3 to:5],
    ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testOverlapping {
    NSString *haystack = @"xxx";
    LineBlock *block = [[LineBlock alloc] initWithRawBufferSize:8192];
    screen_char_t buf[8192];
    screen_char_t zero = { 0 };
    int len = 8192;
    BOOL foundDwc = NO;
    StringToScreenChars(haystack, buf, zero, zero, &len, NO, nil, &foundDwc, iTermUnicodeNormalizationNone, 9, NO);
    screen_char_t eol = { .code = EOL_HARD };
    [block appendLine:buf length:len partial:NO width:80 metadata:iTermMetadataMakeImmutable(iTermMetadataDefault()) continuation:eol];

    NSMutableArray *actual = [NSMutableArray array];
    BOOL includesPartialLastLine = NO;
    [block findSubstring:@"xx"
                 options:FindOptBackwards | FindMultipleResults
                    mode:iTermFindModeSmartCaseSensitivity
                atOffset:-1
                 results:actual
         multipleResults:YES
 includesPartialLastLine:&includesPartialLastLine];
    NSArray<ResultRange *> *expected = @[
        [self rangeFrom:1 to:2],
        [self rangeFrom:0 to:1],
    ];
    XCTAssertEqualObjects(actual, expected);
}

@end
