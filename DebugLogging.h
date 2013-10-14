//
//  DebugLogging.h
//  iTerm
//
//  Created by George Nachman on 10/13/13.
//
//

#import <Foundation/Foundation.h>

extern BOOL gDebugLogging;

// I use a variadic macro here because of an apparent compiler bug in XCode 4.2 that thinks a
// variadaic objc call as an argument is not a single value.
#define DebugLog(args...) DebugLogImpl(__FILE__, __LINE__, __FUNCTION__, args)

//#define GENERAL_VERBOSE_LOGGING
#ifdef GENERAL_VERBOSE_LOGGING
#define DLog NSLog
#else
#define DLog(args...) \
    do { \
        if (gDebugLogging) { \
            DebugLogImpl(__FILE__, __LINE__, __FUNCTION__, [NSString stringWithFormat:args]); \
        } \
    } while (0)
#endif

void ToggleDebugLogging();
int DebugLogImpl(const char *file, int line, const char *function, NSString* value);

