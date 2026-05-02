//
//  iTermGitPoller.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermGitPoller;
@class iTermGitState;

@protocol iTermGitPollerDelegate <NSObject>

- (BOOL)gitPollerShouldPoll:(iTermGitPoller *)poller after:(NSDate * _Nullable)lastPoll;

@end

@interface iTermGitPoller : NSObject
@property (nonatomic) NSTimeInterval cadence;
@property (nonatomic, copy) NSString *currentDirectory;
@property (nonatomic) BOOL enabled;
// When YES, the poller asks the git service to also compute line/file-level
// diff stats. This can be expensive; leave NO unless the caller needs it.
@property (nonatomic) BOOL includeDiffStats;
// Optional ref the per-file status comparison runs against. nil
// (or "HEAD") preserves the legacy `git status`-style output. Any
// other value (e.g. a branch name or "origin/master^^^") makes the
// poller emit fileStatuses for everything that differs between the
// working tree and that base — for the workgroup file picker.
// Setting a new value invalidates the per-path cache and bumps so
// the picker repopulates without waiting for the next poll tick.
@property (nonatomic, copy, nullable) NSString *gitBase;
@property (nonatomic, readonly) iTermGitState *state;
@property (nonatomic, weak) id<iTermGitPollerDelegate> delegate;
@property (nonatomic, readonly) NSDate *lastPollTime;
@property (nonatomic, readonly) BOOL hasSuccessfullyFetched;
@property (nonatomic, readonly) BOOL lastPollTimedOut;

- (instancetype)initWithCadence:(NSTimeInterval)cadence
                         update:(void (^)(void))update NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

// Poll immediately if possible.
- (void)bump;

// Clear the "last poll timed out" flag and repoll immediately. Use this after changing something
// that might change the outcome of a poll (e.g., increasing the git timeout) so the UI stops
// showing the timeout error while the retry is in flight.
- (void)clearTimeoutFlagAndRetry;

@end

NS_ASSUME_NONNULL_END
