//
//  iTermRateLimitedUpdate.h
//  iTerm2
//
//  Created by George Nachman on 6/17/17.
//
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermRateLimitedUpdate : NSObject

@property (nonatomic) NSTimeInterval minimumInterval;
@property (nonatomic) BOOL debug;
@property (nonatomic, readonly) NSTimeInterval deferCount;
@property (nonatomic, readonly, copy) NSString *name;
// When suppression mode is off, the last invocation during the idle time will run after the idle time ends.
// When suppression mode is on, any invocations during the idle time will be ignored.
@property (nonatomic) BOOL suppressionMode;
@property (nonatomic, strong) dispatch_queue_t queue;

- (instancetype)initWithName:(NSString *)name
                minimumInterval:(NSTimeInterval)minimumInterval NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Do not perform a pending action.
- (void)invalidate;

// Performs the block immediately, or perhaps after up to minimumInterval time.
- (void)performRateLimitedBlock:(void (^)(void))block;

// A target/action version of the above.
- (void)performRateLimitedSelector:(SEL)selector
                          onTarget:(id)target
                        withObject:(id _Nullable)object;

// If there is a pending block, do it now (synchronously) and cancel the delayed perform.
- (void)force;

// Forces a pending update to occur within `duration` seconds. Does nothing if
// there is no pending update.
- (void)performWithinDuration:(NSTimeInterval)duration;

@end

// Remembers the delay across restarts. Useful for things like checking for updates every N days.
@interface iTermPersistentRateLimitedUpdate : iTermRateLimitedUpdate
@end

// Only updates after a period of idleness equal to the minimumInterval
@interface iTermRateLimitedIdleUpdate : iTermRateLimitedUpdate
@end

NS_ASSUME_NONNULL_END
