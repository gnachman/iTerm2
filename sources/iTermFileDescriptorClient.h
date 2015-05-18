#ifndef __ITERM_FILE_DESCRIPTOR_CLIENT_H
#define __ITERM_FILE_DESCRIPTOR_CLIENT_H

// Tries to read three file descriptors and fill in fileDescriptors[0...2]
// with their values. Returns the number of file descriptors read. 0 and 1 are stdin and stdout,
// 3 is the reading half of a pipe that wil be written to if the child dies unexpectedly.
int FileDescriptorClientRun(char *path, int *fileDescriptors, int *pidPtr);

#endif  // __ITERM_FILE_DESCRIPTOR_CLIENT_H
