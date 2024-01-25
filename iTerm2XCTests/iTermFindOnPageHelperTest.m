// TODO: Some day fix the unit tests
#if 0

//
//  iTermFindOnPageHelperTest.m
//  iTerm2
//
//  Created by George Nachman on 7/1/17.
//
//

#import <XCTest/XCTest.h>
#import "iTermFindOnPageHelper.h"
#import "FindContext.h"
#import "SearchResult.h"

@interface iTermFindOnPageHelperTest : XCTestCase

@end

@implementation iTermFindOnPageHelperTest{
    FindContext *findContext;
    iTermFindOnPageHelper *helper;
}

- (void)setUp {
    findContext = [[[FindContext alloc] init] autorelease];
    helper = [[[iTermFindOnPageHelper alloc] init] autorelease];
    [helper findString:@"test"
      forwardDirection:NO
                  mode:iTermFindModeCaseInsensitiveSubstring
            withOffset:0
               context:findContext
         numberOfLines:100
totalScrollbackOverflow:0
   scrollToFirstResult:YES
                 force:NO];
}

- (void)testFindRangeOfSearchResults_Random {
    for (int j = 0; j < 10000; j++) {
        srand(j);
        findContext = [[[FindContext alloc] init] autorelease];
        helper = [[[iTermFindOnPageHelper alloc] init] autorelease];
        [helper findString:@"test"
          forwardDirection:NO
                      mode:iTermFindModeCaseInsensitiveSubstring
                withOffset:0
                   context:findContext
             numberOfLines:100
   totalScrollbackOverflow:0
       scrollToFirstResult:YES
                     force:NO];
        int x = 0;
        int n = 1 + rand() % 23;
        NSMutableArray<NSNumber *> *values = [NSMutableArray array];
        for (int i = 0; i < n; i++) {
            SearchResult *r = [[[SearchResult alloc] init] autorelease];
            r.absStartY = rand() % 20;
            r.startX = x++;
            [values addObject:@(r.absStartY)];
            [helper addSearchResult:r width:80];
        }
        [values sortUsingComparator:^NSComparisonResult(NSNumber * _Nonnull obj1, NSNumber * _Nonnull obj2) {
            return [obj2 compare:obj1];
        }];

        for (int k = 0; k < 100; k++) {
            NSRange range = NSMakeRange(rand() % 30, rand() % 30);
            NSRange actual = [helper rangeOfSearchResultsInRangeOfLines:range];
            NSRange expected = NSMakeRange(NSNotFound, 0);
            for (int i = 0; i < values.count; i++) {
                if (values[i].integerValue < NSMaxRange(range)) {
                    expected.location = i;
                    break;
                }
            }
            if (expected.location != NSNotFound) {
                for (int i = values.count - 1; i >= 0; i--) {
                    if (values[i].integerValue >= range.location) {
                        expected.length = i - expected.location + 1;
                        break;
                    }
                }
                if (expected.length == 0) {
                    expected.location = NSNotFound;
                }
            }
            XCTAssertTrue(NSEqualRanges(actual, expected), @"Unequal ranges for values %@ and query location=%@ length=%@. Actual=%@, expected=%@",
                          values, @(range.location), @(range.length), NSStringFromRange(actual), NSStringFromRange(expected));
        }
    }
}

- (void)testFindRangeOfSearchResults_Basic {
    for (NSNumber *y in @[ @10, @20, @30, @35, @40, @50, @60 ]) {
        SearchResult *r = [[[SearchResult alloc] init] autorelease];
        r.absStartY = y.integerValue;
        [helper addSearchResult:r width:80];
    }

    NSRange actual = [helper rangeOfSearchResultsInRangeOfLines:NSMakeRange(30, 11)];
    NSRange expected = NSMakeRange(2, 3);
    XCTAssertTrue(NSEqualRanges(actual, expected));
}

- (void)testFindRangeOfSearchResults_MultiMin {
    int x = 0;
    for (NSNumber *y in @[ @10, @20, @30, @30, @30, @35, @40, @50, @60 ]) {
        SearchResult *r = [[[SearchResult alloc] init] autorelease];
        r.absStartY = y.integerValue;
        r.startX = x++;
        [helper addSearchResult:r width:80];
    }

    NSRange actual = [helper rangeOfSearchResultsInRangeOfLines:NSMakeRange(30, 11)];
    NSRange expected = NSMakeRange(2, 5);
    XCTAssertTrue(NSEqualRanges(actual, expected));
}

- (void)testFindRangeOfSearchResults_MultiMax {
    int x = 0;
    for (NSNumber *y in @[ @10, @20, @30, @35, @40, @40, @40, @50, @60 ]) {
        SearchResult *r = [[[SearchResult alloc] init] autorelease];
        r.absStartY = y.integerValue;
        r.startX = x++;
        [helper addSearchResult:r width:80];
    }

    NSRange actual = [helper rangeOfSearchResultsInRangeOfLines:NSMakeRange(30, 11)];
    NSRange expected = NSMakeRange(2, 5);
    XCTAssertTrue(NSEqualRanges(actual, expected));
}

- (void)testFindRangeOfSearchResults_InexactMin {
    for (NSNumber *y in @[ @10, @20, @30, @35, @40, @50, @60 ]) {
        SearchResult *r = [[[SearchResult alloc] init] autorelease];
        r.absStartY = y.integerValue;
        [helper addSearchResult:r width:80];
    }

    NSRange actual = [helper rangeOfSearchResultsInRangeOfLines:NSMakeRange(25, 11)];
    NSRange expected = NSMakeRange(3, 2);
    XCTAssertTrue(NSEqualRanges(actual, expected));
}

- (void)testFindRangeOfSearchResults_InexactMax {
    for (NSNumber *y in @[ @10, @20, @30, @35, @40, @50, @60 ]) {
        SearchResult *r = [[[SearchResult alloc] init] autorelease];
        r.absStartY = y.integerValue;
        [helper addSearchResult:r width:80];
    }

    NSRange actual = [helper rangeOfSearchResultsInRangeOfLines:NSMakeRange(30, 15)];
    NSRange expected = NSMakeRange(2, 3);
    XCTAssertTrue(NSEqualRanges(actual, expected));
}

- (void)testFindRangeOfSearchResults_NoResults {
    for (NSNumber *y in @[ @10, @20, @30, @35, @40, @50, @60 ]) {
        SearchResult *r = [[[SearchResult alloc] init] autorelease];
        r.absStartY = y.integerValue;
        [helper addSearchResult:r width:80];
    }

    NSRange actual = [helper rangeOfSearchResultsInRangeOfLines:NSMakeRange(11, 5)];
    XCTAssertEqual(actual.length, 0);
}

@end

#endif
