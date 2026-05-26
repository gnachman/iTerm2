//
//  NSHost+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/3/18.
//

#import "NSHost+iTerm.h"

#import "iTermAdvancedSettingsModel.h"

#include <unistd.h>

@implementation NSHost(iTerm)

+ (NSString *)fullyQualifiedDomainName {
    // Testing override: pretend the machine has a different hostname so the
    // localhost-detection paths can be exercised without actually renaming the
    // computer. Empty (the default) means use the real hostname.
    NSString *fake = [iTermAdvancedSettingsModel fakeFullyQualifiedDomainName];
    if (fake.length > 0) {
        return fake;
    }
    char buffer[MAXHOSTNAMELEN];
    const int rc = gethostname(buffer, sizeof(buffer));
    NSString *name = nil;
    if (rc == 0) {
        name = [NSString stringWithUTF8String:buffer];
    }
    return name ?: @"localhost";
}

@end

