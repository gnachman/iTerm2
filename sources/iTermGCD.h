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
// JOIN CONTEXT (main queue only):
// - `joined`: YES when mutation queue has paused and is waiting for main to
//   finish a joined block. During this time, main queue can safely access
//   mutable terminal state.
// - `performingJoinedBlock`: YES when inside a joined block callback. Used to
//   handle reentrant join requests gracefully (run them immediately without
//   another semaphore handshake, since we're already joined).
//
// QUEUE SAFETY MARKERS (for assertions):
// - `setMainQueueSafe:` / `assertMainQueueSafe`: Queue-specific context markers
//   used for DEBUG assertions. These verify code is running in a context where
//   it's safe to access main-queue or mutation-queue state.
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

@interface iTermGCD : NSObject

#pragma mark - Join Context

// YES when mutation queue has paused and is waiting. Main queue can safely
// access mutable state while this is YES.
@property (atomic, class) BOOL joined;

// YES when inside a joined block callback. Reentrant join requests check this
// to run immediately without another semaphore handshake.
// Uses atomic_exchange semantics; returns previous value when setting.
+ (BOOL)performingJoinedBlock;
+ (BOOL)setPerformingJoinedBlock:(BOOL)value;

#pragma mark - Queues

+ (dispatch_queue_t)mutationQueue;
+ (BOOL)onMutationQueue;
+ (BOOL)onMainQueue;

#pragma mark - Queue Safety Assertions

+ (void)assertMainQueueSafe;
+ (void)assertMainQueueSafe:(NSString *)message, ...;

+ (void)assertMutationQueueSafe;
+ (void)assertMutationQueueSafe:(NSString *)message, ...;

+ (void)setMainQueueSafe:(BOOL)safe;

@end

NS_ASSUME_NONNULL_END
