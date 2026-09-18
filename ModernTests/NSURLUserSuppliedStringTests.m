//
//  NSURLUserSuppliedStringTests.m
//  ModernTests
//
//  Tests for +[NSURL(iTerm) URLWithUserSuppliedString:], especially the handling of
//  partially percent-encoded paths (issue 12914).
//

#import <XCTest/XCTest.h>

#import "NSURL+iTerm.h"

@interface NSURLUserSuppliedStringTests : XCTestCase
@end

@implementation NSURLUserSuppliedStringTests

// Regression test for issue 12914. ripgrep's --hyperlink-format=file emits OSC 8 URLs whose path
// mixes existing percent-encoding (space -> %20) with raw non-ASCII bytes (Cyrillic left as-is).
// macOS 14's lenient +URLWithString: double-encodes the percent signs, turning Test%20Folder into
// Test%2520Folder, which resolves to the wrong path. The result must preserve the single-encoded
// space and encode the non-ASCII bytes, so that .path round-trips back to the real filename.
- (void)testMixedPercentEncodingAndNonASCIIPath {
    NSString *input = @"file://MCA/Users/vova/Downloads/rg/Test%20Folder/абв.txt";
    NSURL *url = [NSURL URLWithUserSuppliedString:input];
    XCTAssertNotNil(url);
    // No double-encoded percent (%2520) should appear.
    XCTAssertFalse([url.absoluteString containsString:@"%2520"],
                   @"Percent sign was double-encoded: %@", url.absoluteString);
    // The decoded path must be the real on-disk path.
    XCTAssertEqualObjects(url.path, @"/Users/vova/Downloads/rg/Test Folder/абв.txt");
    XCTAssertEqualObjects(url.host, @"MCA");
}

// A raw (unencoded) space and raw non-ASCII in a file URL should also encode correctly.
- (void)testRawSpaceAndNonASCIIPath {
    NSString *input = @"file:///Users/me/Test Folder/абв.txt";
    NSURL *url = [NSURL URLWithUserSuppliedString:input];
    XCTAssertNotNil(url);
    XCTAssertEqualObjects(url.path, @"/Users/me/Test Folder/абв.txt");
}

// Well-formed ASCII URLs should pass through unchanged.
- (void)testWellFormedURLsUnchanged {
    NSArray<NSString *> *cases = @[
        @"https://example.com/foo%20bar",
        @"https://user:pass@host:8080/a?b=c#frag",
        @"mailto:foo@bar.com",
    ];
    for (NSString *input in cases) {
        NSURL *url = [NSURL URLWithUserSuppliedString:input];
        XCTAssertEqualObjects(url.absoluteString, input, @"URL was altered: %@", input);
    }
}

// IDN hostnames with raw non-ASCII should be Punycode-encoded.
- (void)testIDNHostname {
    NSString *input = @"http://例え.jp/path";  // 例え.jp
    NSURL *url = [NSURL URLWithUserSuppliedString:input];
    XCTAssertEqualObjects(url.host, @"xn--r8jz45g.jp");
}

// Regression test for issue 13063. An OSC 8 hyperlink whose query contains a character outside the
// BMP (an emoji is two UTF-16 units) used to raise NSInvalidArgumentException on the mutation queue
// and abort the app: the surrogate pair was split across placeholder ranges, so percent-encoding the
// resulting lone surrogate returned nil and that nil reached -replaceOccurrencesOfString:withString:.
- (void)testNonBMPCharacterInQuery {
    NSString *input = @"https://example.com/search?q=\U0001F389";
    NSURL *url = [NSURL URLWithUserSuppliedString:input];
    XCTAssertNotNil(url);
    XCTAssertEqualObjects(url.scheme, @"https");
    XCTAssertEqualObjects(url.host, @"example.com");
    XCTAssertEqualObjects(url.query, @"q=%F0%9F%8E%89");
}

// Same as above with more than one query item, so the failing replacement runs twice.
- (void)testNonBMPCharacterInMultipleQueryItems {
    NSString *input = @"https://example.com/search?q=\U0001F389&b=\U0001F680";
    NSURL *url = [NSURL URLWithUserSuppliedString:input];
    XCTAssertNotNil(url);
    XCTAssertEqualObjects(url.query, @"q=%F0%9F%8E%89&b=%F0%9F%9A%80");
}

// A non-BMP character in the path must survive too. The character right after it used to be left out
// of the placeholder map entirely.
- (void)testNonBMPCharacterInPath {
    NSString *input = @"file:///Users/me/\U0001F389x/y.txt";
    NSURL *url = [NSURL URLWithUserSuppliedString:input];
    XCTAssertNotNil(url);
    XCTAssertEqualObjects(url.path, @"/Users/me/\U0001F389x/y.txt");
}

@end
