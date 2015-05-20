#ifndef __ITERM_FILE_DESCRIPTOR_CLIENT_H
#define __ITERM_FILE_DESCRIPTOR_CLIENT_H

#include <unistd.h>

typedef struct {
  int ok;
  char *error;
  int ptyMasterFd;
  pid_t childPid;
} FileDescriptorClientResult;

FileDescriptorClientResult FileDescriptorClientRun(char *path);

#endif  // __ITERM_FILE_DESCRIPTOR_CLIENT_H
