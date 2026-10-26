//
//  iTermGCD.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/21/22.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// =============================================================================
// Terminal Coordination Signals
// =============================================================================
//
// This class centralizes coordination state for the single-writer architecture:
//
// Every session shares one mutation queue unless task I/O monitors are on, in which case each
// session has its own (newMutationQueue). A join pauses one queue, so join state belongs to the
// queue: sessions on the shared queue share it.
//
// JOIN CONTEXT (main queue only):
// - iTermMutationQueueJoinState.performingJoinedBlock: YES when inside a joined
//   block for that queue. Used to handle reentrant join requests gracefully
//   (run them immediately without another semaphore handshake, since that
//   queue is already paused).
//
// QUEUE SAFETY MARKERS (for assertions, which are enabled in release builds):
// - `setMainQueueSafe:onQueue:` / `assertMainQueueSafe`: Queue-specific context
//   markers. These verify code is running in a context where it's safe to
//   access main-queue or mutation-queue state. The main queue stays mutation-
//   queue safe until the outermost of nested joins ends.
//
// RELATED STATE (not in this class):
// - pauseCount/globalPauseCount (TokenExecutor): Counters controlling when
//   token execution pauses. Can be nested.
// - executingSideEffects (TokenExecutor): Per-instance reentrancy guard for
//   side-effect execution.
// - joinInProgress (TokenExecutor, DEBUG): Backstop assert catching any
//   reentrant whilePaused: calls that bypass performingJoinedBlock check.
//
// =============================================================================

// Whether the main queue is running a joined block for one mutation queue.
@interface iTermMutationQueueJoinState : NSObject
// YES when inside a joined block for this queue. Reentrant join requests check
// this to run immediately without another semaphore handshake.
@property (atomic, readonly) BOOL performingJoinedBlock;
// Sets the flag and returns its previous value, atomically.
- (BOOL)setPerformingJoinedBlock:(BOOL)value;
@end

@interface iTermGCD : NSObject

#pragma mark - Queues

// The mutation queue that sessions share.
+ (dispatch_queue_t)mutationQueue;
// A new mutation queue for one session.
+ (dispatch_queue_t)newMutationQueue;
// The join state of a queue from mutationQueue or newMutationQueue.
+ (iTermMutationQueueJoinState *)joinStateForQueue:(dispatch_queue_t)queue;
+ (dispatch_queue_t)deallocQueue;
// YES on any mutation queue, or a queue that targets one.
+ (BOOL)onMutationQueue;
// YES on the mutation queue with this join state, or a queue that targets it.
+ (BOOL)onMutationQueueWithJoinState:(iTermMutationQueueJoinState *)joinState;
+ (BOOL)onMainQueue;

#pragma mark - Queue Safety Assertions

+ (void)assertMainQueueSafe;
+ (void)assertMainQueueSafe:(NSString *)message, ...;

+ (void)assertMutationQueueSafe;
+ (void)assertMutationQueueSafe:(NSString *)message, ...;

// Whether the current queue may use state belonging to `queue`, a mutation queue: it is `queue` (or
// targets it), or it is the main queue while main has joined `queue`. Stricter than
// assertMutationQueueSafe, which accepts main while it has joined any mutation queue.
+ (BOOL)isSafeForMutationQueue:(dispatch_queue_t)queue;
+ (void)assertSafeForMutationQueue:(dispatch_queue_t)queue;

// Whether the current queue is marked safe for main-queue or mutation-queue state.
+ (BOOL)isMainQueueSafe;
+ (BOOL)isMutationQueueSafe;

// Main queue only. Call with YES when starting to join `queue` and NO when done.
+ (void)setMainQueueSafe:(BOOL)safe onQueue:(dispatch_queue_t)queue;

@end

NS_ASSUME_NONNULL_END
