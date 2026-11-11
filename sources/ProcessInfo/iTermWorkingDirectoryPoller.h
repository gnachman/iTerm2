//
//  iTermWorkingDirectoryPoller.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/3/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermTmuxOptionMonitor;
@protocol iTermVariableVendor;
@class TmuxGateway;

@protocol iTermWorkingDirectoryPollerDelegate<NSObject>
- (BOOL)workingDirectoryPollerShouldPoll;
// requestStamp is what workingDirectoryPollerRequestStamp returned when the
// request began, so the delegate can tell which events preceded it.
- (void)workingDirectoryPollerDidFindWorkingDirectory:(nullable NSString *)path
                                          invalidated:(BOOL)invalidated
                                         requestStamp:(NSInteger)requestStamp;
- (pid_t)workingDirectoryPollerProcessID;
// The terminal's foreground process group, or -1 if unknown.
- (pid_t)workingDirectoryPollerForegroundProcessGroup;
// A value recorded when a request begins and handed back with its result. It
// must never decrease.
- (NSInteger)workingDirectoryPollerRequestStamp;
@end

@interface iTermWorkingDirectoryPoller : NSObject

@property (nonatomic, weak) id<iTermWorkingDirectoryPollerDelegate> delegate;
@property (nonatomic, nullable, strong) iTermTmuxOptionMonitor *tmuxOptionMonitor;
// Whether the directory comes from tmux rather than a local process.
@property (nonatomic, readonly) BOOL isTmux;

- (instancetype)init NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithTmuxGateway:(TmuxGateway *)gateway
                              scope:(id<iTermVariableVendor>)scope
                         windowPane:(int)windowPane;

- (void)poll;
- (void)didReceiveLineFeed;
- (void)userDidPressKey;
- (void)invalidateOutstandingRequests;
// Runs on the next result of a request that began no earlier than this call,
// judged by workingDirectoryPollerRequestStamp.
- (void)addOneTimeCompletion:(void (^)(NSString * _Nullable))completion;

// Only when isTmux. Asks tmux for the pane's directory now, bypassing subscriptions and any
// outstanding request. The result is reported to the delegate as any poll result is, and then
// passed to `completion` (nil on error or with no gateway). If the gateway goes away first,
// `completion` is never called.
- (void)fetchTmuxDirectoryNowWithCompletion:(void (^)(NSString * _Nullable))completion;

@end

NS_ASSUME_NONNULL_END
