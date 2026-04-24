//
//  PTYTask+MRR.h
//  iTerm2Shared
//
//  Created by George Nachman on 4/22/19.
//

#import "PTYTask.h"

#import "iTermTTYState.h"
#import "iTermPosixTTYReplacements.h"

#include <util.h>

int iTermForkAndExecToRunJobInServer(iTermForkState *forkState,
                                     iTermTTYState *ttyState,
                                     NSString *tempPath,
                                     const char *argpath,
                                     char **argv,
                                     BOOL closeFileDescriptors,
                                     const char *initialPwd,
                                     char **newEnviron);

int iTermForkAndExecToRunJobDirectly(iTermForkState *forkState,
                                     iTermTTYState *ttyState,
                                     const char *argpath,
                                     char **argv,
                                     BOOL closeFileDescriptors,
                                     const char *initialPwd,
                                     char **newEnviron);

void iTermSignalSafeWrite(int fd, const char *message);
void iTermSignalSafeWriteInt(int fd, int n);

