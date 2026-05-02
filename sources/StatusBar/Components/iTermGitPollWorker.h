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
+ (instancetype)sharedInstance;
// `gitBase` selects the file-status comparison base (see
// pidinfoProtocol). Cache key includes it, so HEAD-relative status
// fetches and base-relative ones don't collide.
- (void)requestPath:(NSString *)path
            gitBase:(NSString * _Nullable)gitBase
   includeDiffStats:(BOOL)includeDiffStats
         completion:(void (^)(iTermGitState * _Nullable, BOOL timedOut))completion;
- (void)invalidateCacheForPath:(NSString *)path;
- (NSString *)cachedBranchForPath:(NSString *)path;
- (NSString *)debugInfoForDirectory:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
