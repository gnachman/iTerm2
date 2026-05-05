//
//  iTermOpenDirectory+MainApp.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/4/26.
//

#import "iTermOpenDirectory+MainApp.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermPromise.h"
#import "iTermSlowOperationGateway.h"

// Kept very short because callers can hit this on every cadence tick
// (e.g. Run Command triggers).
static const NSTimeInterval kFreshLookupTimeout = 0.020;

// If +prime can't get a value (gateway not ready, opendirectoryd wedged,
// etc.), retry after this delay until the cache is populated.
static const NSTimeInterval kPrimeRetryDelay = 1.0;

// Both protected by @synchronized([iTermOpenDirectory class]).
// gCurrentLookup is never nilled out — once a lookup settles the promise
// stays here until the next caller observes that it's settled and replaces
// it with a fresh one. Keeping the gateway completion out of the
// gCurrentLookup mutation eliminates the race where the completion races
// the assignment to publish a stale settled promise.
static NSString *gCachedShell;
static iTermPromise<NSString *> *gCurrentLookup;

@interface iTermOpenDirectory (MainAppPrivate)
+ (iTermPromise<NSString *> *)inFlightLookupLocked;
@end

@implementation iTermOpenDirectory (MainApp)

// Caller must hold the @synchronized lock. Returns gCurrentLookup if it's
// still in flight; otherwise starts a new lookup and returns that.
+ (iTermPromise<NSString *> *)inFlightLookupLocked {
    if (gCurrentLookup != nil && !gCurrentLookup.hasValue) {
        return gCurrentLookup;
    }
    iTermPromise<NSString *> *p = [iTermPromise promise:^(id<iTermPromiseSeal> seal) {
        [[iTermSlowOperationGateway sharedInstance] fetchUserShellWithCompletion:^(NSString * _Nullable fresh) {
            // Runs off-main. Only writes gCachedShell — gCurrentLookup is
            // intentionally untouched here; the next caller will notice
            // hasValue and rotate to a new promise.
            if (fresh) {
                @synchronized([iTermOpenDirectory class]) {
                    gCachedShell = fresh;
                }
                [seal fulfill:fresh];
            } else {
                [seal rejectWithDefaultError];
            }
        }];
    }];
    gCurrentLookup = p;
    return p;
}

+ (NSString *)userShell {
    if (![iTermAdvancedSettingsModel useOpenDirectory]) {
        return nil;
    }
    iTermPromise<NSString *> *promise;
    NSString *snapshot;
    @synchronized([iTermOpenDirectory class]) {
        snapshot = gCachedShell;
        promise = [self inFlightLookupLocked];
    }

    iTermOr<NSString *, NSError *> *result;
    if (snapshot != nil) {
        // Stale cache is fine if the lookup doesn't return promptly.
        result = [promise waitWithTimeout:kFreshLookupTimeout];
    } else {
        // Nothing to fall back to — block until the lookup settles, even
        // if it rejects.
        result = [promise wait];
    }
    if (result.hasFirst) {
        return result.maybeFirst;
    }
    return snapshot;
}

+ (void)prime {
    if (![iTermAdvancedSettingsModel useOpenDirectory]) {
        return;
    }
    iTermPromise<NSString *> *promise;
    @synchronized([iTermOpenDirectory class]) {
        if (gCachedShell != nil) {
            return;
        }
        promise = [self inFlightLookupLocked];
    }
    // Self-rescheduling: if the lookup rejects (gateway not ready,
    // opendirectoryd wedged), keep retrying until the cache is populated.
    [promise catchError:^(NSError * _Nonnull error) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(kPrimeRetryDelay * NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            [iTermOpenDirectory prime];
        });
    }];
}

@end
