#import "iTermTests.h"
#import "NSStringCategoryTest.h"
#import "NSStringITerm.h"

@implementation NSStringCategoryTest


- (void)testVimSpecialChars_NoSpecialChars {
    assert([@"Foo" isEqualToString:[@"Foo" stringByExpandingVimSpecialCharacters]]);
}

- (void)testVimSpecialChars_TerminalBackslash {
    assert([@"Foo" isEqualToString:[@"Foo\\" stringByExpandingVimSpecialCharacters]]);
}

- (void)testVimSpecialChars_ThreeDigitOctal {
    assert([@"prefixAsuffix" isEqualToString:[@"prefix\\101suffix" stringByExpandingVimSpecialCharacters]]);
}

- (void)testVimSpecialChars_TwoDigitOctal {
    assert([@"prefix0suffix" isEqualToString:[@"prefix\\60suffix" stringByExpandingVimSpecialCharacters]]);
}

- (void)testVimSpecialChars_OneDigitOctal {
    NSString *expected = [NSString stringWithFormat:@"prefix%csuffix", 5];
    NSString *actual = [@"prefix\\5suffix" stringByExpandingVimSpecialCharacters];
    assert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_TwoDigitHex {
    NSString *expected = [NSString stringWithFormat:@"prefixAsuffix"];
    NSString *actual = [@"prefix\\x41suffix" stringByExpandingVimSpecialCharacters];
    assert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_OneDigitHex {
    NSString *expected = [NSString stringWithFormat:@"prefix%csuffix", 5];
    NSString *actual = [@"prefix\\x5suffix" stringByExpandingVimSpecialCharacters];
    assert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_FourDigitUnicode {
    NSString *expected = [NSString stringWithFormat:@"prefix%Csuffix", 0x6C34];
    NSString *actual = [@"prefix\\u6C34suffix" stringByExpandingVimSpecialCharacters];
    assert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_Backspace {
    NSString *expected = [NSString stringWithFormat:@"prefix%csuffix", 0x7f];
    NSString *actual = [@"prefix\\bsuffix" stringByExpandingVimSpecialCharacters];
    assert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_Escape {
    NSString *expected = [NSString stringWithFormat:@"prefix%csuffix", 27];
    NSString *actual = [@"prefix\\esuffix" stringByExpandingVimSpecialCharacters];
    assert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_FormFeed {
    NSString *expected = [NSString stringWithFormat:@"prefix%csuffix", 12];
    NSString *actual = [@"prefix\\fsuffix" stringByExpandingVimSpecialCharacters];
    assert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_Newline {
    NSString *expected = [NSString stringWithFormat:@"prefix%csuffix", '\n'];
    NSString *actual = [@"prefix\\nsuffix" stringByExpandingVimSpecialCharacters];
    assert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_Return {
    NSString *expected = [NSString stringWithFormat:@"prefix%csuffix", '\r'];
    NSString *actual = [@"prefix\\rsuffix" stringByExpandingVimSpecialCharacters];
    assert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_Tab {
    NSString *expected = [NSString stringWithFormat:@"prefix%csuffix", '\t'];
    NSString *actual = [@"prefix\\tsuffix" stringByExpandingVimSpecialCharacters];
    assert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_Backslash {
    NSString *expected = [NSString stringWithFormat:@"prefix%csuffix", '\\'];
    NSString *actual = [@"prefix\\\\suffix" stringByExpandingVimSpecialCharacters];
    assert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_DoubleQuote {
    NSString *expected = [NSString stringWithFormat:@"prefix%csuffix", '"'];
    NSString *actual = [@"prefix\\\"suffix" stringByExpandingVimSpecialCharacters];
    assert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_ControlKey {
    NSString *expected = [NSString stringWithFormat:@"prefix%csuffix", 1];
    NSString *actual = [@"prefix\\<C-A>suffix" stringByExpandingVimSpecialCharacters];
    assert([expected isEqualToString:actual]);
}

- (void)testVimSpecialChars_MetaKey {
    NSString *expected = [NSString stringWithFormat:@"prefix%cAsuffix", 27];
    NSString *actual = [@"prefix\\<M-A>suffix" stringByExpandingVimSpecialCharacters];
    assert([expected isEqualToString:actual]);
}

- (void)testMultiples {
    NSString *expected = [NSString stringWithFormat:@"AxAxA"];
    NSString *actual = [@"\\x41x\\x41x\\x41" stringByExpandingVimSpecialCharacters];
    assert([expected isEqualToString:actual]);
}

- (void)testSequential {
    NSString *expected = [NSString stringWithFormat:@"AA"];
    NSString *actual = [@"\\x41\\x41" stringByExpandingVimSpecialCharacters];
    assert([expected isEqualToString:actual]);
}

@end
