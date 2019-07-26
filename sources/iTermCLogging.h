//
//  iTermCLogging.h
//  iTerm2
//
//  Created by George Nachman on 1/5/20.
//

#include <syslog.h>

// Because xcode is hot garbage, syslog(LOG_DEBUG) goes to its console so we turn that off for debug builds.
#if DEBUG
#define FDLog(level, format, ...) do { \
    if (level < LOG_DEBUG) { \
        syslog(level, "iTermServer-Client(%d) " format, getpid(), ##__VA_ARGS__); \
    } \
} while (0)
#else
#if ITERM_SERVER
#define FDLog(level, format, ...) syslog(level, "iTermServer(pid=%d) " format, getpid(), ##__VA_ARGS__)
#else
#define FDLog(level, format, ...) syslog(level, "iTermServer-Client(%d) " format, getpid(), ##__VA_ARGS__)
#endif  // ITERM_SERVER
#endif  // DEBUG
