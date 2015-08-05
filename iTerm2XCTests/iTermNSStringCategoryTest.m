#import <XCTest/XCTest.h>
#import "NSStringITerm.h"

@interface NSStringCategoryTest : XCTestCase
@end

@implementation NSStringCategoryTest


- (void)testVimSpecialChars_NoSpecialChars {
    XCTAssert([@"Foo" isEqualToString:[@"Foo" stringByExpandingVimSpecialCharacters]]);
}

- (void)testVimSpecialChars_TerminalBackslash {
    XCTAssert([@"Foo" isEqualToString:[@"Foo\\" stringByExpandingVimSpecialCharacters]]);
}

- (void)testVimSpecialChars_ThreeDigitOctal {
    XCTAssert([@"prefixAsuffix" isEqualToString:[@"prefix\\101suffix" stringByExpandingVimSpecialCharacters]]);
}

- (void)testVimSpecialChars_TwoDigitOctal {
    XCTAssert([@"prefix0suffix" isEqualToString:[@"prefix\\60suffix" stringByExpandingVimSpecialCharacters]]);
}

- (void)testVimSpecialChars_OneDigitOctal {
    NSString *expected = [NSString stringWithFormat:@"prefix%csuffix", 5];
    NSString *actual = [@"prefix\\5suffix" stringByExpandingVimSpecialCharacters];
    XCTAssert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_TwoDigitHex {
    NSString *expected = [NSString stringWithFormat:@"prefixAsuffix"];
    NSString *actual = [@"prefix\\x41suffix" stringByExpandingVimSpecialCharacters];
    XCTAssert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_OneDigitHex {
    NSString *expected = [NSString stringWithFormat:@"prefix%csuffix", 5];
    NSString *actual = [@"prefix\\x5suffix" stringByExpandingVimSpecialCharacters];
    XCTAssert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_FourDigitUnicode {
    NSString *expected = [NSString stringWithFormat:@"prefix%Csuffix", 0x6C34];
    NSString *actual = [@"prefix\\u6C34suffix" stringByExpandingVimSpecialCharacters];
    XCTAssert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_Backspace {
    NSString *expected = [NSString stringWithFormat:@"prefix%csuffix", 0x7f];
    NSString *actual = [@"prefix\\bsuffix" stringByExpandingVimSpecialCharacters];
    XCTAssert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_Escape {
    NSString *expected = [NSString stringWithFormat:@"prefix%csuffix", 27];
    NSString *actual = [@"prefix\\esuffix" stringByExpandingVimSpecialCharacters];
    XCTAssert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_FormFeed {
    NSString *expected = [NSString stringWithFormat:@"prefix%csuffix", 12];
    NSString *actual = [@"prefix\\fsuffix" stringByExpandingVimSpecialCharacters];
    XCTAssert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_Newline {
    NSString *expected = [NSString stringWithFormat:@"prefix%csuffix", '\n'];
    NSString *actual = [@"prefix\\nsuffix" stringByExpandingVimSpecialCharacters];
    XCTAssert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_Return {
    NSString *expected = [NSString stringWithFormat:@"prefix%csuffix", '\r'];
    NSString *actual = [@"prefix\\rsuffix" stringByExpandingVimSpecialCharacters];
    XCTAssert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_Tab {
    NSString *expected = [NSString stringWithFormat:@"prefix%csuffix", '\t'];
    NSString *actual = [@"prefix\\tsuffix" stringByExpandingVimSpecialCharacters];
    XCTAssert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_Backslash {
    NSString *expected = [NSString stringWithFormat:@"prefix%csuffix", '\\'];
    NSString *actual = [@"prefix\\\\suffix" stringByExpandingVimSpecialCharacters];
    XCTAssert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_DoubleQuote {
    NSString *expected = [NSString stringWithFormat:@"prefix%csuffix", '"'];
    NSString *actual = [@"prefix\\\"suffix" stringByExpandingVimSpecialCharacters];
    XCTAssert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_ControlKey {
    NSString *expected = [NSString stringWithFormat:@"prefix%csuffix", 1];
    NSString *actual = [@"prefix\\<C-A>suffix" stringByExpandingVimSpecialCharacters];
    XCTAssert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_MetaKey {
    NSString *expected = [NSString stringWithFormat:@"prefix%cAsuffix", 27];
    NSString *actual = [@"prefix\\<M-A>suffix" stringByExpandingVimSpecialCharacters];
    XCTAssert([expected isEqualToString:actual]);
}

- (void)testMultiples {
    NSString *expected = [NSString stringWithFormat:@"AxAxA"];
    NSString *actual = [@"\\x41x\\x41x\\x41" stringByExpandingVimSpecialCharacters];
    XCTAssert([expected isEqualToString:actual]);
}

- (void)testSequential {
    NSString *expected = [NSString stringWithFormat:@"AA"];
    NSString *actual = [@"\\x41\\x41" stringByExpandingVimSpecialCharacters];
    XCTAssert([expected isEqualToString:actual]);
}

- (void)assertString:(NSString *)string parsesAsShellCommandTo:(NSArray *)expected {
    NSArray *actual = [string componentsInShellCommand];
    XCTAssert([actual isEqualToArray:expected]);
}

- (void)testParseShellCommand {
    [self assertString:@"foo" parsesAsShellCommandTo:@[ @"foo" ]];
    [self assertString:@"foo bar" parsesAsShellCommandTo:@[ @"foo",
                                                            @"bar" ]];
    [self assertString:@"   foo    bar   " parsesAsShellCommandTo:@[ @"foo",
                                                                     @"bar" ]];

    // Escapes
    [self assertString:@"foo\\ bar" parsesAsShellCommandTo:@[ @"foo bar"]];
    [self assertString:@"foo\\n bar" parsesAsShellCommandTo:@[ @"foo\n", @"bar"]];
    [self assertString:@"foo\\t bar" parsesAsShellCommandTo:@[ @"foo\t", @"bar"]];
    [self assertString:@"foo\\\" bar" parsesAsShellCommandTo:@[ @"foo\"", @"bar"]];
    [self assertString:@"foo\\ bar" parsesAsShellCommandTo:@[ @"foo bar"]];

    // Quotes
    [self assertString:@"\"foo bar\"" parsesAsShellCommandTo:@[ @"foo bar" ]];
    [self assertString:@"   \"foo bar\"   " parsesAsShellCommandTo:@[ @"foo bar" ]];
    [self assertString:@"   \"foo  bar\"   " parsesAsShellCommandTo:@[ @"foo  bar" ]];
    [self assertString:@"   \"foo\\ bar\"   " parsesAsShellCommandTo:@[ @"foo bar" ]];
    [self assertString:@"   \"foo bar" parsesAsShellCommandTo:@[ @"foo bar" ]];
    [self assertString:@"\\\"foo bar\\\"" parsesAsShellCommandTo:@[ @"\"foo", @"bar\"" ]];

    // Tildes
    [self assertString:@"~" parsesAsShellCommandTo:@[ [@"~" stringByExpandingTildeInPath] ]];
    [self assertString:@"a~" parsesAsShellCommandTo:@[ @"a~" ]];
    [self assertString:@"\"~\"" parsesAsShellCommandTo:@[ @"~" ]];
    [self assertString:@"\\~" parsesAsShellCommandTo:@[ @"~" ]];
}

- (void)testStringByTrimmingTrailingWhitespace {
    XCTAssert([[@"abc" stringByTrimmingTrailingWhitespace] isEqualToString:@"abc"]);
    XCTAssert([[@"abc " stringByTrimmingTrailingWhitespace] isEqualToString:@"abc"]);
    XCTAssert([[@"abc  " stringByTrimmingTrailingWhitespace] isEqualToString:@"abc"]);
    XCTAssert([[@" abc " stringByTrimmingTrailingWhitespace] isEqualToString:@" abc"]);
    XCTAssert([[@" abc  " stringByTrimmingTrailingWhitespace] isEqualToString:@" abc"]);
    // U+00A0 is a non-breaking space
    XCTAssert([[@"abc \u00a0" stringByTrimmingTrailingWhitespace] isEqualToString:@"abc"]);

    // There used to be a bug that surrogate pairs got truncated by sBTTW.
    XCTAssert([[@"abc 🔥" stringByTrimmingTrailingWhitespace] isEqualToString:@"abc 🔥"]);
}

- (void)testRangeOfURLInString {
    NSArray *strings = @[ @"http://example.com",
                          @"(http://example.com)",
                          @"*http://example.com",
                          @"http://example.com.",
                          @"(http://example.com).",
                          @"(http://example.com.)",
                          @"*(http://example.com.)" ];
    for (NSString *string in strings) {
        NSRange range = [string rangeOfURLInString];
        XCTAssert([[string substringWithRange:range] isEqualToString:@"http://example.com"]);
    }

    strings = @[ @"example.com",
                 @"(example.com)",
                 @"example.com.",
                 @"(example.com).",
                 @"(example.com.)" ];
    for (NSString *string in strings) {
        NSRange range = [string rangeOfURLInString];
        XCTAssert([[string substringWithRange:range] isEqualToString:@"example.com"]);
    }
}

- (void)testStringMatchesCaseInsensitiveGlobPattern {
  // Empty string tests
  XCTAssertTrue([@"" stringMatchesCaseInsensitiveGlobPattern:@""]);
  XCTAssertFalse([@"" stringMatchesCaseInsensitiveGlobPattern:@"abc"]);

  // Basic tests that should pass
  XCTAssertTrue([@"abc" stringMatchesCaseInsensitiveGlobPattern:@"abc"]);
  XCTAssertTrue([@"abc" stringMatchesCaseInsensitiveGlobPattern:@"a*c"]);
  XCTAssertTrue([@"abc" stringMatchesCaseInsensitiveGlobPattern:@"a*"]);
  XCTAssertTrue([@"abc" stringMatchesCaseInsensitiveGlobPattern:@"*c"]);
  XCTAssertTrue([@"abc" stringMatchesCaseInsensitiveGlobPattern:@"*bc"]);
  XCTAssertTrue([@"abc" stringMatchesCaseInsensitiveGlobPattern:@"*b*"]);
  XCTAssertTrue([@"abc" stringMatchesCaseInsensitiveGlobPattern:@"**c"]);
  XCTAssertTrue([@"abc" stringMatchesCaseInsensitiveGlobPattern:@"a*b*c"]);
  XCTAssertTrue([@"abc" stringMatchesCaseInsensitiveGlobPattern:@"*a*b*c"]);
  XCTAssertTrue([@"abc" stringMatchesCaseInsensitiveGlobPattern:@"a*b*c*"]);
  XCTAssertTrue([@"abc" stringMatchesCaseInsensitiveGlobPattern:@"*a*b*c*"]);
  XCTAssertTrue([@"abc" stringMatchesCaseInsensitiveGlobPattern:@"***a****b****c****"]);

  // Basic tests that should fail
  XCTAssertFalse([@"abc" stringMatchesCaseInsensitiveGlobPattern:@""]);
  XCTAssertFalse([@"abc" stringMatchesCaseInsensitiveGlobPattern:@"a"]);
  XCTAssertFalse([@"abc" stringMatchesCaseInsensitiveGlobPattern:@"x"]);
  XCTAssertFalse([@"abc" stringMatchesCaseInsensitiveGlobPattern:@"a*b"]);
  XCTAssertFalse([@"abc" stringMatchesCaseInsensitiveGlobPattern:@"*b"]);
  XCTAssertFalse([@"abc" stringMatchesCaseInsensitiveGlobPattern:@"***a****b**x**c****"]);

  // Longer string tests
  XCTAssertTrue([@"abcdefghi" stringMatchesCaseInsensitiveGlobPattern:@"a*d*g*i"]);
  XCTAssertTrue([@"abcdefghi" stringMatchesCaseInsensitiveGlobPattern:@"a*d*g*"]);
  XCTAssertFalse([@"abcdefghi" stringMatchesCaseInsensitiveGlobPattern:@"a*q*g*"]);

  // Case insensitivity tests
  XCTAssertTrue([@"abc" stringMatchesCaseInsensitiveGlobPattern:@"ABC"]);
  XCTAssertTrue([@"abc" stringMatchesCaseInsensitiveGlobPattern:@"A*C"]);
  XCTAssertTrue([@"ABC" stringMatchesCaseInsensitiveGlobPattern:@"abc"]);
  XCTAssertTrue([@"ABC" stringMatchesCaseInsensitiveGlobPattern:@"a*c"]);
  XCTAssertFalse([@"ABC" stringMatchesCaseInsensitiveGlobPattern:@"a*x"]);
}

@end
