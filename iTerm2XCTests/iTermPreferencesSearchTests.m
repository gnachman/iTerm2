//
//  iTermPreferencesSearchTests.m
//  iTerm2XCTests
//
//  Created by George Nachman on 3/28/19.
//

#import <XCTest/XCTest.h>
#import "iTermPreferencesSearch.h"

@interface iTermPreferencesSearchTests : XCTestCase

@end

@implementation iTermPreferencesSearchTests {
    iTermPreferencesSearchEngine *_engine;
}

- (void)setUp {
    // Put setup code here. This method is called before the invocation of each test method in the class.
    _engine = [[iTermPreferencesSearchEngine alloc] init];
}

- (void)testDocumentTokenization {
    iTermPreferencesSearchDocument *doc1 = [iTermPreferencesSearchDocument documentWithDisplayName:@"foo bar"
                                                                                        identifier:@"id1"
                                                                                    keywordPhrases:@[ @"lorem ipsum dolor", @"sit amet" ]];
    NSArray *expected = [@[ @"foo", @"bar", @"lorem", @"ipsum", @"dolor", @"sit", @"amet" ] sortedArrayUsingSelector:@selector(compare:)];
    NSArray *actual = [doc1.allKeywords sortedArrayUsingSelector:@selector(compare:)];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testSimple {
    iTermPreferencesSearchDocument *doc1 = [iTermPreferencesSearchDocument documentWithDisplayName:@"1"
                                                                                        identifier:@"id1"
                                                                                    keywordPhrases:@[]];
    iTermPreferencesSearchDocument *doc2 = [iTermPreferencesSearchDocument documentWithDisplayName:@"2"
                                                                                        identifier:@"id2"
                                                                                    keywordPhrases:@[]];
    [_engine addDocumentToIndex:doc1];
    [_engine addDocumentToIndex:doc2];

    NSArray<iTermPreferencesSearchDocument *> *actual = [_engine documentsMatchingQuery:@"1"];
    NSArray<iTermPreferencesSearchDocument *> *expected = @[ doc1 ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testMultiword {
    iTermPreferencesSearchDocument *doc1 = [iTermPreferencesSearchDocument documentWithDisplayName:@"foo bar"
                                                                                        identifier:@"id1"
                                                                                    keywordPhrases:@[]];
    iTermPreferencesSearchDocument *doc2 = [iTermPreferencesSearchDocument documentWithDisplayName:@"bar baz foo"
                                                                                        identifier:@"id2"
                                                                                    keywordPhrases:@[]];
    iTermPreferencesSearchDocument *doc3 = [iTermPreferencesSearchDocument documentWithDisplayName:@"baz foo"
                                                                                        identifier:@"id3"
                                                                                    keywordPhrases:@[]];
    [_engine addDocumentToIndex:doc1];
    [_engine addDocumentToIndex:doc2];
    [_engine addDocumentToIndex:doc3];

    NSSet<iTermPreferencesSearchDocument *> *actual = [NSSet setWithArray:[_engine documentsMatchingQuery:@"bar foo"]];
    NSSet<iTermPreferencesSearchDocument *> *expected = [NSSet setWithArray:@[ doc1, doc2 ]];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testPrefixMatches {
    iTermPreferencesSearchDocument *doc1 = [iTermPreferencesSearchDocument documentWithDisplayName:@"aa ab ba"
                                                                                        identifier:@"id1"
                                                                                    keywordPhrases:@[]];
    iTermPreferencesSearchDocument *doc2 = [iTermPreferencesSearchDocument documentWithDisplayName:@"a"
                                                                                        identifier:@"id2"
                                                                                    keywordPhrases:@[]];
    iTermPreferencesSearchDocument *doc3 = [iTermPreferencesSearchDocument documentWithDisplayName:@"abc"
                                                                                        identifier:@"id3"
                                                                                    keywordPhrases:@[]];
    [_engine addDocumentToIndex:doc1];
    [_engine addDocumentToIndex:doc2];
    [_engine addDocumentToIndex:doc3];

    {
        NSSet<iTermPreferencesSearchDocument *> *actual = [NSSet setWithArray:[_engine documentsMatchingQuery:@"a"]];
        NSSet<iTermPreferencesSearchDocument *> *expected = [NSSet setWithArray:@[ doc1, doc2, doc3 ]];
        XCTAssertEqualObjects(actual, expected);
    }
    {
        NSSet<iTermPreferencesSearchDocument *> *actual = [NSSet setWithArray:[_engine documentsMatchingQuery:@"a b"]];
        NSSet<iTermPreferencesSearchDocument *> *expected = [NSSet setWithArray:@[ doc1 ]];
        XCTAssertEqualObjects(actual, expected);
    }
    {
        NSSet<iTermPreferencesSearchDocument *> *actual = [NSSet setWithArray:[_engine documentsMatchingQuery:@"ab"]];
        NSSet<iTermPreferencesSearchDocument *> *expected = [NSSet setWithArray:@[ doc1, doc3 ]];
        XCTAssertEqualObjects(actual, expected);
    }
}

@end
