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
// user as `originDisplayName` (e.g. "ssh user@host"), used here only for Script
// Console attribution. The caller is responsible for checking that the API is
// enabled and that this origin has been authorized before calling; this method
// unconditionally runs the command.
// `stdoutBlock`/`stderrBlock` receive output lines (on a background queue).
// `completion` gets the process-style exit code. The command runs on a background
// queue (never main) so its blocking API round-trips do not deadlock the
// dispatch, and the process is never terminated.
//
// `cancellationHandler`, if non-nil, is invoked once the command is about to run
// and handed a `cancel` block. Calling `cancel` (from any thread) unblocks a
// command that is waiting on the API server (e.g. `monitor --follow`) so it
// unwinds and returns promptly; harmless to call after completion. This is how a
// remote Ctrl-C tears down a streaming command.
// `stdinData` is what the remote it2 read from its own stdin, for a command whose payload
// arrives there (a Claude Code hook's JSON). Nil when there was none.
// `environment` is the ALLOWLISTED slice of the remote's environment; see
// IT2ClientContext.allowedEnvNames. Never the whole thing.
// `originSessionID` is the iTerm2 session this connection belongs to, which a remote command
// with no explicit target addresses. A remote host cannot name a session itself.
+ (void)runWithArguments:(NSArray<NSString *> *)arguments
        originIdentifier:(NSString *)originIdentifier
       originDisplayName:(NSString *)originDisplayName
         originSessionID:(nullable NSString *)originSessionID
               stdinData:(nullable NSData *)stdinData
             environment:(NSDictionary<NSString *, NSString *> *)environment
           stdoutHandler:(void (^)(NSString *line))stdoutBlock
           stderrHandler:(void (^)(NSString *line))stderrBlock
     cancellationHandler:(void (^ _Nullable)(dispatch_block_t cancel))cancellationHandler
              completion:(void (^)(int32_t exitCode))completion;

@end

NS_ASSUME_NONNULL_END
