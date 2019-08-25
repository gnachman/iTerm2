//
//  iTermWorkingDirectoryPoller.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/3/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermTmuxOptionMonitor;
@class iTermVariableScope;
@class TmuxGateway;

@protocol iTermWorkingDirectoryPollerDelegate<NSObject>
- (BOOL)workingDirectoryPollerShouldPoll;
- (void)workingDirectoryPollerDidFindWorkingDirectory:(nullable NSString *)path invalidated:(BOOL)invalidated;
- (pid_t)workingDirectoryPollerProcessID;
@end

@interface iTermWorkingDirectoryPoller : NSObject

@property (nonatomic, weak) id<iTermWorkingDirectoryPollerDelegate> delegate;
@property (nonatomic, nullable, strong) iTermTmuxOptionMonitor *tmuxOptionMonitor;

- (instancetype)init NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithTmuxGateway:(TmuxGateway *)gateway
                              scope:(iTermVariableScope *)scope
                         windowPane:(int)windowPane;

- (void)poll;
- (void)didReceiveLineFeed;
- (void)userDidPressKey;
- (void)invalidateOutstandingRequests;

@end

NS_ASSUME_NONNULL_END
