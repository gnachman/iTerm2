//
//  iTermCacheTests.m
//  ModernTests
//

#import <XCTest/XCTest.h>

#import "iTermCache.h"

// A probe whose dealloc decrements a shared counter, so a test can observe
// whether the cache actually released its values when it went away.
@interface iTermCacheLeakProbe : NSObject
+ (void)resetLiveCount;
+ (NSInteger)liveCount;
@end

static NSInteger gProbeLive = 0;

@implementation iTermCacheLeakProbe
+ (void)resetLiveCount { gProbeLive = 0; }
+ (NSInteger)liveCount { return gProbeLive; }
- (instancetype)init {
    self = [super init];
    if (self) {
        gProbeLive++;
    }
    return self;
}
- (void)dealloc {
    gProbeLive--;
}
@end

@interface iTermCacheTests : XCTestCase
@end

@implementation iTermCacheTests

// iTermDoublyLinkedListEntry has both dllNext and dllPrevious as strong
// references, so every adjacent pair forms a retain cycle. When the
// owning iTermCache is dropped, the cache's dictionary and list both go
// away, but the cycle keeps every entry — and every cached value — alive
// forever.
- (void)testDroppingNonEmptyCacheReleasesValues {
    [iTermCacheLeakProbe resetLiveCount];
    @autoreleasepool {
        iTermCache<NSString *, iTermCacheLeakProbe *> *cache =
            [[iTermCache alloc] initWithCapacity:100];
        for (int i = 0; i < 5; i++) {
            NSString *key = [NSString stringWithFormat:@"k%d", i];
            iTermCacheLeakProbe *value = [[iTermCacheLeakProbe alloc] init];
            cache[key] = value;
        }
        XCTAssertEqual([iTermCacheLeakProbe liveCount], 5,
                       @"sanity: all 5 values should be alive while cache exists");
        cache = nil;
    }
    XCTAssertEqual([iTermCacheLeakProbe liveCount], 0,
                   @"all values should have been released when the cache went away");
}

@end
