//
//  iTermPTY.h
//  iTerm2
//
//  Created by George Nachman on 11/12/19.
//

#import <Foundation/Foundation.h>
#import "iTermFileDescriptorClient.h"
#include <termios.h>

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

@protocol iTermPTY<NSObject>
- (void)shutdown;
- (void)closeFileDescriptor;
// TODO: eliminate
- (BOOL)pidIsChild;
// TODO: eliminate
- (pid_t)serverPid;
- (int)fd;
- (pid_t)pid;
// TODO: eliminate
- (void)sendSignal:(int)signo toServer:(BOOL)toServer;
- (void)invalidate;
- (BOOL)tryToAttachToServerWithProcessId:(pid_t)thePid;
- (void)attachToServer:(iTermFileDescriptorServerConnection)serverConnection;
- (void)killServerIfRunning;
- (void)didForkParent:(const iTermForkState *)forkState
             ttyState:(iTermTTYState *)ttyState
          synchronous:(BOOL)synchronous
           completion:(void (^)(NSString *tty, BOOL failedImmediately, BOOL shouldRegister))completion;

// Returns NO if it failed before calling fork().
- (BOOL)forkAndExecWithEnvironment:(char **)newEnviron
                         forkState:(iTermForkState *)forkState
                          ttyState:(iTermTTYState *)ttyState
                           argPath:(const char *)argpath
                              argv:(const char **)argv
                        initialPwd:(const char *)initialPwd;
- (BOOL)isatty;

@end

