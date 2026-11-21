//
//  OrderedDictionaryNullabilityTests.m
//  ModernTests
//
//  +[iTermOrderedDictionary byMapping:block:] and
//  +byMappingEnumerator:block: are called by the graph delta encoder with a
//  record's children, nil for a record without any, under a nonnull claim
//  (unit N11 of docs/swift-migration/nullability-triage.md). The loop over a
//  nil enumerator runs zero times. No Swift code calls these methods, so the
//  claims are pinned here in Objective-C. Before they were made nullable,
//  these calls were -Wnonnull warnings and nullability sanitizer reports.
//

#import <XCTest/XCTest.h>

#import "iTermOrderedDictionary.h"

@interface OrderedDictionaryNullabilityTests : XCTestCase
@end

@implementation OrderedDictionaryNullabilityTests

- (void)testMappingNilIsEmpty {
    iTermOrderedDictionary<NSString *, NSString *> *dictionary =
        [iTermOrderedDictionary byMapping:nil block:^NSString *(NSUInteger index, NSString *object) {
            return object;
        }];
    XCTAssertEqual(dictionary.keys.count, 0);
    XCTAssertEqual(dictionary.values.count, 0);
}

- (void)testMappingNilEnumeratorIsEmpty {
    iTermOrderedDictionary<NSString *, NSString *> *dictionary =
        [iTermOrderedDictionary byMappingEnumerator:nil block:^NSString *(NSUInteger index, NSString *object) {
            return object;
        }];
    XCTAssertEqual(dictionary.keys.count, 0);
}

@end
