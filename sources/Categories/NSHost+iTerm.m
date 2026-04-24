//
//  NSHost+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/3/18.
//

#import "NSHost+iTerm.h"

#include <unistd.h>

@implementation NSHost(iTerm)

+ (NSString *)fullyQualifiedDomainName {
    char buffer[MAXHOSTNAMELEN];
    const int rc = gethostname(buffer, sizeof(buffer));
    NSString *name = nil;
    if (rc == 0) {
        name = [NSString stringWithUTF8String:buffer];
    }
    return name ?: @"localhost";
}

@end

