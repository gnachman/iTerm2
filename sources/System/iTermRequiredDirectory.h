// Internal, project-only launch acknowledgement. Ordinary launches leave the channel disabled.
#ifndef ITERM_REQUIRED_DIRECTORY_H
#define ITERM_REQUIRED_DIRECTORY_H
#include <sys/types.h>

typedef struct {
    int readFD;
    int writeFD;
} iTermRequiredDirectoryChannel;

// Returns zero or an errno value. The caller should run preflight off the main thread.
int iTermRequiredDirectoryValidate(const char *path);
int iTermRequiredDirectoryOpenChannel(int required, iTermRequiredDirectoryChannel *channel);
// Async-signal-safe. Enters the directory, acknowledges its actual chdir result, and exits on failure.
void iTermRequiredDirectoryEnterInChild(const char *path, iTermRequiredDirectoryChannel channel);
// Reads the child's result. On failure closes the master, reaps the child, and sets *pid = -1.
int iTermRequiredDirectoryFinishInParent(iTermRequiredDirectoryChannel channel, pid_t *pid, int *masterFD);
#endif
