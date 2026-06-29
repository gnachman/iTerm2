//
//  iTermTaskQueue.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/29/24.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


typedef void(^iTermQueueableTask)(void);

// This is a deque of closures. It tries to be fast AF.
@interface iTermTaskQueue : NSObject
@property(nonatomic, readonly) NSUInteger count;

- (void)appendTask:(iTermQueueableTask)task NS_SWIFT_NAME(append(_:));
- (void)appendTasks:(NSArray<iTermQueueableTask> *)tasks NS_SWIFT_NAME(appendTasks(_:));
- (void (^_Nullable)(void))dequeue;
- (int64_t)setFlag:(int64_t)flag;
- (int64_t)resetFlags;

@end

NS_ASSUME_NONNULL_END
