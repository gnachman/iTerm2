#import <XCTest/XCTest.h>

#import "iTermTuple.h"
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

- (void)testStringByTrimmingCharset {
    XCTAssertEqualObjects([@"abc" stringByTrimmingTrailingCharactersFromCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@"a"]], @"abc");
    XCTAssertEqualObjects([@"abc" stringByTrimmingTrailingCharactersFromCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@"c"]], @"ab");
    XCTAssertEqualObjects([@"abc" stringByTrimmingTrailingCharactersFromCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@"x"]], @"abc");
    XCTAssertEqualObjects([@"abc" stringByTrimmingTrailingCharactersFromCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@"bc"]], @"a");
    XCTAssertEqualObjects([@"abc" stringByTrimmingTrailingCharactersFromCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@"abc"]], @"");
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

- (void)testStringByRemovingEnclosingBrackets {
  XCTAssert([@"abc" isEqualToString:[@"abc" stringByRemovingEnclosingBrackets]]);

  XCTAssert([@"abc" isEqualToString:[@"(abc)" stringByRemovingEnclosingBrackets]]);
  XCTAssert([@"abc" isEqualToString:[@"<abc>" stringByRemovingEnclosingBrackets]]);
  XCTAssert([@"abc" isEqualToString:[@"[abc]" stringByRemovingEnclosingBrackets]]);
  XCTAssert([@"abc" isEqualToString:[@"{abc}" stringByRemovingEnclosingBrackets]]);
  XCTAssert([@"abc" isEqualToString:[@"'abc'" stringByRemovingEnclosingBrackets]]);
  XCTAssert([@"abc" isEqualToString:[@"\"abc\"" stringByRemovingEnclosingBrackets]]);

  XCTAssert([@"(abc(" isEqualToString:[@"(abc(" stringByRemovingEnclosingBrackets]]);
  XCTAssert([@"<abc<" isEqualToString:[@"<abc<" stringByRemovingEnclosingBrackets]]);
  XCTAssert([@"[abc[" isEqualToString:[@"[abc[" stringByRemovingEnclosingBrackets]]);
  XCTAssert([@"{abc{" isEqualToString:[@"{abc{" stringByRemovingEnclosingBrackets]]);

  XCTAssert([@"a" isEqualToString:[@"a" stringByRemovingEnclosingBrackets]]);
  XCTAssert([@"a" isEqualToString:[@"(a)" stringByRemovingEnclosingBrackets]]);

  XCTAssert([@"" isEqualToString:[@"" stringByRemovingEnclosingBrackets]]);
  XCTAssert([@"" isEqualToString:[@"()" stringByRemovingEnclosingBrackets]]);
  XCTAssert([@"" isEqualToString:[@"([])" stringByRemovingEnclosingBrackets]]);

  XCTAssert([@"abc" isEqualToString:[@"<[abc]>" stringByRemovingEnclosingBrackets]]);
  XCTAssert([@"<[abc>]" isEqualToString:[@"<[abc>]" stringByRemovingEnclosingBrackets]]);
}

