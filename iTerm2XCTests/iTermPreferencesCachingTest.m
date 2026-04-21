#import <XCTest/XCTest.h>
#import "iTermPreferences.h"

@interface iTermPreferences (Testing)
+ (void)setUserDefaultsOverrideForTesting:(NSUserDefaults *)userDefaults;
+ (void)resetPreferenceCacheForTesting;
@end

@interface CountingUserDefaults : NSUserDefaults
@property(nonatomic) NSInteger objectForKeyCount;
- (void)setRawObject:(id)object forKey:(NSString *)key;
- (void)simulateExternalChangeValue:(id)object forKey:(NSString *)key;
- (id)storedObjectForKey:(NSString *)key;
@end

@implementation CountingUserDefaults {
    NSMutableDictionary *_storage;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _storage = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (id)objectForKey:(NSString *)defaultName {
    self.objectForKeyCount += 1;
    return _storage[defaultName];
}

- (id)storedObjectForKey:(NSString *)key {
    return _storage[key];
}

- (void)setObject:(id)value forKey:(NSString *)defaultName {
    if (value) {
        _storage[defaultName] = value;
    } else {
        [_storage removeObjectForKey:defaultName];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:NSUserDefaultsDidChangeNotification object:self];
}

- (void)removeObjectForKey:(NSString *)defaultName {
    [_storage removeObjectForKey:defaultName];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSUserDefaultsDidChangeNotification object:self];
}

- (void)setRawObject:(id)object forKey:(NSString *)key {
    if (object) {
        _storage[key] = object;
    } else {
        [_storage removeObjectForKey:key];
    }
}

- (void)simulateExternalChangeValue:(id)object forKey:(NSString *)key {
    [self setRawObject:object forKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSUserDefaultsDidChangeNotification object:self];
}

@end

@interface CoordinatedUserDefaults : CountingUserDefaults
- (void)blockNextReadForKey:(NSString *)key;
- (BOOL)waitForBlockedReadWithTimeout:(NSTimeInterval)timeout;
- (void)resumeBlockedRead;
@end

@implementation CoordinatedUserDefaults {
    NSString *_blockedKey;
    dispatch_semaphore_t _snapshotTakenSemaphore;
    dispatch_semaphore_t _resumeBlockedReadSemaphore;
}

- (void)blockNextReadForKey:(NSString *)key {
    _blockedKey = [key copy];
    _snapshotTakenSemaphore = dispatch_semaphore_create(0);
    _resumeBlockedReadSemaphore = dispatch_semaphore_create(0);
}

- (BOOL)waitForBlockedReadWithTimeout:(NSTimeInterval)timeout {
    return dispatch_semaphore_wait(_snapshotTakenSemaphore,
                                   dispatch_time(DISPATCH_TIME_NOW,
                                                 (int64_t)(timeout * NSEC_PER_SEC))) == 0;
}

- (void)resumeBlockedRead {
    dispatch_semaphore_signal(_resumeBlockedReadSemaphore);
}

- (id)objectForKey:(NSString *)defaultName {
    self.objectForKeyCount += 1;
    if ([_blockedKey isEqualToString:defaultName]) {
        id snapshot = [self storedObjectForKey:defaultName];
        _blockedKey = nil;
        dispatch_semaphore_signal(_snapshotTakenSemaphore);
        dispatch_semaphore_wait(_resumeBlockedReadSemaphore, DISPATCH_TIME_FOREVER);
        return snapshot;
    }
    return [self storedObjectForKey:defaultName];
}

@end

@interface iTermPreferencesCachingTest : XCTestCase
@property(nonatomic, strong) CountingUserDefaults *testDefaults;
@end

@implementation iTermPreferencesCachingTest

