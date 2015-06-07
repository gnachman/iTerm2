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

// Fills in |buffer| with the path to a file descriptor server socket for process id |pid|.
void iTermFileDescriptorSocketPath(char *buffer, size_t buffer_size, pid_t pid);

// Returns path containing orphans
const char *iTermFileDescriptorDirectory(void);

#endif /* defined(__iTerm2__iTermFileDescriptorSocketPath__) */
