//
//  iTermFileDescriptorSocketPath.c
//  iTerm2
//
//  Created by George Nachman on 6/6/15.
//
//

#include "iTermFileDescriptorSocketPath.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

const char *iTermFileDescriptorSocketNamePrefix = "iTerm2.socket.";


// From http://apple.stackexchange.com/questions/22694/private-tmp-vs-private-var-tmp-vs-tmpdir
//
// "TMPDIR as defined in OSX is only accessible by yourself"
//   This is handy for a multi-user setup so you don't think other users'
//   iTerm2 sockets are your orphans
//
// "/tmp is cleared out regularly on OSX (see /etc/defaults/periodic.conf),
// /var/tmp very rarely (if at all)."
//   We want the sockets to be long-lived, so we prefer /var/tmp.
//
// $TMPDIR gives me a path like /var/folders/nx/random gibberish/T
//
// From http://blog.magnusviri.com/what-is-var-folders.html
//   "[/var/folders]'s purpose is to increase security by improving permissions (rwxr-xr-x) over
//   previous temp and cache locations..."
//
// Regarding lifespan:
//   "I've read that '/var/folders' is deleted at startup, but that is not true. The confstr man
//   page said the cache will only be deleted with a safe boot and only files older then 3 days are
//   cleaned out of temp."
//
// Based on that, we don't want /var/folders. That site makes another point about home directories:
//   "There is a user cache in ~/Library/Caches and the only advantage I can see for '/var/folders'
//   is to have a cache that is not in the home folder, for example, to avoid transfering data over
//   a network when using network homes"
//
// Obviously, a unix domain socket on a network path sounds like a bad idea (does it even work?)
//
// /var/tmp seems pretty good. I can't find any docs about it, but at least on my system there are
// a bunch of sockets in there and many of them have ancient access times, so things don't get
// cleaned up while they're possibly in use. I would prefer for it to get wiped on reboot, but
// it's more important to keep the sockets around.
//
// P_tmpdir (which goes to /var/tmp) seems the best choice for this.
// /tmp and /var/folders are eliminated because they might delete the sockets.

void iTermFileDescriptorSocketPath(char *buffer, size_t buffer_size, pid_t pid) {
    const char *tmp = iTermFileDescriptorDirectory();
    snprintf(buffer, buffer_size, "%s%s%d", tmp, iTermFileDescriptorSocketNamePrefix, (int)pid);
}

// Note: this must end in /
const char *iTermFileDescriptorDirectory(void) {
    return P_tmpdir;
}

pid_t iTermFileDescriptorProcessIdFromPath(const char *path) {
    char *dotPtr = strrchr(path, '.');
    if (!dotPtr) {
        return -1;
    }
    char *endPtr;
    long pid = strtol(dotPtr + 1, &endPtr, 10);
    if (*endPtr) {
        return -1;
    }
    return pid;
}
