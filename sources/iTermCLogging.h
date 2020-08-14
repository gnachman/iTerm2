//
//  iTermCLogging.h
//  iTerm2
//
//  Created by George Nachman on 1/5/20.
//

#ifndef ITERMCLOGGING_H
#define ITERMCLOGGING_H

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <syslog.h>
#include <unistd.h>

static inline void CDLogImpl(const int level, const char *func, const char *file, int line, const char *format, ...) {
#if !ITERM_SERVER && !ITERM_XPC
#if DEBUG
    // Because xcode is hot garbage, syslog(LOG_DEBUG) goes to its console so we turn that off for debug builds.
    if (level >= LOG_DEBUG) {
        return;
    }
#endif  // DEBUG
#ifndef __OBJC__
    extern char gDebugLogging;
#endif  // OBJC
    if (!gDebugLogging) {
        return;
    }
#endif  // !ITERM_SERVER && !ITERM_XPC
    va_list args;
    va_start(args, format);
    char *temp = NULL;
#if ITERM_SERVER
    extern const char *gMultiServerSocketPath;
    asprintf(&temp, "iTermServer(pid=%d, path=%s) %s:%d %s: %s", getpid(), gMultiServerSocketPath, file, line, func, format);
    vsyslog(level, temp, args);
#elif ITERM_XPC
    asprintf(&temp, "pidinfo(pid=%d) %s:%d %s: %s", getpid(), file, line, func, format);
    vsyslog(level, temp, args);
#else  // ITERM_SERVER
    extern void DLogC(const char *format, va_list args);
    asprintf(&temp, "iTermClient(pid=%d) %s:%d %s: %s", getpid(), file, line, func, format);
    DLogC(temp, args);
#endif  // ITERM_SERVER
    va_end(args);
    free(temp);
}

// Unified client-server logging function.
// If client, writes to the debug log.
// If server, writes to syslog.
#define FDLog(level, args...) CDLogImpl(level, __FUNCTION__, __FILE__, __LINE__, args)

#endif  // ITERMCELOGGING_H
