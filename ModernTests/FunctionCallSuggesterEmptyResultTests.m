//
//  FunctionCallSuggesterEmptyResultTests.m
//  ModernTests
//
//  -[iTermFunctionCallSuggester suggestionsForString:] is declared nonnull but
//  returned nil when the parser produced no array for the prefix (a complete
//  call, for example), and when the path source gave no paths. The nullability
//  sanitizer reported the nil return (unit N3 of
//  docs/swift-migration/nullability-triage.md). Swift callers already saw an
//  empty array there, because the bridge turns a nil NSArray into [], so these
//  tests are in Objective-C: only Objective-C can observe the nil.
//

#import <XCTest/XCTest.h>

#import "iTermFunctionCallSuggester.h"

@interface FunctionCallSuggesterEmptyResultTests : XCTestCase
@end

@implementation FunctionCallSuggesterEmptyResultTests

- (NSDictionary<NSString *, NSArray<NSString *> *> *)signatures {
    return @{ @"add": @[ @"x", @"y" ] };
}

- (NSSet<NSString *> *(^)(NSString *))pathSourceWithPaths {
    return ^NSSet<NSString *> *(NSString *prefix) {
        return [NSSet setWithArray:@[ @"foo", @"bar" ]];
    };
}

// The app's path sources always return a set. This one does not, because a
// missing set is the only way the expression and swifty-string suggesters
// produced nil.
- (NSSet<NSString *> *(^)(NSString *))pathSourceWithoutPaths {
    return ^NSSet<NSString *> *(NSString *prefix) {
        return nil;
    };
}

// A complete call leaves nothing to suggest: the parser yields no array.
- (void)testCompleteCallGivesAnEmptyArray {
    iTermFunctionCallSuggester *suggester =
        [[iTermFunctionCallSuggester alloc] initWithFunctionSignatures:[self signatures]
                                                            pathSource:[self pathSourceWithPaths]];
    NSArray<NSString *> *suggestions = [suggester suggestionsForString:@"add(x: 1, y: 2)"];
    XCTAssertNotNil(suggestions);
    XCTAssertEqual(suggestions.count, 0u);
}

// The zero-length prefix lists paths and functions; with no paths it still
// gives an array.
- (void)testEmptyPrefixWithoutPathsGivesAnArray {
    iTermFunctionCallSuggester *suggester =
        [[iTermFunctionCallSuggester alloc] initWithFunctionSignatures:[self signatures]
                                                            pathSource:[self pathSourceWithoutPaths]];
    NSArray<NSString *> *suggestions = [suggester suggestionsForString:@""];
    XCTAssertNotNil(suggestions);
}

- (void)testExpressionSuggesterWithoutPathsGivesAnArray {
    iTermExpressionSuggester *suggester =
        [[iTermExpressionSuggester alloc] initWithFunctionSignatures:[self signatures]
                                                          pathSource:[self pathSourceWithoutPaths]];
    NSArray<NSString *> *suggestions = [suggester suggestionsForString:@"fo"];
    XCTAssertNotNil(suggestions);
    XCTAssertEqual(suggestions.count, 0u);
}

// The swifty-string suggester asks its superclass about the truncated
// interpolation, here the empty string after the backslash and parenthesis.
- (void)testSwiftyStringSuggesterWithoutPathsGivesAnArray {
    iTermSwiftyStringSuggester *suggester =
        [[iTermSwiftyStringSuggester alloc] initWithFunctionSignatures:[self signatures]
                                                            pathSource:[self pathSourceWithoutPaths]];
    NSArray<NSString *> *suggestions = [suggester suggestionsForString:@"Hello \\("];
    XCTAssertNotNil(suggestions);
}

@end
