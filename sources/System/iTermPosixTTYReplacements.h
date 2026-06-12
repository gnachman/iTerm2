//
//  iTermPosixTTYReplacements.h
//  iTerm2
//
//  Created by George Nachman on 7/25/19.
//

#import "iTermTTYState.h"

#include <limits.h>
#include <termios.h>

extern const int kNumFileDescriptorsToDup;

typedef struct {
    pid_t pid;
    // Client socket FD for recvmsg and sendmsg
    int connectionFd;
    int deadMansPipe[2];
    int numFileDescriptorsToPreserve;
    int writeFd;  // For multi-server, use this file descriptor for writing.
} iTermForkState;

// Just like forkpty but fd 0 the master and fd 1 the slave.
int iTermPosixTTYReplacementForkPty(int *amaster,
                                    iTermTTYState *ttyState,
                                    int serverSocketFd,
                                    int deadMansPipeWriteEnd);

// Call this in the child after fork. This never returns, even if it can't exec the target.
void iTermExec(const char *argpath,
               char **argv,
               int closeFileDescriptors,
               int restoreResourceLimits,
               const iTermForkState *forkState,
               const char *initialPwd,
               char **newEnviron,
               int errorFd) __attribute__((noreturn));

void iTermSignalSafeWrite(int fd, const char *message);
void iTermSignalSafeWriteInt(int fd, int n);

// `orig` is an array of ints with file descriptor numbers that we wish to preserve. The first one
// gets remapped to fd 0, the second one to fd 1, etc. `count` gives the length of the array.
void iTermPosixMoveFileDescriptors(int *orig, int count);

// Combines fork and exec.
// If fork is true, returns -1 and sets errno on error. If fork is false it does not return.
// Unlike iTermExec it cannot reset resource limits in children.
pid_t iTermSpawn(const char *argpath,
                char *const *argv,
                const int *fds,
                int numFds,
                const char *initialPwd,
                char **newEnviron,
                int errorFd,
                int fork);
