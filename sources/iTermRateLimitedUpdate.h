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

// Do not perform a pending action.
- (void)invalidate;

// Performs the block immediately, or perhaps after up to minimumInterval time.
- (void)performRateLimitedBlock:(void (^)(void))block;

// A target/action version of the above.
- (void)performRateLimitedSelector:(SEL)selector
                          onTarget:(id)target
                        withObject:(id)object;

@end
