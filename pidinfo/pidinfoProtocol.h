//
//  pidinfoProtocol.h
//  pidinfo
//
//  Created by George Nachman on 1/11/20.
//

#import <Foundation/Foundation.h>

@class iTermGitState;
@class iTermDirectoryEntry;

NS_ASSUME_NONNULL_BEGIN

// The protocol that this service will vend as its API. This header file will also need to be visible to the process hosting the service.
@protocol pidinfoProtocol

- (void)getProcessInfoForProcessID:(NSNumber *)pid
                            flavor:(NSNumber *)flavor
                               arg:(NSNumber *)arg
                              size:(NSNumber *)size
                             reqid:(int)reqid
                         withReply:(void (^ _Nonnull)(NSNumber *rc, NSData *buffer))reply;

- (void)handshakeWithReply:(void (^)(void))reply;

- (void)checkIfDirectoryExists:(NSString *)directory
                     withReply:(void (^)(NSNumber * _Nullable exists))reply;

- (void)checkIfExecutableRegularFile:(NSString *)filename
                         searchPaths:(NSArray<NSString *> *)searchPaths
                           withReply:(void (^)(NSNumber * _Nullable exists))reply;

- (void)statFile:(NSString *)path
       withReply:(void (^)(struct stat statbuf, int error))reply;

// Runs a single-command `script` in `shell`. When `interactive` is YES the shell
// runs with -i, so the user's interactive rc files are sourced and `output`
// reflects the environment a real terminal would have (needed to read variables
// like CLAUDE_CONFIG_DIR that live in .zshrc/.bashrc); pass NO for the fast path
// when the ambient/exported environment suffices (PATH, SSH_AUTH_SOCK), since
// sourcing a heavy rc can cost seconds. Either way the command's stdout is
// captured via a private FIFO, so rc-file/greeting/banner output written to the
// shell's own stdout is kept out of `output`. `error` is the shell's stderr;
// `status` is the command's exit status, or a negative sentinel on internal
// failure (see the implementation) so callers can distinguish "could not run"
// from "ran and produced nothing".
//
// PRECONDITION: `script` must be a single command. The FIFO capture appends a
// `> fifo` redirect, which in a compound script (`a && b`, `a; b`) would bind
// only the last command and silently drop earlier output.
- (void)runShellScript:(NSString *)script
                 shell:(NSString *)shell
           interactive:(BOOL)interactive
             withReply:(void (^)(NSData * _Nullable output,
                                 NSData * _Nullable error,
                                 int status))reply;

- (void)findCompletionsWithPrefix:(NSString *)prefix
                    inDirectories:(NSArray<NSString *> *)directories
                              pwd:(NSString *)pwd
                         maxCount:(NSInteger)maxCount
                       executable:(BOOL)executable
                        withReply:(void (^)(NSArray<NSString *> * _Nullable))reply;

// `gitBase` selects the ref the file-status comparison runs against.
// Pass nil (or "HEAD") for the legacy `git status`-style output —
// the cheap libgit2 status_list pass that compares working tree to
// HEAD/index. Any other value (a branch, tag, or revision spec like
// "origin/master^^^") triggers the diff-against-base path: libgit2
// resolves the spec, diffs its tree against working-tree-with-index,
// and emits one fileStatuses entry per delta. Counts (dirty/adds/
// deletes) keep their HEAD-relative meaning regardless of gitBase.
- (void)requestGitStateForPath:(NSString *)path
                       gitBase:(NSString * _Nullable)gitBase
                       timeout:(int)timeout
              includeDiffStats:(BOOL)includeDiffStats
                    completion:(void (^)(iTermGitState * _Nullable, BOOL timedOut))completion;

- (void)fetchRecentBranchesAt:(NSString *)path count:(NSInteger)maxCount completion:(void (^)(NSArray<NSString *> *))reply;

- (void)findExistingFileWithPrefix:(NSString *)prefix
                            suffix:(NSString *)suffix
                  workingDirectory:(NSString *)workingDirectory
                    trimWhitespace:(BOOL)trimWhitespace
                     pathsToIgnore:(NSString *)pathsToIgnore
                allowNetworkMounts:(BOOL)allowNetworkMounts
                             reqid:(int)reqid
                             reply:(void (^)(NSString * _Nullable path,
                                             int prefixChars,
                                             int suffixChars,
                                             BOOL workingDirectoryIsLocal))reply;

- (void)cancelFindExistingFileRequest:(int)reqid
                               reply:(void (^)(void))reply;

- (void)executeShellCommand:(NSString *)command
                       args:(NSArray<NSString *> *)args
                        dir:(NSString *)dir
                        env:(NSDictionary<NSString *, NSString *> *)env
                      reply:(void (^)(NSData *stdout,
                                      NSData *stderr,
                                      uint8_t status,
                                      NSTaskTerminationReason reason))reply;

- (void)fetchDirectoryListingOfPath:(NSString *)path
                         completion:(void (^)(NSArray<iTermDirectoryEntry *> *entries))completion;

// Returns the calling user's login shell (the pw_shell field). Goes through
// NSS > opendirectoryd, so it can hang if the daemon is wedged. That's why it
// lives in the XPC service: the performRiskyBlock watchdog catches the wedge
// without burning a thread in the main app.
- (void)fetchUserShellWithReply:(void (^)(NSString * _Nullable shell))reply;

@end

NS_ASSUME_NONNULL_END
