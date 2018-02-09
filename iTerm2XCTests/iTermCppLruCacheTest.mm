//
//  iTermCppLruCacheTest.m
//  iTerm2XCTests
//
//  Created by George Nachman on 11/19/17.
//

#import <XCTest/XCTest.h>
#include "lrucache.hpp"

@interface iTermCppLruCacheTest : XCTestCase

@end

const int NUM_OF_TEST2_RECORDS = 100;
const int TEST2_CACHE_CAPACITY = 50;

@implementation iTermCppLruCacheTest

- (void)testSimplePut {
    cache::lru_cache<int, int> cache_lru(1);
    cache_lru.put(7, 777);
    XCTAssertTrue(cache_lru.exists(7));
    XCTAssertEqual(777, *cache_lru.get(7));
    XCTAssertEqual(1, cache_lru.size());
}

- (void)testMissingValue {
    cache::lru_cache<int, int> cache_lru(1);
    XCTAssertEqual(cache_lru.get(7), nullptr);
}

- (void)keepsAllValuesWithinCapacity {
    cache::lru_cache<int, int> cache_lru(TEST2_CACHE_CAPACITY);

    for (int i = 0; i < NUM_OF_TEST2_RECORDS; ++i) {
        cache_lru.put(i, i);
    }

    for (int i = 0; i < NUM_OF_TEST2_RECORDS - TEST2_CACHE_CAPACITY; ++i) {
        XCTAssertFalse(cache_lru.exists(i));
    }

    for (int i = NUM_OF_TEST2_RECORDS - TEST2_CACHE_CAPACITY; i < NUM_OF_TEST2_RECORDS; ++i) {
        XCTAssertTrue(cache_lru.exists(i));
        XCTAssertEqual(i, *cache_lru.get(i));
    }

    size_t size = cache_lru.size();
    XCTAssertEqual(TEST2_CACHE_CAPACITY, size);
}

@end
