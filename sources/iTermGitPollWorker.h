//
//  iTermGitPollWorker.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/18.
//

#import <Foundation/Foundation.h>
#import "iTermGitState.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermGitPollWorker : NSObject
+ (instancetype)instanceForPath:(NSString *)path;
- (void)requestPath:(NSString *)path completion:(void (^)(iTermGitState *))completion;
- (void)invalidateCacheForPath:(NSString *)path;
@end

NS_ASSUME_NONNULL_END