- (void)testStringMatchesCaseInsensitiveGlobPattern {
  // Empty string tests
  XCTAssertTrue([@"" stringMatchesGlobPattern:@"" caseSensitive:NO]);
  XCTAssertFalse([@"" stringMatchesGlobPattern:@"abc" caseSensitive:NO]);

  // Basic tests that should pass
  XCTAssertTrue([@"abc" stringMatchesGlobPattern:@"abc" caseSensitive:NO]);
  XCTAssertTrue([@"abc" stringMatchesGlobPattern:@"a*c" caseSensitive:NO]);
  XCTAssertTrue([@"abc" stringMatchesGlobPattern:@"a*" caseSensitive:NO]);
  XCTAssertTrue([@"abc" stringMatchesGlobPattern:@"*c" caseSensitive:NO]);
  XCTAssertTrue([@"abc" stringMatchesGlobPattern:@"*bc" caseSensitive:NO]);
  XCTAssertTrue([@"abc" stringMatchesGlobPattern:@"*b*" caseSensitive:NO]);
  XCTAssertTrue([@"abc" stringMatchesGlobPattern:@"**c" caseSensitive:NO]);
  XCTAssertTrue([@"abc" stringMatchesGlobPattern:@"a*b*c" caseSensitive:NO]);
  XCTAssertTrue([@"abc" stringMatchesGlobPattern:@"*a*b*c" caseSensitive:NO]);
  XCTAssertTrue([@"abc" stringMatchesGlobPattern:@"a*b*c*" caseSensitive:NO]);
  XCTAssertTrue([@"abc" stringMatchesGlobPattern:@"*a*b*c*" caseSensitive:NO]);
  XCTAssertTrue([@"abc" stringMatchesGlobPattern:@"***a****b****c****" caseSensitive:NO]);

  // Basic tests that should fail
  XCTAssertFalse([@"abc" stringMatchesGlobPattern:@"" caseSensitive:NO]);
  XCTAssertFalse([@"abc" stringMatchesGlobPattern:@"a" caseSensitive:NO]);
  XCTAssertFalse([@"abc" stringMatchesGlobPattern:@"x" caseSensitive:NO]);
  XCTAssertFalse([@"abc" stringMatchesGlobPattern:@"a*b" caseSensitive:NO]);
  XCTAssertFalse([@"abc" stringMatchesGlobPattern:@"*b" caseSensitive:NO]);
  XCTAssertFalse([@"abc" stringMatchesGlobPattern:@"***a****b**x**c****" caseSensitive:NO]);

  // Longer string tests
  XCTAssertTrue([@"abcdefghi" stringMatchesGlobPattern:@"a*d*g*i" caseSensitive:NO]);
  XCTAssertTrue([@"abcdefghi" stringMatchesGlobPattern:@"a*d*g*" caseSensitive:NO]);
  XCTAssertFalse([@"abcdefghi" stringMatchesGlobPattern:@"a*q*g*" caseSensitive:NO]);

  // Case insensitivity tests
  XCTAssertTrue([@"abc" stringMatchesGlobPattern:@"ABC" caseSensitive:NO]);
  XCTAssertTrue([@"abc" stringMatchesGlobPattern:@"A*C" caseSensitive:NO]);
  XCTAssertTrue([@"ABC" stringMatchesGlobPattern:@"abc" caseSensitive:NO]);
  XCTAssertTrue([@"ABC" stringMatchesGlobPattern:@"a*c" caseSensitive:NO]);
  XCTAssertFalse([@"ABC" stringMatchesGlobPattern:@"a*x" caseSensitive:NO]);
}

