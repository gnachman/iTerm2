//
//  iTermProcess.h
//  iTerm2
//
//  Created by George Nachman on 5/28/24.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Use posix_spawn to launch a process.
// url: File URL of program to launch
// args: Arguments, including argv[0] being the name of the program.
// fd_in: Readable file descriptor that becomes the child's stdin.
// fd_out: Writable file descriptor that becomes the child's stdout.
//
// Returns -1 on error or a process ID otherwise.
pid_t iTermStartProcess(NSURL *url, NSArray<NSString *> *args, int fd_in, int fd_out);

// Gives Swift access to the WEXITSTATUS macro.
int iTermProcessExitStatus(int status);

NS_ASSUME_NONNULL_END
