//
//  iTermPromptOnCloseReason.h
//  iTerm2
//
//  Created by George Nachman on 11/29/16.
//
//

#import <Foundation/Foundation.h>
#import "ProfileModel.h"

@interface iTermPromptOnCloseReason : NSObject

@property (nonatomic, readonly) BOOL hasReason;
@property (nonatomic, readonly) NSString *message;

+ (instancetype)noReason;
+ (instancetype)profileAlwaysPrompts:(Profile *)profile;
+ (instancetype)profile:(Profile *)profile blockedByJobs:(NSArray<NSString *> *)jobs;
+ (instancetype)alwaysConfirmQuitPreferenceEnabled;
+ (instancetype)closingMultipleSessionsPreferenceEnabled;
+ (instancetype)tmuxClientsAlwaysPromptBecauseJobsAreNotExposed;

- (void)addReason:(iTermPromptOnCloseReason *)reason;

@end
