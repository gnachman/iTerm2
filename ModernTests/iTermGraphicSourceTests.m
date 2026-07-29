//
//  iTermGraphicSourceTests.m
//  ModernTests
//

#import <XCTest/XCTest.h>

#import "iTermGraphicSource.h"

// -it_invertedGraphicDictionary is a private category method compiled into iTermGraphicSource.m.
// Redeclare its interface so these tests can exercise it directly against the malformed input a
// synced graphic_icons.json can carry (corrupt, or hand-edited on another machine).
@interface NSDictionary (GraphicTesting)
- (NSDictionary *)it_invertedGraphicDictionary;
@end

@interface iTermGraphicSourceTests : XCTestCase
@end

@implementation iTermGraphicSourceTests

// A well-formed graphic_icons.json maps each logical icon name to the list of commands that use it;
// inverting it yields command -> [logical names].
- (void)testInvertedGraphicDictionaryInvertsValidInput {
    NSDictionary *input = @{ @"E": @[ @"emacs", @"vim" ],
                             @"P": @[ @"python" ] };
    NSDictionary *inverted = [input it_invertedGraphicDictionary];
    XCTAssertEqualObjects(inverted[@"emacs"], @[ @"E" ]);
    XCTAssertEqualObjects(inverted[@"vim"], @[ @"E" ]);
    XCTAssertEqualObjects(inverted[@"python"], @[ @"P" ]);
    XCTAssertEqual(inverted.count, 3);
}

// A malformed value that is not an array (e.g. {"emacs":"E"}) must not crash: the old code did
// `for (NSString *appName in obj)`, and sending countByEnumeratingWithState: to an NSString throws
// unrecognized selector. It should simply be skipped.
- (void)testInvertedGraphicDictionaryToleratesNonArrayValue {
    NSDictionary *input = @{ @"emacs": @"E",                 // string value, not an array
                             @"num": @(42),                  // number value, not an array
                             @"P": @[ @"python" ] };         // one valid entry survives
    NSDictionary *inverted = nil;
    XCTAssertNoThrow(inverted = [input it_invertedGraphicDictionary]);
    XCTAssertEqualObjects(inverted[@"python"], @[ @"P" ]);
    XCTAssertEqual(inverted.count, 1);
}

// A non-string element inside the array (e.g. {"E":[123,"emacs"]}) must not become a dictionary
// key of the wrong type; only the string element is mapped.
- (void)testInvertedGraphicDictionaryToleratesNonStringElement {
    NSDictionary *input = @{ @"E": @[ @(123), @"emacs" ] };
    NSDictionary *inverted = nil;
    XCTAssertNoThrow(inverted = [input it_invertedGraphicDictionary]);
    XCTAssertEqualObjects(inverted[@"emacs"], @[ @"E" ]);
    XCTAssertEqual(inverted.count, 1);
}

// A non-string key (JSON can't produce this, but a programmatic/plist path could) must be skipped
// rather than used as a graphic name that later gets string-appended.
- (void)testInvertedGraphicDictionaryToleratesNonStringKey {
    NSDictionary *input = @{ @(7): @[ @"emacs" ],
                             @"P": @[ @"python" ] };
    NSDictionary *inverted = nil;
    XCTAssertNoThrow(inverted = [input it_invertedGraphicDictionary]);
    XCTAssertNil(inverted[@"emacs"]);
    XCTAssertEqualObjects(inverted[@"python"], @[ @"P" ]);
    XCTAssertEqual(inverted.count, 1);
}

@end
