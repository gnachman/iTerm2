//
//  iTermFileDescriptorServerShared.h
//  iTerm2
//
//  Created by George Nachman on 11/26/19.
//

#ifndef iTermFileDescriptorServerShared_h
#define iTermFileDescriptorServerShared_h

#include <stdio.h>
#include <sys/socket.h>

#include "DebugLogging.h"

typedef union {
    struct cmsghdr cm;
    char control[CMSG_SPACE(sizeof(int))];
} iTermFileDescriptorControlMessage;

void iTermFileDescriptorServerLog(char *format, ...);
int iTermFileDescriptorServerAcceptAndClose(int socketFd);
int iTermFileDescriptorServerAccept(int socketFd);
void SetRunningServer(void);

ssize_t iTermFileDescriptorServerSendMessageAndFileDescriptor(int connectionFd,
                                                              void *buffer,
                                                              size_t bufferSize,
                                                              int fdToSend);

ssize_t iTermFileDescriptorServerWriteLengthAndBuffer(int connectionFd,
                                                      void *buffer,
                                                      size_t bufferSize,
                                                      int *errorOut);
ssize_t iTermFileDescriptorServerWriteLengthAndBufferAndFileDescriptor(int connectionFd,
                                                                       void *buffer,
                                                                       size_t bufferSize,
                                                                       int fdToSend,
                                                                       int *errorOut);

ssize_t iTermFileDescriptorServerWrite(int fd, void *buffer, size_t bufferSize);

// For use on a pipe or other non-socket
ssize_t iTermFileDescriptorClientWrite(int fd, const void *buffer, size_t bufferSize);

// Takes an array of file descriptors and its length as input. `results` should be an array of
// equal length. On return, the readable FDs will have the corresponding value in `results` set to
// true. Takes care of EINTR. Return value is number of readable FDs.
int iTermSelect(int *fds, int count, int *results, int wantErrors);

// Like iTermSelect but selects for writing.
int iTermSelectForWriting(int *fds, int count, int *results, int wantErrors);

// Create a socket and listen on it. Returns the socket's file descriptor.
// This is used for connecting a client and server prior to fork.
// Follow it with a call to iTermFileDescriptorServerAcceptAndClose().
int iTermFileDescriptorServerSocketBindListen(const char *path);

// Acquire an advisory lock. If successful, returns a file descriptor >= 0.
// If the lock could not be acquired, returns -1.
// You can release the lock by closing the file descriptor.
int iTermAcquireAdvisoryLock(const char *path);

#endif /* iTermFileDescriptorServerShared_h */
