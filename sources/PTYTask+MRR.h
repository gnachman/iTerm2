//
//  PTYTask+MRR.h
//  iTerm2Shared
//
//  Created by George Nachman on 4/22/19.
//

#import "PTYTask.h"

#include <util.h>

typedef struct {
    pid_t pid;
    int connectionFd;
    int deadMansPipe[2];
    int numFileDescriptorsToPreserve;
} iTermForkState;

typedef struct {
    struct termios term;
    struct winsize win;
    char tty[PATH_MAX];
} iTermTTYState;

int iTermForkAndExecToRunJobInServer(iTermForkState *forkState,
                                     iTermTTYState *ttyState,
                                     NSString *tempPath,
                                     const char *argpath,
                                     const char **argv,
                                     BOOL closeFileDescriptors,
                                     const char *initialPwd,
                                     char **newEnviron);

int iTermForkAndExecToRunJobDirectly(iTermForkState *forkState,
                                     iTermTTYState *ttyState,
                                     const char *argpath,
                                     const char **argv,
                                     BOOL closeFileDescriptors,
                                     const char *initialPwd,
                                     char **newEnviron);

void iTermSignalSafeWrite(int fd, const char *message);
void iTermSignalSafeWriteInt(int fd, int n);

