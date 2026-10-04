//
//  iTermSlowOperationGateway.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/12/20.
//

#import <Foundation/Foundation.h>
#import "iTermShellArguments.h"
#import "iTermCancelable.h"

@class iTermGitState;
@class iTermDirectoryEntry;

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

// Get the value of an environment variable from `shell`, read from the
// EXPORTED environment via a fast bare -c shell; the startup files are NOT
// sourced. Right for variables the environment already carries (SSH_AUTH_SOCK).
// A caller that needs a value set only in the startup files (CLAUDE_CONFIG_DIR
// in .zshrc, PATH in .zprofile) must instead use runCommandInUserShell:mode:.
// Delivered exactly once on the main thread; nil if the shell could not be run.
- (void)exfiltrateEnvironmentVariableNamed:(NSString *)name
                                     shell:(NSString *)shell
                                completion:(void (^)(NSString * _Nullable value))completion;

// Runs a single command in the user's shell with a bare -c. rc/banner output is
// stripped; the reply is the command's own stdout, delivered exactly once on the
// main thread, or nil if the command could not be run or exited nonzero.
- (void)runCommandInUserShell:(NSString *)command completion:(void (^)(NSString * _Nullable value))completion;

// Same, but `mode` picks which startup files run (see iTermShellRunMode):
// interactive for variables in the rc files, such as CLAUDE_CONFIG_DIR;
// login-interactive for PATH as a terminal session sees it. Both cost the
// shell's startup time, so use them only when that environment is required.
- (void)runCommandInUserShell:(NSString *)command
                         mode:(iTermShellRunMode)mode
                   completion:(void (^)(NSString * _Nullable value))completion;

// Convenience: YES is iTermShellRunModeInteractive, NO is bare.
- (void)runCommandInUserShell:(NSString *)command
                  interactive:(BOOL)interactive
                   completion:(void (^)(NSString * _Nullable value))completion;

- (void)findCompletionsWithPrefix:(NSString *)prefix
                    inDirectories:(NSArray<NSString *> *)directories
                              pwd:(NSString *)pwd
                         maxCount:(NSInteger)maxCount
                       executable:(BOOL)executable
                       completion:(void (^)(NSArray<NSString *> *))completions;

- (void)requestGitStateForPath:(NSString *)path
                       gitBase:(NSString * _Nullable)gitBase
              includeDiffStats:(BOOL)includeDiffStats
                    completion:(void (^)(iTermGitState * _Nullable, BOOL timedOut))completion;

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

- (void)checkIfExecutableRegularFile:(NSString *)filename
                         searchPaths:(NSArray<NSString *> *)searchPaths  // from $PATH
                          completion:(void (^)(BOOL isExecutableRegularFile))completion;

- (void)fetchDirectoryListingOfPath:(NSString *)path
                         completion:(void (^)(NSArray<iTermDirectoryEntry *> *entries))completion;

// Returns the calling user's login shell. Always invokes `completion` exactly
// once: with the shell on success, or nil if the XPC service isn't ready, the
// underlying daemon (opendirectoryd) is wedged, or no reply arrives within an
// internal timeout. Unlike most gateway methods, the completion does NOT run
// on the main queue — it fires on whatever queue the XPC reply or internal
// timeout uses. This is so a synchronous main-thread caller waiting on this
// result can't deadlock against its own delivery.
- (void)fetchUserShellWithCompletion:(void (^)(NSString * _Nullable shell))completion;

@end

NS_ASSUME_NONNULL_END