- (void)testComponentsBySplittingStringWithQuotesAndBackslashEscaping_Basic {
    NSString *s = @"foo bar";
    NSArray<NSString *> *actual = [s componentsBySplittingStringWithQuotesAndBackslashEscaping:@{}];
    NSArray<NSString *> *expected = @[ @"foo", @"bar" ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testComponentsBySplittingStringWithQuotesAndBackslashEscaping_BackslashEscapesMidlineSpace {
    NSString *s = @"foo\\ bar";
    NSArray<NSString *> *actual = [s componentsBySplittingStringWithQuotesAndBackslashEscaping:@{}];
    NSArray<NSString *> *expected = @[ @"foo bar" ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testComponentsBySplittingStringWithQuotesAndBackslashEscaping_BackslashEscapesLeadingTrailingSpace {
    NSString *s = @"\\ foo bar\\ ";
    NSArray<NSString *> *actual = [s componentsBySplittingStringWithQuotesAndBackslashEscaping:@{}];
    NSArray<NSString *> *expected = @[ @" foo", @"bar " ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testComponentsBySplittingStringWithQuotesAndBackslashEscaping_BackslashEscapesSingleQuote {
    NSString *s = @"foo\\' bar";
    NSArray<NSString *> *actual = [s componentsBySplittingStringWithQuotesAndBackslashEscaping:@{}];
    NSArray<NSString *> *expected = @[ @"foo'", @"bar" ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testComponentsBySplittingStringWithQuotesAndBackslashEscaping_BackslashEscapesDoubleQuote {
    NSString *s = @"foo\\\" bar";
    NSArray<NSString *> *actual = [s componentsBySplittingStringWithQuotesAndBackslashEscaping:@{}];
    NSArray<NSString *> *expected = @[ @"foo\"", @"bar" ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testComponentsBySplittingStringWithQuotesAndBackslashEscaping_BackslashEscapesBackslash {
    NSString *s = @"foo\\\\ bar";
    NSArray<NSString *> *actual = [s componentsBySplittingStringWithQuotesAndBackslashEscaping:@{}];
    NSArray<NSString *> *expected = @[ @"foo\\", @"bar" ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testComponentsBySplittingStringWithQuotesAndBackslashEscaping_CustomEscapes {
    NSString *s = @"foo \\1";
    NSArray<NSString *> *actual = [s componentsBySplittingStringWithQuotesAndBackslashEscaping:@{ @'1': @"bar" }];
    NSArray<NSString *> *expected = @[ @"foo", @"bar" ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testComponentsBySplittingStringWithQuotesAndBackslashEscaping_QuotedCustomEscapes {
    NSString *s = @"foo \"\\1\"";
    NSArray<NSString *> *actual = [s componentsBySplittingStringWithQuotesAndBackslashEscaping:@{ @'1': @"bar" }];
    NSArray<NSString *> *expected = @[ @"foo", @"bar" ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testComponentsBySplittingStringWithQuotesAndBackslashEscaping_DoubleQuotesWithSpace {
    NSString *s = @"foo\" \"bar";
    NSArray<NSString *> *actual = [s componentsBySplittingStringWithQuotesAndBackslashEscaping:@{}];
    NSArray<NSString *> *expected = @[ @"foo bar" ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testComponentsBySplittingStringWithQuotesAndBackslashEscaping_DoubleQuotesWithSingleQuote {
    NSString *s = @"foo\"'\"bar";
    NSArray<NSString *> *actual = [s componentsBySplittingStringWithQuotesAndBackslashEscaping:@{}];
    NSArray<NSString *> *expected = @[ @"foo'bar" ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testComponentsBySplittingStringWithQuotesAndBackslashEscaping_DoubleQuotesWithEscapedDoubleQuote {
    NSString *s = @"foo\"\\\"\"bar";
    NSArray<NSString *> *actual = [s componentsBySplittingStringWithQuotesAndBackslashEscaping:@{}];
    NSArray<NSString *> *expected = @[ @"foo\"bar" ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testComponentsBySplittingStringWithQuotesAndBackslashEscaping_SingleQuotesWithSpace {
    NSString *s = @"foo' 'bar";
    NSArray<NSString *> *actual = [s componentsBySplittingStringWithQuotesAndBackslashEscaping:@{}];
    NSArray<NSString *> *expected = @[ @"foo bar" ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testComponentsBySplittingStringWithQuotesAndBackslashEscaping_SingleQuotesWithDoubleQuote {
    NSString *s = @"foo'\"'bar";
    NSArray<NSString *> *actual = [s componentsBySplittingStringWithQuotesAndBackslashEscaping:@{}];
    NSArray<NSString *> *expected = @[ @"foo\"bar" ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testComponentsBySplittingStringWithQuotesAndBackslashEscaping_SingleQuotesWithEscapedSingleQuote {
    NSString *s = @"foo'\\''bar";
    NSArray<NSString *> *actual = [s componentsBySplittingStringWithQuotesAndBackslashEscaping:@{}];
    NSArray<NSString *> *expected = @[ @"foo'bar" ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testComponentsBySplittingStringWithQuotesAndBackslashEscaping_MismatchedDoubleQuotes {
    NSString *s = @"foo\" bar";
    NSArray<NSString *> *actual = [s componentsBySplittingStringWithQuotesAndBackslashEscaping:@{}];
    NSArray<NSString *> *expected = @[ @"foo bar" ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testComponentsBySplittingStringWithQuotesAndBackslashEscaping_MismatchedSingleQuotes {
    NSString *s = @"foo' bar";
    NSArray<NSString *> *actual = [s componentsBySplittingStringWithQuotesAndBackslashEscaping:@{}];
    NSArray<NSString *> *expected = @[ @"foo bar" ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testComponentsBySplittingStringWithQuotesAndBackslashEscaping_OrphanBackslash {
    NSString *s = @"foo bar\\";
    NSArray<NSString *> *actual = [s componentsBySplittingStringWithQuotesAndBackslashEscaping:@{}];
    NSArray<NSString *> *expected = @[ @"foo", @"bar" ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testComponentsBySplittingStringWithQuotesAndBackslashEscaping_ExpandTilde {
    NSString *s = @"~/foo bar";
    NSArray<NSString *> *actual = [s componentsBySplittingStringWithQuotesAndBackslashEscaping:@{}];
    XCTAssertEqual(actual.count, 2);
    XCTAssertFalse([actual[0] hasPrefix:@"~"]);
}

- (void)testComponentsBySplittingStringWithQuotesAndBackslashEscaping_MidlineTilde {
    NSString *s = @"fo~o bar";
    NSArray<NSString *> *actual = [s componentsBySplittingStringWithQuotesAndBackslashEscaping:@{}];
    NSArray<NSString *> *expected = @[ @"fo~o", @"bar" ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testComponentsBySplittingStringWithQuotesAndBackslashEscaping_EscapedTilde {
    NSString *s = @"\\~/foo bar";
    NSArray<NSString *> *actual = [s componentsBySplittingStringWithQuotesAndBackslashEscaping:@{}];
    NSArray<NSString *> *expected = @[ @"~/foo", @"bar" ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testComponentsBySplittingStringWithQuotesAndBackslashEscaping_DoubleQuotedTilde {
    NSString *s = @"\"~/foo\" bar";
    NSArray<NSString *> *actual = [s componentsBySplittingStringWithQuotesAndBackslashEscaping:@{}];
    NSArray<NSString *> *expected = @[ @"~/foo", @"bar" ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testComponentsBySplittingStringWithQuotesAndBackslashEscaping_SingleQuotedTilde {
    NSString *s = @"'~/foo' bar";
    NSArray<NSString *> *actual = [s componentsBySplittingStringWithQuotesAndBackslashEscaping:@{}];
    NSArray<NSString *> *expected = @[ @"~/foo", @"bar" ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testComponentsBySplittingStringWithQuotesAndBackslashEscaping_TrimSpace {
    NSString *s = @"  foo   bar  ";
    NSArray<NSString *> *actual = [s componentsBySplittingStringWithQuotesAndBackslashEscaping:@{}];
    NSArray<NSString *> *expected = @[ @"foo", @"bar" ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testDoubleDollarVariables_OneTrivialCapture {
    NSString *s = @"blah $$FOO$$ blah";
    NSSet *expected = [NSSet setWithArray:@[ @"$$FOO$$" ]];
    NSSet *actual = [s doubleDollarVariables];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testDoubleDollarVariables_TwoCaptures {
    NSString *s = @"blah $$FOO$$ blah $$BAR$$ baz";
    NSSet *expected = [NSSet setWithArray:@[ @"$$FOO$$", @"$$BAR$$" ]];
    NSSet *actual = [s doubleDollarVariables];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testDoubleDollarVariables_EscapedCaptures {
    NSString *s = @"blah $$$$ blah $$$$ baz";
    NSSet *expected = [NSSet setWithArray:@[ ]];
    NSSet *actual = [s doubleDollarVariables];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testDoubleDollarVariables_OneBigCapture {
    NSString *s = @"$$ foo bar baz $$";
    NSSet *expected = [NSSet setWithArray:@[ @"$$ foo bar baz $$" ]];
    NSSet *actual = [s doubleDollarVariables];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testEnumerateSwiftySubstrings_Literal {
    NSString *s = @"xyz";
    NSArray<iTermTuple<NSString *, NSNumber *> *> *expected =
        @[ [iTermTuple tupleWithObject:@"xyz" andObject:@YES] ];
    NSMutableArray<iTermTuple<NSString *, NSNumber *> *> *actual = [NSMutableArray array];
    [s enumerateSwiftySubstrings:^(NSUInteger index, NSString *substring, BOOL isLiteral, BOOL *stop) {
        [actual addObject:[iTermTuple tupleWithObject:substring andObject:@(isLiteral)]];
    }];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testEnumerateSwiftySubstrings_LiteralAndExpression {
    NSString *s = @"abc\\(def)ghi";
    NSArray<iTermTuple<NSString *, NSNumber *> *> *expected =
        @[ [iTermTuple tupleWithObject:@"abc" andObject:@YES],
           [iTermTuple tupleWithObject:@"def" andObject:@NO],
           [iTermTuple tupleWithObject:@"ghi" andObject:@YES]];
    NSMutableArray<iTermTuple<NSString *, NSNumber *> *> *actual = [NSMutableArray array];
    [s enumerateSwiftySubstrings:^(NSUInteger index, NSString *substring, BOOL isLiteral, BOOL *stop) {
        [actual addObject:[iTermTuple tupleWithObject:substring andObject:@(isLiteral)]];
    }];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testEnumerateSwiftySubstrings_LiteralWithEscapedCharacters {
    NSString *s = @"a\\b\\\\";
    NSArray<iTermTuple<NSString *, NSNumber *> *> *expected =
        @[ [iTermTuple tupleWithObject:@"a\\b\\\\" andObject:@YES] ];
    NSMutableArray<iTermTuple<NSString *, NSNumber *> *> *actual = [NSMutableArray array];
    [s enumerateSwiftySubstrings:^(NSUInteger index, NSString *substring, BOOL isLiteral, BOOL *stop) {
        [actual addObject:[iTermTuple tupleWithObject:substring andObject:@(isLiteral)]];
    }];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testEnumerateSwiftySubstrings_ExpressionContainingStringWithParens {
    NSString *s = @"\\(foo(\"bar(((\"))";
    NSArray<iTermTuple<NSString *, NSNumber *> *> *expected =
        @[ [iTermTuple tupleWithObject:@"foo(\"bar(((\")" andObject:@NO] ];
    NSMutableArray<iTermTuple<NSString *, NSNumber *> *> *actual = [NSMutableArray array];
    [s enumerateSwiftySubstrings:^(NSUInteger index, NSString *substring, BOOL isLiteral, BOOL *stop) {
        [actual addObject:[iTermTuple tupleWithObject:substring andObject:@(isLiteral)]];
    }];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testEnumerateSwiftySubstrings_ExpressionContainingNestedExpression {
    NSString *s = @"\\(foo(\"bar\(inner(x,y))\"))";
    NSArray<iTermTuple<NSString *, NSNumber *> *> *expected =
        @[ [iTermTuple tupleWithObject:@"foo(\"bar\(inner(x,y))\")" andObject:@NO] ];
    NSMutableArray<iTermTuple<NSString *, NSNumber *> *> *actual = [NSMutableArray array];
    [s enumerateSwiftySubstrings:^(NSUInteger index, NSString *substring, BOOL isLiteral, BOOL *stop) {
        [actual addObject:[iTermTuple tupleWithObject:substring andObject:@(isLiteral)]];
    }];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testEnumerateSwiftySubstrings_ExpressionContainingNestedExpressionWithString {
    NSString *s = @"\\(foo(\"bar\(inner(\"innerstring\",y))\"))";
    NSArray<iTermTuple<NSString *, NSNumber *> *> *expected =
        @[ [iTermTuple tupleWithObject:@"foo(\"bar\(inner(\"innerstring\",y))\")" andObject:@NO] ];
    NSMutableArray<iTermTuple<NSString *, NSNumber *> *> *actual = [NSMutableArray array];
    [s enumerateSwiftySubstrings:^(NSUInteger index, NSString *substring, BOOL isLiteral, BOOL *stop) {
        [actual addObject:[iTermTuple tupleWithObject:substring andObject:@(isLiteral)]];
    }];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testEnumerateSwiftySubstrings_UnclosedExpression {
    NSString *s = @"\\(foo(\"bar\(inner(\"innerstring\",y";
    NSArray<iTermTuple<NSString *, NSNumber *> *> *expected =
        @[ [iTermTuple tupleWithObject:@"foo(\"bar\(inner(\"innerstring\",y" andObject:@YES] ];
    NSMutableArray<iTermTuple<NSString *, NSNumber *> *> *actual = [NSMutableArray array];
    [s enumerateSwiftySubstrings:^(NSUInteger index, NSString *substring, BOOL isLiteral, BOOL *stop) {
        [actual addObject:[iTermTuple tupleWithObject:substring andObject:@(isLiteral)]];
    }];
    XCTAssertEqualObjects(actual, expected);
}

@end
