//
//  iTermPidinfoDebugLogging.m
//  pidinfo
//
//  Created by George Nachman on 2/24/22.
//

#import <Foundation/Foundation.h>
#include <syslog.h>

BOOL gDebugLogging = YES;

int DebugLogImpl(const char *file, int line, const char *function, NSString *value) {
    const char *lastSlash = strrchr(file, '/');
        if (!lastSlash) {
            lastSlash = file;
        } else {
            lastSlash++;
        }
    syslog(LOG_DEBUG, "%s:%d (%s): %s", lastSlash, line, function, value.UTF8String);
    return 1;
}
