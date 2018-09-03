//
//  iTermWorkingDirectoryPoller.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/3/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol iTermWorkingDirectoryPollerDelegate<NSObject>
- (BOOL)workingDirectoryPollerShouldPoll;
- (void)workingDirectoryPollerDidFindWorkingDirectory:(NSString *)path;
- (pid_t)workingDirectoryPollerProcessID;
@end

@interface iTermWorkingDirectoryPoller : NSObject

@property (nonatomic, weak) id<iTermWorkingDirectoryPollerDelegate> delegate;

- (void)poll;
- (void)didReceiveLineFeed;
- (void)userDidPressKey;

@end

NS_ASSUME_NONNULL_END
