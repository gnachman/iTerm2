//
//  iTermFileDescriptorSocketPath.h
//  iTerm2
//
//  Created by George Nachman on 6/6/15.
//
//

#ifndef __iTerm2__iTermFileDescriptorSocketPath__
#define __iTerm2__iTermFileDescriptorSocketPath__

#include <unistd.h>

// Returns the part of the filename between the directory and the process ID in a socket path.
// Default is "iTerm2.socket." but can be changed via iTermFileDescriptorSetSocketNamePrefix().
const char *iTermFileDescriptorSocketNamePrefix(void);

// Sets a custom socket name prefix. Call this before any sockets are created.
// The prefix should end with a period (e.g., "com.example.socket.").
// The string is copied internally.
void iTermFileDescriptorSetSocketNamePrefix(const char *prefix);

// Fills in |buffer| with the path to a file descriptor server socket for process id |pid|.
void iTermFileDescriptorSocketPath(char *buffer, size_t buffer_size, pid_t pid);

// Returns path containing orphans
const char *iTermFileDescriptorDirectory(void);

// Extracts the process ID from a socket filename. Returns -1 if it is ill-formed.
pid_t iTermFileDescriptorProcessIdFromPath(const char *path);

#endif /* defined(__iTerm2__iTermFileDescriptorSocketPath__) */
