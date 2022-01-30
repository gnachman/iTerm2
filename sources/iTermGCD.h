//
//  iTermGCD.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/21/22.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermGCD : NSObject

+ (dispatch_queue_t)mutationQueue;
+ (void)assertMainQueueSafe;
+ (void)assertMainQueueSafe:(NSString *)message, ...;

+ (void)assertMutationQueueSafe;
+ (void)assertMutationQueueSafe:(NSString *)message, ...;

+ (void)setMainQueueSafe:(BOOL)safe;

+ (BOOL)onMutationQueue;
+ (BOOL)onMainQueue;

@end

NS_ASSUME_NONNULL_END
