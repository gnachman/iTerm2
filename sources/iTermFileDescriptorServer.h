#ifndef __ITERM_FILE_DESCRIPTOR_SERVER_H
#define __ITERM_FILE_DESCRIPTOR_SERVER_H

#include <sys/socket.h>

typedef union {
    struct cmsghdr cm;
    char control[CMSG_SPACE(sizeof(int))];
} FileDescriptorControlMessage;

int FileDescriptorServerRun(char *path, pid_t childPid);

#endif  // __ITERM_FILE_DESCRIPTOR_SERVER_H
