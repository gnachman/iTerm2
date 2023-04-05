//
//  iTermSlowOperationGateway.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/12/20.
//

#import <Foundation/Foundation.h>
#import "iTermCancelable.h"

@class iTermGitState;

NS_ASSUME_NONNULL_BEGIN

// This runs potentially very slow operations outside the process. If they hang forever it's cool,
// we'll just kill the process and start it over. Consequently, these operations are not 100%
// reliable.
@interface iTermSlowOperationGateway : NSObject

// If this is true then it's much more likely to succeed, but no guarantees as this thing has
// inherent race conditiosn.
@property (nonatomic, readonly) BOOL ready;

// Monotonic source of request IDs.
@property (nonatomic, readonly) int nextReqid;

+ (instancetype)sharedInstance;

- (instancetype)init NS_UNAVAILABLE;

// NOTE: the completion block won't be called if it times out.
- (void)checkIfDirectoryExists:(NSString *)directory
                    completion:(void (^)(BOOL))completion;

// NOTE: the completion block won't be called if it times out.
- (void)statFile:(NSString *)path
      completion:(void (^)(struct stat, int))completion;

- (void)asyncGetInfoForProcess:(int)pid
                        flavor:(int)flavor
                           arg:(uint64_t)arg
                    buffersize:(int)buffersize
                         reqid:(int)reqid
                    completion:(void (^)(int rc, NSData *buffer))completion;

// Get the value of an environment variable from the user's shell.
- (void)exfiltrateEnvironmentVariableNamed:(NSString *)name
                                     shell:(NSString *)shell
                                completion:(void (^)(NSString *value))completion;

- (void)runCommandInUserShell:(NSString *)command completion:(void (^)(NSString * _Nullable value))completion;

- (void)findCompletionsWithPrefix:(NSString *)prefix
                    inDirectories:(NSArray<NSString *> *)directories
                              pwd:(NSString *)pwd
                         maxCount:(NSInteger)maxCount
                       executable:(BOOL)executable
                       completion:(void (^)(NSArray<NSString *> *))completions;

- (void)requestGitStateForPath:(NSString *)path
                    completion:(void (^)(iTermGitState * _Nullable))completion;

- (void)fetchRecentBranchesAt:(NSString *)path count:(NSInteger)maxCount completion:(void (^)(NSArray<NSString *> *))reply;

// If canceled, the completion block won't be run. Canceling is not always successful, though.
- (id<iTermCancelable>)findExistingFileWithPrefix:(NSString *)prefix
                                           suffix:(NSString *)suffix
                                 workingDirectory:(NSString *)workingDirectory
                                   trimWhitespace:(BOOL)trimWhitespace
                                    pathsToIgnore:(NSString *)pathsToIgnore
                               allowNetworkMounts:(BOOL)allowNetworkMounts
                                       completion:(void (^)(NSString *path, int prefixChars, int suffixChars, BOOL workingDirectoryIsLocal))completion;

- (void)executeShellCommand:(NSString *)command
                       args:(NSArray<NSString *> *)args
                        dir:(NSString *)dir
                        env:(NSDictionary<NSString *, NSString *> *)env
                 completion:(void (^)(NSData *stdout,
                                      NSData *stderr,
                                      uint8_t status,
                                      NSTaskTerminationReason reason))completion;

@end

NS_ASSUME_NONNULL_END
