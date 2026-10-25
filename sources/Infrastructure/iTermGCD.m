//
//  iTermGCD.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/21/22.
//

#import "iTermGCD.h"
#import "iTermAdvancedSettingsModel.h"
#import "DebugLogging.h"

#import <stdatomic.h>

@implementation iTermMutationQueueJoinState {
    _Atomic BOOL _performingJoinedBlock;
}

- (BOOL)performingJoinedBlock {
    return atomic_load(&_performingJoinedBlock);
}

- (BOOL)setPerformingJoinedBlock:(BOOL)value {
    return atomic_exchange(&_performingJoinedBlock, value);
}

@end

@implementation iTermGCD

static char iTermGCDMainQueueSafeKey;

static char iTermGCDSpecificMainQueueSafe_Yes;
static char iTermGCDSpecificMainQueueSafe_No;

static char iTermGCDMutationQueueSafeKey;

static char iTermGCDSpecificMutationQueueSafe_Yes;
static char iTermGCDSpecificMutationQueueSafe_No;

static const char *iTermGCDMutationQueueLabel = "com.iterm2.mutation";
static const char *iTermGCDSessionMutationQueueLabel = "com.iterm2.mutation.session";

// Set on every mutation queue to its iTermMutationQueueJoinState (retained).
static char iTermGCDJoinStateKey;

+ (void)initialize {
    if (self != [iTermGCD self]) {
        return;
    }
    dispatch_queue_set_specific(dispatch_get_main_queue(),
                                &iTermGCDMainQueueSafeKey,
                                &iTermGCDSpecificMainQueueSafe_Yes,
                                nil);
}

+ (dispatch_queue_t)_mutationQueue {
    static dispatch_queue_t mutationQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mutationQueue = [self makeMutationQueueWithLabel:iTermGCDMutationQueueLabel];
    });
    return mutationQueue;
}

+ (dispatch_queue_t)makeMutationQueueWithLabel:(const char *)label {
    dispatch_queue_t queue = dispatch_queue_create(label, DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(queue,
                                &iTermGCDMutationQueueSafeKey,
                                &iTermGCDSpecificMutationQueueSafe_Yes,
                                nil);
    dispatch_queue_set_specific(queue,
                                &iTermGCDJoinStateKey,
                                (void *)CFBridgingRetain([[iTermMutationQueueJoinState alloc] init]),
                                (dispatch_function_t)CFRelease);
    return queue;
}

+ (dispatch_queue_t)mutationQueue {
    return [self _mutationQueue];
}

+ (dispatch_queue_t)newMutationQueue {
    return [self makeMutationQueueWithLabel:iTermGCDSessionMutationQueueLabel];
}

+ (iTermMutationQueueJoinState *)joinStateForQueue:(dispatch_queue_t)queue {
    void *state = dispatch_queue_get_specific(queue, &iTermGCDJoinStateKey);
    ITAssertWithMessage(state != NULL, @"Not a mutation queue: %@", queue);
    return (__bridge iTermMutationQueueJoinState *)state;
}

+ (dispatch_queue_t)deallocQueue {
    static dispatch_queue_t deallocQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        deallocQueue = dispatch_queue_create("com.iterm2.dealloc", DISPATCH_QUEUE_SERIAL);
    });
    return deallocQueue;
}

+ (void)assertMainQueueSafe {
    void *addr = dispatch_get_specific(&iTermGCDMainQueueSafeKey);
    assert(addr == &iTermGCDSpecificMainQueueSafe_Yes);
}

+ (void)assertMainQueueSafe:(NSString *)message, ... {
    void *addr = dispatch_get_specific(&iTermGCDMainQueueSafeKey);
    if (addr == &iTermGCDSpecificMainQueueSafe_Yes) {
        return;
    }
    va_list args;
    va_start(args, message);
    NSString *s = [[NSString alloc] initWithFormat:message arguments:args];
    va_end(args);

    ITAssertWithMessage(NO, @"Not main-queue safe: %@", s);
}

+ (void)assertMutationQueueSafe {
    void *addr = dispatch_get_specific(&iTermGCDMutationQueueSafeKey);
    assert(addr == &iTermGCDSpecificMutationQueueSafe_Yes);
}

+ (void)assertMutationQueueSafe:(NSString *)message, ... {
    void *addr = dispatch_get_specific(&iTermGCDMutationQueueSafeKey);
    if (addr == &iTermGCDSpecificMutationQueueSafe_Yes) {
        return;
    }
    va_list args;
    va_start(args, message);
    NSString *s = [[NSString alloc] initWithFormat:message arguments:args];
    va_end(args);

    ITAssertWithMessage(NO, @"Not mutation-queue safe: %@", s);
}

+ (BOOL)isMainQueueSafe {
    return dispatch_get_specific(&iTermGCDMainQueueSafeKey) == &iTermGCDSpecificMainQueueSafe_Yes;
}

+ (BOOL)isMutationQueueSafe {
    return dispatch_get_specific(&iTermGCDMutationQueueSafeKey) == &iTermGCDSpecificMutationQueueSafe_Yes;
}

// Main queue only. How many joins are in progress, so nested joins of different queues leave the
// main queue marked until the outermost ends.
static NSInteger gMainQueueJoinDepth;

+ (void)setMainQueueSafe:(BOOL)safe onQueue:(dispatch_queue_t)queue {
    ITAssertWithMessage([self onMainQueue], @"setMainQueueSafe:onQueue: is main queue only");
    // A queue is joined at most once at a time: a nested join of the same queue takes the
    // reentrancy shortcut instead of joining again.
    ITAssertWithMessage(!safe || dispatch_queue_get_specific(queue, &iTermGCDMainQueueSafeKey) != &iTermGCDSpecificMainQueueSafe_Yes,
                        @"%@ is already joined", queue);
    dispatch_queue_set_specific(queue,
                                &iTermGCDMainQueueSafeKey,
                                safe ? &iTermGCDSpecificMainQueueSafe_Yes : &iTermGCDSpecificMainQueueSafe_No,
                                nil);
    if (safe) {
        gMainQueueJoinDepth += 1;
    } else {
        ITAssertWithMessage(gMainQueueJoinDepth > 0, @"Unbalanced setMainQueueSafe:NO");
        gMainQueueJoinDepth -= 1;
    }
    const BOOL mainIsMutationSafe = gMainQueueJoinDepth > 0;
    dispatch_queue_set_specific(dispatch_get_main_queue(),
                                &iTermGCDMutationQueueSafeKey,
                                mainIsMutationSafe ? &iTermGCDSpecificMutationQueueSafe_Yes : &iTermGCDSpecificMutationQueueSafe_No,
                                nil);
}

+ (BOOL)onMutationQueue {
    return dispatch_get_specific(&iTermGCDJoinStateKey) != NULL;
}

+ (BOOL)onMainQueue {
    return dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL) == dispatch_queue_get_label(dispatch_get_main_queue());
}

static _Atomic BOOL gJoined;

+ (BOOL)joined {
    return gJoined;
}

+ (void)setJoined:(BOOL)joined {
    gJoined = joined;
}

@end
