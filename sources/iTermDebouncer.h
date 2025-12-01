//
//  iTermDebouncer.h
//  iTerm2SharedARC
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * A debouncer that implements a state machine to intelligently delay execution based on query length.
 * This prevents flickering/blinking when typing and reduces unnecessary operations.
 *
 * The debouncer uses different states based on query length:
 * - Short queries (1-2 chars): Delayed to avoid excessive triggering
 * - Medium queries (3-4 chars): Active, executes immediately
 * - Long queries (5+ chars): Active, executes immediately
 *
 * Queries become "stale" when they are short and haven't been edited in 3 seconds,
 * causing the debouncer to re-enter the delay state.
 */
@interface iTermDebouncer : NSObject

/**
 * Initializes a debouncer with a callback block that will be invoked when the query should be executed.
 *
 * @param callback Block to execute when the debounced query should be processed.
 *                 The block receives the current query string as a parameter.
 */
- (instancetype)initWithCallback:(void (^)(NSString *query))callback NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

/**
 * Updates the query string and triggers the state machine logic.
 * The callback may be invoked immediately, after a delay, or not at all depending on the state.
 *
 * @param query The updated query string.
 */
- (void)updateQuery:(NSString *)query;

/**
 * Call this when the owning view becomes first responder.
 * This helps the debouncer handle focus changes appropriately.
 */
- (void)owningViewDidBecomeFirstResponder;

@end

NS_ASSUME_NONNULL_END
