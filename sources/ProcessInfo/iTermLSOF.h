//
//  iTermLSOF.h
//  iTerm2
//
//  Created by George Nachman on 11/8/16.
//
//

#import <Foundation/Foundation.h>
#import <sys/param.h>

@class iTermSocketAddress;
@protocol iTermProcessDataSource;

int iTermProcPidInfoWrapper(int pid, int flavor, uint64_t arg,  void *buffer, int buffersize);

// One open file descriptor of a process.
@interface iTermProcessFileDescriptor : NSObject
// The file descriptor number.
@property (nonatomic) int fd;
// A short human-readable kind: "file", "TCP", "UDP", "unix", "pipe", "kqueue", etc.
@property (nonatomic, copy) NSString *type;
// For files: the path. For network sockets: "local → remote (STATE)". For unix
// sockets: the socket path. Empty when there is nothing useful to show.
@property (nonatomic, copy) NSString *detail;
@end

// A process as +[iTermLSOF foregroundShellPidWithRootPid:foregroundProcessGroup:lookup:processTable:arguments:]
// sees it.
typedef struct {
    pid_t pid;
    pid_t ppid;
    pid_t pgid;
    // Whether it has exec'ed since it was forked.
    BOOL didExec;
    // The device of its controlling terminal, or NODEV if it has none.
    dev_t tty;
    // The foreground process group of its controlling terminal, or 0 if none.
    pid_t ttyForegroundProcessGroup;
    // p_comm, the name of the executable it last exec'ed, NUL-terminated.
    char name[MAXCOMLEN + 1];
} iTermWalkProcess;

@interface iTermLSOF : NSObject

// Each argument shell-escaped, so the joined result can be pasted into a shell.
+ (NSArray<NSString *> *)commandLineArgumentsForProcess:(pid_t)pid execName:(NSString **)execName;
// Each argument exactly as the process received it.
+ (NSArray<NSString *> *)rawCommandLineArgumentsForProcess:(pid_t)pid execName:(NSString **)execName;
+ (NSString *)commandForProcess:(pid_t)pid execName:(NSString **)execName;
// The process's environment as an array of "KEY=VALUE" strings, or nil if it
// could not be read (e.g. the process is owned by another user). Extracted from
// the same KERN_PROCARGS2 buffer as the command line.
+ (NSArray<NSString *> *)environmentForProcess:(pid_t)pid;
// The process's open file descriptors (files, sockets, pipes, etc.), or nil if
// they could not be read (e.g. the process is owned by another user).
+ (NSArray<iTermProcessFileDescriptor *> *)fileDescriptorsForProcess:(pid_t)pid;
// If the given file descriptor of the process is open on a terminal device
// (a /dev/tty* character device), returns that device's rdev (the same value as
// stat(2).st_rdev of the device file). Returns 0 if the fd is not a tty (e.g. a
// pipe, regular file, socket, or a non-terminal character device like /dev/null)
// or cannot be read. Used to tell whether a process's stdin/stdout is actually
// the session's terminal.
+ (dev_t)ttyRdevForFileDescriptor:(int)fd ofProcess:(pid_t)pid;
+ (NSString *)displayCommandForProcess:(pid_t)pid execName:(NSString **)execName;
+ (NSArray<NSNumber *> *)allPids;
+ (pid_t)ppidForPid:(pid_t)childPid;
// Reads the whole process table with one sysctl(KERN_PROC_ALL) and calls block once
// per live (non-zombie) process. name is nil when the kernel reports an empty p_comm
// (typically mid-exec). Returns NO, without calling block, if the table could not be read.
+ (BOOL)enumerateProcessTable:(void (^ NS_NOESCAPE)(pid_t pid, pid_t ppid, NSString *name, BOOL isForeground))block;
+ (NSString *)nameOfProcessWithPid:(pid_t)thePid isForeground:(BOOL *)isForeground;

