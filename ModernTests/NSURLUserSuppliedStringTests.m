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

@end
