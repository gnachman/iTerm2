//
//  iTermBackgroundCommandRunner.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/20/20.
//

#import <Foundation/Foundation.h>
#import "iTermCommandRunner.h"

NS_ASSUME_NONNULL_BEGIN

// Runs a command through /bin/sh -c and adds it to the script console, optionally posting a
// notification if it fails.
@interface iTermBackgroundCommandRunner : NSObject<iTermCommandRunner>
@property (nonatomic) NSString *command;
@property (nonatomic) NSString *shell;
@property (nonatomic) NSString *title;
@property (nonatomic, nullable, copy) NSString *notificationTitle;  // Title to show in user notification
@property (atomic, nullable, copy) NSString *path;

- (instancetype)initWithCommand:(nullable NSString *)command
                          shell:(nullable NSString *)shell
                          title:(nullable NSString *)title;

- (instancetype)init NS_DESIGNATED_INITIALIZER;

- (void)run;

@end

@interface iTermBackgroundCommandRunnerPromise: iTermBackgroundCommandRunner
@property (nonatomic, copy) void (^ _Nullable terminationBlock)(iTermBackgroundCommandRunner *, int);

- (void)fulfill;
@end

NS_ASSUME_NONNULL_END