// Best-effort human-readable explanation of why nameOfProcessWithPid: would return
// nil for this pid, obtained by re-reading. Intended for a cold diagnostic path (an
// ancestry name that unexpectedly came back empty), not routine use, since it does
// another sysctl. Distinguishes a sysctl error, a pid that isn't in the process list
// (not matched / likely exited), a matched-but-empty comm (mid-exec), and the case
// where the name is readable again (the original failure was transient).
+ (NSString *)nameFailureDiagnosisForPid:(pid_t)pid;
+ (NSString *)workingDirectoryOfProcess:(pid_t)pid;
+ (void)asyncWorkingDirectoryOfProcess:(pid_t)pid
                                 queue:(dispatch_queue_t)queue
                                 block:(void (^)(NSString *pwd))block;
// The working directory of the shell the user is in, which in a nested shell (bash run from zsh,
// poetry shell) is not the session's root process. If the leader of the terminal's foreground
// process group is a shell at its prompt (it exec'ed, so it isn't a subshell, and runs no script or
// -c command), that's the one. Otherwise the foreground job is a command, maybe a script or
// subshell, and the shell is the one that started it: the nearest ancestor outside the foreground
// group, since only a shell doing job control puts a command in a group of its own. So a command
// that changes its own directory (make -C), a subshell's cd, or a script's cd doesn't count, and an
// ssh client gives the directory of the shell that ran it. If the leader has exited (`ps aux | less`
// once ps finishes), the walk starts from another member of the group.
//
// A job may relay another pty (sudo -s with use_pty, poetry shell, script, expect). If exactly one
// process below the job is on a different terminal, the same search runs on that terminal, and its
// result is used if it finds an interactive shell there: a shell at its prompt, or one that started
// that terminal's foreground job. A root shell from sudo -s is found but its directory can't be
// read, so the result is nil rather than the directory of the shell that ran sudo. If the inner
// terminal has no interactive shell (expect driving ssh, a tool running `bash -c`), nobody is
// typing into a shell there, and the shell that started the outer job is the answer. That also
// holds when several processes below the job are on other terminals (an editor with terminal
// buffers), since which one the user is in can't be known.
//
// Without a foreground process group (pgrp <= 0), or when the walk reaches rootPid (e.g., the
// session runs a command, not a shell), this reads rootPid as
// asyncWorkingDirectoryOfProcess:queue:block: does.
+ (void)asyncWorkingDirectoryOfForegroundShellWithRootPid:(pid_t)rootPid
                                   foregroundProcessGroup:(pid_t)pgrp
                                                    queue:(dispatch_queue_t)queue
                                                    block:(void (^)(NSString *pwd))block;
+ (NSString *)workingDirectoryOfForegroundShellWithRootPid:(pid_t)rootPid
                                    foregroundProcessGroup:(pid_t)pgrp;
// Whether a process name (as the kernel or process cache reports it, maybe "-zsh") is an
// interactive shell.
+ (BOOL)processNameIsAShell:(NSString *)name;
// The pid whose working directory the method above reads, or -1 for none. lookup reads one
// process, returning NO if it doesn't exist or is a zombie; it's enough when the foreground group's
// leader is a shell at its prompt. Otherwise processTable is called once for the whole table, as
// iTermWalkProcess structs in any order without zombies, or nil if it can't be read. arguments
// gives a process's argv, or nil if they can't be read. Exposed for tests.
+ (pid_t)foregroundShellPidWithRootPid:(pid_t)rootPid
                foregroundProcessGroup:(pid_t)pgrp
                                lookup:(BOOL (^ NS_NOESCAPE)(pid_t pid, iTermWalkProcess *process))lookup
                          processTable:(NSData *(^ NS_NOESCAPE)(void))processTable
                             arguments:(NSArray<NSString *> *(^)(pid_t pid))arguments;
// Whether a shell with these arguments (argv[0] first) runs a script or a -c command rather than
// reading commands from the terminal. Exposed for tests.
+ (BOOL)shellArgumentsRunScriptOrCommand:(NSArray<NSString *> *)argv;
+ (pid_t)pidOfFirstChildOf:(pid_t)parentPid;
+ (NSDate *)startTimeForProcess:(pid_t)pid;
+ (id<iTermProcessDataSource>)processDataSource;

@end
