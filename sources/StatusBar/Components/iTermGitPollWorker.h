//
//  iTermGitPollWorker.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/18.
//

#import <Foundation/Foundation.h>
#import "iTermGitState.h"

NS_ASSUME_NONNULL_BEGIN

// Where an iTermGitPoller gets git state. The shared iTermGitPollWorker reads repositories on this
// Mac; iTermRemoteGitPollWorker reads them on a host reached through SSH Integration.
@protocol iTermGitPollWorkerProtocol<NSObject>
// `gitBase` selects the file-status comparison base (see
// pidinfoProtocol). Cache key includes it, so HEAD-relative status
// fetches and base-relative ones don't collide.
- (void)requestPath:(NSString *)path
            gitBase:(NSString * _Nullable)gitBase
   includeDiffStats:(BOOL)includeDiffStats
         completion:(void (^)(iTermGitState * _Nullable, BOOL timedOut))completion;
- (void)invalidateCacheForPath:(NSString *)path;
@end

// Fetches git state for a path. The default sends the request through
// iTermSlowOperationGateway. Tests substitute their own.
typedef void (^iTermGitPollWorkerRequester)(NSString *path,
                                            NSString * _Nullable gitBase,
                                            BOOL includeDiffStats,
                                            void (^completion)(iTermGitState * _Nullable state, BOOL timedOut));

@interface iTermGitPollWorker : NSObject<iTermGitPollWorkerProtocol>
+ (instancetype)sharedInstance;
- (instancetype)init;
- (instancetype)initWithRequester:(iTermGitPollWorkerRequester)requester NS_DESIGNATED_INITIALIZER;
- (nullable NSString *)cachedBranchForPath:(NSString *)path;
- (NSString *)debugInfoForDirectory:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
