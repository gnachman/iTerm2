//
//  iTermBackgroundCommandRunner.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/20/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Runs a command through /bin/sh -c and adds it to the script console, optionally posting a
// notification if it fails.
@interface iTermBackgroundCommandRunner : NSObject
@property (nonatomic, readonly) NSString *command;
@property (nonatomic, readonly) NSString *shell;
@property (nonatomic, readonly) NSString *title;
@property (nonatomic, nullable, copy) NSString *notificationTitle;  // Title to show in user notification
@property (atomic, nullable, copy) NSString *path;

- (instancetype)initWithCommand:(NSString *)command
                          shell:(NSString *)shell
                          title:(NSString *)title NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (void)run;

@end

NS_ASSUME_NONNULL_END
