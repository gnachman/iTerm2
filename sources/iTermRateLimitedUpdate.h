//
//  iTermRateLimitedUpdate.h
//  iTerm2
//
//  Created by George Nachman on 6/17/17.
//
//

#import <Foundation/Foundation.h>

@interface iTermRateLimitedUpdate : NSObject

@property (nonatomic) NSTimeInterval minimumInterval;
@property (nonatomic) BOOL debug;

// Do not perform a pending action.
- (void)invalidate;

// Performs the block immediately, or perhaps after up to minimumInterval time.
- (void)performRateLimitedBlock:(void (^)(void))block;

// A target/action version of the above.
- (void)performRateLimitedSelector:(SEL)selector
                          onTarget:(id)target
                        withObject:(id)object;

@end

// Remembers the delay across restarts. Useful for things like checking for updates every N days.
@interface iTermPersistentRateLimitedUpdate : iTermRateLimitedUpdate

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithName:(NSString *)name NS_DESIGNATED_INITIALIZER;

@end

// Only updates after a period of idleness equal to the minimumInterval
@interface iTermRateLimitedIdleUpdate : iTermRateLimitedUpdate
@end

