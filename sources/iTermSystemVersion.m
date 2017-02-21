//
//  iTermSystemVersion.m
//  iTerm2
//
//  Created by George Nachman on 1/3/16.
//
//

#import "iTermSystemVersion.h"
#import <Cocoa/Cocoa.h>

#import "DebugLogging.h"

typedef struct {
    unsigned int major;
    unsigned int minor;
    unsigned int bugfix;
} iTermSystemVersion;

// http://cocoadev.com/DeterminingOSVersion
static BOOL GetSystemVersionMajor(unsigned int *major,
                                  unsigned int *minor,
                                  unsigned int *bugFix) {
    NSDictionary *version = [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
    NSString *productVersion = [version objectForKey:@"ProductVersion"];
    DLog(@"product version is %@", productVersion);
    NSArray *parts = [productVersion componentsSeparatedByString:@"."];
    if (parts.count == 0) {
        return NO;
    }
    if (major) {
        *major = [[parts objectAtIndex:0] intValue];
        if (*major < 10) {
            return NO;
        }
    }
    if (minor) {
        *minor = 0;
        if (parts.count > 1) {
            *minor = [[parts objectAtIndex:1] intValue];
        }
    }
    if (bugFix) {
        *bugFix = 0;
        if (parts.count > 2) {
            *bugFix = [[parts objectAtIndex:2] intValue];
        }
    }
    return YES;
}

iTermSystemVersion CachedSystemVersion(void) {
    static iTermSystemVersion version;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        GetSystemVersionMajor(&version.major, &version.minor, &version.bugfix);
    });
    return version;
}

BOOL SystemVersionIsGreaterOrEqualTo(unsigned major, unsigned minor, unsigned bugfix) {
    iTermSystemVersion version = CachedSystemVersion();
    if (version.major > major) {
        return YES;
    } else if (version.major < major) {
        return NO;
    }
    if (version.minor > minor) {
        return YES;
    } else if (version.minor < minor) {
        return NO;
    }
    return version.bugfix >= bugfix;
}

BOOL IsElCapitanOrLater(void) {
    return SystemVersionIsGreaterOrEqualTo(10, 11, 0);
}

BOOL IsSierraOrLater(void) {
    return SystemVersionIsGreaterOrEqualTo(10, 12, 0);
}

BOOL IsTouchBarAvailable(void) {
    // Checking for OS version doesn't work because there were two different 10.12.1's.
    return [NSApp respondsToSelector:@selector(setAutomaticCustomizeTouchBarMenuItemEnabled:)];
}
