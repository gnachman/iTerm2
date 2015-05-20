#ifndef __ITERM_FILE_DESCRIPTOR_CLIENT_H
#define __ITERM_FILE_DESCRIPTOR_CLIENT_H

#include <unistd.h>

extern const char *kFileDescriptorClientErrorCouldNotConnect;

typedef struct {
  int ok;
  const char *error;
  int ptyMasterFd;
  pid_t childPid;
} FileDescriptorClientResult;

FileDescriptorClientResult FileDescriptorClientRun(char *path);

#endif  // __ITERM_FILE_DESCRIPTOR_CLIENT_H