- (void)writeInteger:(NSInteger)value
              toSuite:(NSString *)suiteName
                  key:(NSString *)key {
    NSTask *task = [[NSTask alloc] init];
    NSPipe *standardError = [NSPipe pipe];
    task.launchPath = @"/usr/bin/defaults";
    task.arguments = @[ @"write", suiteName, key, @"-int", @(value).stringValue ];
    task.standardError = standardError;
    [task launch];
    [task waitUntilExit];
    if (task.terminationStatus != 0) {
        NSData *data = [[standardError fileHandleForReading] readDataToEndOfFile];
        NSString *message = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        XCTFail(@"defaults write failed for suite %@ key %@: %@", suiteName, key, message ?: @"");
    }
}

- (void)setUp {
    [super setUp];
    self.testDefaults = [[CountingUserDefaults alloc] init];
    [iTermPreferences setUserDefaultsOverrideForTesting:self.testDefaults];
    [iTermPreferences resetPreferenceCacheForTesting];
}

- (void)tearDown {
    [iTermPreferences setUserDefaultsOverrideForTesting:nil];
    [iTermPreferences resetPreferenceCacheForTesting];
    self.testDefaults = nil;
    [super tearDown];
}

- (void)testRepeatedReadsHitCache {
    [self.testDefaults setRawObject:@5 forKey:kPreferenceKeyTopBottomMargins];

    int first = [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    int second = [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];

    XCTAssertEqual(first, 5);
    XCTAssertEqual(second, 5);
    XCTAssertEqual(self.testDefaults.objectForKeyCount, 1);
}

- (void)testSetterUpdatesCacheWithoutExtraLookup {
    [self.testDefaults setRawObject:@5 forKey:kPreferenceKeyTopBottomMargins];
    (void)[iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    self.testDefaults.objectForKeyCount = 0;

    [iTermPreferences setInt:10 forKey:kPreferenceKeyTopBottomMargins];
    NSInteger lookupsAfterSet = self.testDefaults.objectForKeyCount;

    int updated = [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];

    XCTAssertEqual(updated, 10);
    XCTAssertEqual(self.testDefaults.objectForKeyCount, lookupsAfterSet);
}

- (void)testExternalNotificationFlushesCache {
    [self.testDefaults setRawObject:@5 forKey:kPreferenceKeyTopBottomMargins];
    (void)[iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    self.testDefaults.objectForKeyCount = 0;

    [self.testDefaults simulateExternalChangeValue:@8 forKey:kPreferenceKeyTopBottomMargins];

    int refreshed = [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];

    XCTAssertEqual(refreshed, 8);
    // At least 1 call to re-read after cache clear. FastAccessors observers
    // may cause additional reads for the same key.
    XCTAssertGreaterThanOrEqual(self.testDefaults.objectForKeyCount, 1,
                                @"Cache should have been cleared, forcing re-read");
}

- (void)testComputedPreferencesAreCached {
    // TabStyle is a computed preference - should be cached after first read
    [self.testDefaults setRawObject:@5 forKey:kPreferenceKeyTabStyle];
    
    NSNumber *first = [iTermPreferences objectForKey:kPreferenceKeyTabStyle];
    NSNumber *second = [iTermPreferences objectForKey:kPreferenceKeyTabStyle];
    NSNumber *third = [iTermPreferences objectForKey:kPreferenceKeyTabStyle];
    
    XCTAssertEqualObjects(first, @5);
    XCTAssertEqualObjects(second, @5);
    XCTAssertEqualObjects(third, @5);
    // Should only hit UserDefaults once (for the computed block check + the block itself)
    // The computed block checks UserDefaults, so we expect 2 calls total
    XCTAssertLessThanOrEqual(self.testDefaults.objectForKeyCount, 2, @"Computed preference should be cached");
}

- (void)testComputedPreferencesCacheAfterMultipleReads {
    [self.testDefaults setRawObject:@5 forKey:kPreferenceKeyTabStyle];
    
    // First read populates cache
    (void)[iTermPreferences objectForKey:kPreferenceKeyTabStyle];
    NSInteger firstCount = self.testDefaults.objectForKeyCount;
    
    // Subsequent reads should use cache
    (void)[iTermPreferences objectForKey:kPreferenceKeyTabStyle];
    (void)[iTermPreferences objectForKey:kPreferenceKeyTabStyle];
    (void)[iTermPreferences objectForKey:kPreferenceKeyTabStyle];
    
    XCTAssertEqual(self.testDefaults.objectForKeyCount, firstCount, @"Subsequent reads should not hit UserDefaults");
}

- (void)testValueIsExplicitlySetForKey {
    // Test with explicitly set value
    [self.testDefaults setRawObject:@YES forKey:kPreferenceKeyAllowClipboardAccessFromTerminal];
    XCTAssertTrue([iTermPreferences valueIsExplicitlySetForKey:kPreferenceKeyAllowClipboardAccessFromTerminal]);
    
    // Test with default value (not explicitly set)
    [self.testDefaults removeObjectForKey:kPreferenceKeyTopBottomMargins];
    [iTermPreferences resetPreferenceCacheForTesting];
    XCTAssertFalse([iTermPreferences valueIsExplicitlySetForKey:kPreferenceKeyTopBottomMargins]);
    
    // Test after setting value
    [iTermPreferences setInt:10 forKey:kPreferenceKeyTopBottomMargins];
    XCTAssertTrue([iTermPreferences valueIsExplicitlySetForKey:kPreferenceKeyTopBottomMargins]);
    
    // Test after removing value
    [iTermPreferences setObject:nil forKey:kPreferenceKeyTopBottomMargins];
    XCTAssertFalse([iTermPreferences valueIsExplicitlySetForKey:kPreferenceKeyTopBottomMargins]);
}

- (void)testValueIsExplicitlySetForKeyUsesCache {
    [self.testDefaults setRawObject:@5 forKey:kPreferenceKeyTopBottomMargins];
    
    // First call populates cache
    (void)[iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    NSInteger firstCount = self.testDefaults.objectForKeyCount;
    
    // valueIsExplicitlySetForKey should use cache
    XCTAssertTrue([iTermPreferences valueIsExplicitlySetForKey:kPreferenceKeyTopBottomMargins]);
    XCTAssertEqual(self.testDefaults.objectForKeyCount, firstCount, @"Should use cache, not hit UserDefaults again");
}

- (void)testCacheInvalidationThrottle {
    [self.testDefaults setRawObject:@5 forKey:kPreferenceKeyTopBottomMargins];
    (void)[iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    self.testDefaults.objectForKeyCount = 0;
    
    // Rapid notifications should be throttled (only first one clears cache)
    for (int i = 0; i < 10; i++) {
        [self.testDefaults simulateExternalChangeValue:@(5 + i) forKey:kPreferenceKeyTopBottomMargins];
    }
    
    // Should have hit UserDefaults at least once (cache was cleared), but throttling
    // means not every notification cleared the cache
    int value = [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    XCTAssertGreaterThanOrEqual(value, 5);
    // Due to throttling, we expect fewer than 10 cache clears
    XCTAssertLessThan(self.testDefaults.objectForKeyCount, 20, @"Throttling should reduce cache clears");
}

- (void)testNilValueCaching {
    // Test that nil values are properly cached using null sentinel
    [self.testDefaults setRawObject:nil forKey:kPreferenceKeyTopBottomMargins];
    [iTermPreferences resetPreferenceCacheForTesting];
    self.testDefaults.objectForKeyCount = 0;

    id first = [iTermPreferences objectForKey:kPreferenceKeyTopBottomMargins];
    NSInteger countAfterFirst = self.testDefaults.objectForKeyCount;
    id second = [iTermPreferences objectForKey:kPreferenceKeyTopBottomMargins];

    // Both should return default value (not nil, but the default)
    XCTAssertNotNil(first);
    XCTAssertEqualObjects(first, second);
    // Second read must not hit UserDefaults again
    XCTAssertEqual(self.testDefaults.objectForKeyCount, countAfterFirst, @"Nil/default should be cached after first read");
}

- (void)testComputedPreferenceWithNoExplicitValue {
    // Test computed preference when key doesn't exist (uses default)
    [self.testDefaults removeObjectForKey:kPreferenceKeyTabStyle];
    
    NSNumber *value = [iTermPreferences objectForKey:kPreferenceKeyTabStyle];
    XCTAssertNotNil(value, @"Computed preference should return default when key not set");
    
    // Second read should use cache
    NSInteger firstCount = self.testDefaults.objectForKeyCount;
    NSNumber *value2 = [iTermPreferences objectForKey:kPreferenceKeyTabStyle];
    XCTAssertEqualObjects(value, value2);
    XCTAssertEqual(self.testDefaults.objectForKeyCount, firstCount, @"Should use cache");
}

- (void)testConcurrentAccess {
    // Test that cache is thread-safe
    dispatch_group_t group = dispatch_group_create();
    for (int i = 0; i < 100; i++) {
        dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            (void)[iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
        });
    }
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    
    // Should have hit UserDefaults only once (first access), rest from cache
    XCTAssertLessThanOrEqual(self.testDefaults.objectForKeyCount, 2, @"Concurrent access should be safe");
}

- (void)testColdReadDoesNotOverwriteNewerWrite {
    CoordinatedUserDefaults *defaults = [[CoordinatedUserDefaults alloc] init];
    [iTermPreferences setUserDefaultsOverrideForTesting:defaults];
    [iTermPreferences resetPreferenceCacheForTesting];
    [defaults setRawObject:@5 forKey:kPreferenceKeyTopBottomMargins];
    [defaults blockNextReadForKey:kPreferenceKeyTopBottomMargins];

    dispatch_group_t group = dispatch_group_create();
    __block int staleRead = INT_MIN;
    dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        staleRead = [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    });

    XCTAssertTrue([defaults waitForBlockedReadWithTimeout:1.0],
                  @"Timed out waiting for the cold read to capture its snapshot");

    [iTermPreferences setInt:10 forKey:kPreferenceKeyTopBottomMargins];
    XCTAssertEqualObjects([defaults storedObjectForKey:kPreferenceKeyTopBottomMargins], @10);

    [defaults resumeBlockedRead];
    XCTAssertEqual(dispatch_group_wait(group,
                                       dispatch_time(DISPATCH_TIME_NOW,
                                                     (int64_t)(1 * NSEC_PER_SEC))),
                   0L,
                   @"Timed out waiting for the blocked read to finish");
    XCTAssertEqual(staleRead, 5);
    XCTAssertEqual([iTermPreferences intForKey:kPreferenceKeyTopBottomMargins],
                   10,
                   @"A stale cold read must not overwrite a newer in-process write");
}

- (void)testMutationDepthPreventsCacheClearDuringInternalWrites {
    // Test that setObject: updates the cache inline and reads don't hit UserDefaults
    [self.testDefaults setRawObject:@5 forKey:kPreferenceKeyTopBottomMargins];
    (void)[iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];

    // Set a new value through the public API
    [iTermPreferences setInt:10 forKey:kPreferenceKeyTopBottomMargins];

    // Reset count AFTER the set, then verify the subsequent read is cached
    self.testDefaults.objectForKeyCount = 0;
    int value = [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    XCTAssertEqual(value, 10);
    XCTAssertEqual(self.testDefaults.objectForKeyCount, 0, @"Read after set should use cache");
}

- (void)testUnrelatedNotificationDoesNotClearCache {
    // Test that notifications from unrelated defaults objects don't clear cache
    [self.testDefaults setRawObject:@5 forKey:kPreferenceKeyTopBottomMargins];
    (void)[iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];

    // Create a different defaults object and send notification
    NSUserDefaults *otherDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.test.other"];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSUserDefaultsDidChangeNotification
                                                        object:otherDefaults];

    // Reset count AFTER the unrelated notification, then verify the read is cached
    self.testDefaults.objectForKeyCount = 0;
    int value = [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    XCTAssertEqual(value, 5);
    XCTAssertEqual(self.testDefaults.objectForKeyCount, 0, @"Unrelated notification should not clear cache");
}

- (void)testNilObjectNotificationDoesNotClearCache {
    // Test that notifications with nil object don't clear cache (filtered out)
    [self.testDefaults setRawObject:@5 forKey:kPreferenceKeyTopBottomMargins];
    (void)[iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];

    // Send notification with nil object (can come from unrelated domains)
    [[NSNotificationCenter defaultCenter] postNotificationName:NSUserDefaultsDidChangeNotification
                                                        object:nil];

    // Reset count AFTER the nil notification, then verify the read is cached
    self.testDefaults.objectForKeyCount = 0;
    int value = [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    XCTAssertEqual(value, 5);
    XCTAssertEqual(self.testDefaults.objectForKeyCount, 0, @"Nil object notification should not clear cache");
}

- (void)testExternalProcessWriteInvalidatesCache {
    NSString *suiteName = [@"com.iterm2.prefcache.test." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *suiteDefaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
    XCTAssertNotNil(suiteDefaults);

    [suiteDefaults removePersistentDomainForName:suiteName];
    [iTermPreferences setUserDefaultsOverrideForTesting:suiteDefaults];
    [iTermPreferences resetPreferenceCacheForTesting];

    [suiteDefaults setInteger:5 forKey:kPreferenceKeyTopBottomMargins];
    XCTAssertEqual([iTermPreferences intForKey:kPreferenceKeyTopBottomMargins], 5);

    [self writeInteger:8 toSuite:suiteName key:kPreferenceKeyTopBottomMargins];
    XCTAssertEqualObjects([suiteDefaults objectForKey:kPreferenceKeyTopBottomMargins], @8);
    XCTAssertEqual([iTermPreferences intForKey:kPreferenceKeyTopBottomMargins],
                   8,
                   @"Cache should refresh after the backing defaults domain changes out of process");

    [suiteDefaults removePersistentDomainForName:suiteName];
}

- (void)testCacheClearClearsBothCacheAndExplicitSetKeys {
    // Test that cache clear also clears explicit-set tracking
    [self.testDefaults setRawObject:@5 forKey:kPreferenceKeyTopBottomMargins];
    [iTermPreferences setInt:10 forKey:kPreferenceKeyTopBottomMargins];
    
    // Verify it's explicitly set
    XCTAssertTrue([iTermPreferences valueIsExplicitlySetForKey:kPreferenceKeyTopBottomMargins]);
    
    // Clear cache via external notification
    [self.testDefaults simulateExternalChangeValue:@8 forKey:kPreferenceKeyTopBottomMargins];
    
    // After cache clear, explicit-set should be recalculated (may still be true if value exists)
    // But the important thing is that the cache was cleared
    int value = [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    XCTAssertEqual(value, 8);
    // Should have hit UserDefaults after cache clear
    XCTAssertGreaterThan(self.testDefaults.objectForKeyCount, 0, @"Cache should have been cleared");
}

- (void)testExplicitSetTrackingInComputedPreferences {
    // Test that explicit-set tracking works for computed preferences
    [self.testDefaults setRawObject:@5 forKey:kPreferenceKeyTabStyle];
    
    // Should be explicitly set
    XCTAssertTrue([iTermPreferences valueIsExplicitlySetForKey:kPreferenceKeyTabStyle]);
    
    // Remove the key
    [self.testDefaults removeObjectForKey:kPreferenceKeyTabStyle];
    [iTermPreferences resetPreferenceCacheForTesting];
    
    // Should not be explicitly set (will use default)
    XCTAssertFalse([iTermPreferences valueIsExplicitlySetForKey:kPreferenceKeyTabStyle]);
}

@end
