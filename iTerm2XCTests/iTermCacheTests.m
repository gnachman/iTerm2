//
//  iTermCacheTests.m
//  iTerm2XCTests
//
//  Created by George Nachman on 11/5/19.
//

#import <XCTest/XCTest.h>
#import "iTermCache.h"

@interface iTermCacheTests : XCTestCase

@end

@implementation iTermCacheTests

- (void)testInsertion {
    iTermCache<NSString *, NSNumber *> *cache = [[iTermCache alloc] initWithCapacity:3];
    cache[@"one"] = @1;
    cache[@"two"] = @2;

    XCTAssertEqualObjects(@1, cache[@"one"]);
    XCTAssertEqualObjects(@2, cache[@"two"]);
}

- (void)testEvictionWithoutReads {
    iTermCache<NSString *, NSNumber *> *cache = [[iTermCache alloc] initWithCapacity:3];
    cache[@"one"] = @1;
    cache[@"two"] = @2;
    cache[@"three"] = @3;
    cache[@"four"] = @4;

    XCTAssertNil(cache[@"one"]);
}

- (void)testEvictionWithReads {
    iTermCache<NSString *, NSNumber *> *cache = [[iTermCache alloc] initWithCapacity:3];
    cache[@"one"] = @1;
    cache[@"two"] = @2;
    cache[@"three"] = @3;

    // Promote 1 to MRU
    XCTAssertEqualObjects(@1, cache[@"one"]);

    // This should evict 2, the LRU
    cache[@"four"] = @4;

    XCTAssertNil(cache[@"two"]);

    XCTAssertEqualObjects(@4, cache[@"four"]);
    XCTAssertEqualObjects(@3, cache[@"three"]);
    XCTAssertEqualObjects(@1, cache[@"one"]);
}

- (void)testReadNeverAddedKey {
    iTermCache<NSString *, NSNumber *> *cache = [[iTermCache alloc] initWithCapacity:3];
    cache[@"one"] = @1;
    XCTAssertNil(cache[@"bogus"]);
}

- (void)testModifyValue {
    iTermCache<NSString *, NSNumber *> *cache = [[iTermCache alloc] initWithCapacity:3];
    cache[@"one"] = @1;
    cache[@"two"] = @2;
    cache[@"three"] = @3;
    cache[@"four"] = @4;

    cache[@"three"] = @33;
    XCTAssertEqualObjects(@4, cache[@"four"]);
    XCTAssertEqualObjects(@33, cache[@"three"]);
    XCTAssertEqualObjects(@2, cache[@"two"]);
}

@end
