//
//  iTermInProcessIt2.h
//  iTerm2
//
//  Runs the embedded it2 command tree (it2core) in-process on behalf of a remote
//  it2 invoked over SSH integration. Requests are dispatched to the local API
//  server; output streams back to the caller. The command logic is the same code
//  as the standalone `it2` binary; only the transport differs.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermInProcessIt2 : NSObject

// Parse and run `arguments` (excluding the executable name) on behalf of a remote
// it2 identified by `originIdentifier` (a stable per-ssh-session id) shown to the
// user as `originDisplayName` (e.g. "ssh user@host"). The user is prompted once
// per session to allow API access; a denial fails without running the command.
// `stdoutBlock`/`stderrBlock` receive output lines (on a background queue).
// `completion` gets the process-style exit code. The command runs on a background
// queue (never main) so its blocking API round-trips do not deadlock the
// dispatch, and the process is never terminated.
+ (void)runWithArguments:(NSArray<NSString *> *)arguments
        originIdentifier:(NSString *)originIdentifier
       originDisplayName:(NSString *)originDisplayName
                  stdout:(void (^)(NSString *line))stdoutBlock
                  stderr:(void (^)(NSString *line))stderrBlock
              completion:(void (^)(int32_t exitCode))completion;

@end

NS_ASSUME_NONNULL_END
