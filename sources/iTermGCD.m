//
//  iTermGCD.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/21/22.
//

#import "iTermGCD.h"
#import "iTermAdvancedSettingsModel.h"
#import "DebugLogging.h"

@implementation iTermGCD

static char iTermGCDMainQueueSafeKey;

static char iTermGCDSpecificMainQueueSafe_Yes;
static char iTermGCDSpecificMainQueueSafe_No;

static char iTermGCDMutationQueueSafeKey;

static char iTermGCDSpecificMutationQueueSafe_Yes;
static char iTermGCDSpecificMutationQueueSafe_No;

static const char *iTermGCDMutationQueueLabel = "com.iterm2.mutation";

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
        mutationQueue = dispatch_queue_create(iTermGCDMutationQueueLabel, DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(mutationQueue,
                                    &iTermGCDMutationQueueSafeKey,
                                    &iTermGCDSpecificMutationQueueSafe_Yes,
                                    nil);
    });
    return mutationQueue;
}

+ (dispatch_queue_t)mutationQueue {
    return [self _mutationQueue];
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

+ (void)setMainQueueSafe:(BOOL)safe {
    dispatch_queue_set_specific([self _mutationQueue],
                                &iTermGCDMainQueueSafeKey,
                                safe ? &iTermGCDSpecificMainQueueSafe_Yes : &iTermGCDSpecificMainQueueSafe_No,
                                nil);
    dispatch_queue_set_specific(dispatch_get_main_queue(),
                                &iTermGCDMutationQueueSafeKey,
                                safe ? &iTermGCDSpecificMutationQueueSafe_Yes : &iTermGCDSpecificMutationQueueSafe_No,
                                nil);
}

+ (BOOL)onMutationQueue {
    return dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL) == iTermGCDMutationQueueLabel;
}

+ (BOOL)onMainQueue {
    return dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL) == dispatch_queue_get_label(dispatch_get_main_queue());
}

@end
