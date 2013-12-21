//
//  VT100RemoteHost.m
//  iTerm
//
//  Created by George Nachman on 12/20/13.
//
//

#import "VT100RemoteHost.h"

@implementation VT100RemoteHost
@synthesize entry;

- (void)dealloc {
    [_hostname release];
    [_username release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p hostname=%@ username=%@>",
            self.class, self, self.hostname, self.username];
}

@end
