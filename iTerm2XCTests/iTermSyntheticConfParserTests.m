//
//  iTermSyntheticConfParserTests.m
//  iTerm2XCTests
//
//  Created by George Nachman on 12/2/19.
//

#import <XCTest/XCTest.h>

#import "iTermSyntheticConfParser+Private.h"

@interface iTermTestableSyntheticConfParser: iTermSyntheticConfParser
+ (void)setFakeContents:(NSString *)string;
@end

@implementation iTermTestableSyntheticConfParser

- (void)dealloc {
    [_fakeContents release];
    [super dealloc];
}

static NSString *_fakeContents;

+ (void)setFakeContents:(NSString *)string {
    _fakeContents = [string copy];
}

+ (NSString *)contents {
    return _fakeContents;
}

@end

@interface iTermSyntheticConfParserTests : XCTestCase
@end

@implementation iTermSyntheticConfParserTests

- (void)testEmptyContents {
    iTermTestableSyntheticConfParser.fakeContents = @"";
    iTermSyntheticConfParser *parser = [[iTermTestableSyntheticConfParser alloc] initPrivate];
    XCTAssertEqual(parser.syntheticDirectories.count, 0);
}

// Example from synthetic.conf man page
static NSString *const sValidContents =
@"# create an empty directory named \"foo\" at / which may be mounted over\n"
@"foo\n"
@"\n"
@"# create a symbolic link named \"bar\" at / which points to\n"
@"# \"System/Volumes/Data/bar\", a writeable location at the root of the data volume\n"
@"bar\tSystem/Volumes/Data/bar\n"
@"# create a symbolic link named \"baz\" at / which points to \"Users/me/baz\"\n"
@"baz\tUsers/me/baz\n";

- (void)testParsingValidData {
    [iTermTestableSyntheticConfParser setFakeContents:sValidContents];
    iTermSyntheticConfParser *parser = [[iTermTestableSyntheticConfParser alloc] initPrivate];
    XCTAssertEqual(parser.syntheticDirectories.count, 2);

    {
        iTermSyntheticDirectory *bar = parser.syntheticDirectories[0];
        XCTAssertEqualObjects(@"/bar", bar.root);
        XCTAssertEqualObjects(@"/System/Volumes/Data/bar", bar.target);
    }

    {
        iTermSyntheticDirectory *baz = parser.syntheticDirectories[1];
        XCTAssertEqualObjects(@"/baz", baz.root);
        XCTAssertEqualObjects(@"/Users/me/baz", baz.target);
    }
}

- (void)testIgnoreBadInput {
    NSString *badInput =
    @"one\ttwo\tthree\n"
    @"\tx\n"
    @"y\t";
    [iTermTestableSyntheticConfParser setFakeContents:badInput];
    iTermSyntheticConfParser *parser = [[iTermTestableSyntheticConfParser alloc] initPrivate];
    XCTAssertEqual(parser.syntheticDirectories.count, 0);
}

- (void)testSubstituteExactRoot {
    [iTermTestableSyntheticConfParser setFakeContents:sValidContents];
    iTermSyntheticConfParser *parser = [[iTermTestableSyntheticConfParser alloc] initPrivate];

    XCTAssertEqualObjects(@"/baz", [parser pathByReplacingPrefixWithSyntheticRoot:@"/Users/me/baz"]);
    XCTAssertEqualObjects(@"/bar", [parser pathByReplacingPrefixWithSyntheticRoot:@"/System/Volumes/Data/bar"]);
}

- (void)testSubstituteRootWithTrailingSlash {
    [iTermTestableSyntheticConfParser setFakeContents:sValidContents];
    iTermSyntheticConfParser *parser = [[iTermTestableSyntheticConfParser alloc] initPrivate];

    XCTAssertEqualObjects(@"/baz/", [parser pathByReplacingPrefixWithSyntheticRoot:@"/Users/me/baz/"]);
}

- (void)testSubstitutePathPrefix {
    [iTermTestableSyntheticConfParser setFakeContents:sValidContents];
    iTermSyntheticConfParser *parser = [[iTermTestableSyntheticConfParser alloc] initPrivate];

    XCTAssertEqualObjects(@"/baz/foo", [parser pathByReplacingPrefixWithSyntheticRoot:@"/Users/me/baz/foo"]);
}

- (void)testDoNotSubstituteNonPathPrefix {
    [iTermTestableSyntheticConfParser setFakeContents:sValidContents];
    iTermSyntheticConfParser *parser = [[iTermTestableSyntheticConfParser alloc] initPrivate];

    XCTAssertEqualObjects(@"/bazX", [parser pathByReplacingPrefixWithSyntheticRoot:@"/bazX"]);
}

@end
