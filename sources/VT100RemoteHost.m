//
//  VT100RemoteHost.m
//  iTerm
//
//  Created by George Nachman on 12/20/13.
//
//

#import "VT100RemoteHost.h"
#import "DebugLogging.h"
#import "NSDictionary+iTerm.h"
#import "NSHost+iTerm.h"
#import "NSObject+iTerm.h"

static NSString *const kRemoteHostHostNameKey = @"Host name";
static NSString *const kRemoteHostUserNameKey = @"User name";

@implementation VT100RemoteHost
@synthesize entry;

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        self.hostname = dict[kRemoteHostHostNameKey];
        self.username = dict[kRemoteHostUserNameKey];
    }
    return self;
}

+ (instancetype)localhost {
    VT100RemoteHost *localhost = [[self alloc] init];
    localhost.hostname = [NSHost fullyQualifiedDomainName];
    localhost.username = NSUserName();
    return localhost;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p hostname=%@ username=%@>",
            self.class, self, self.hostname, self.username];
}

- (BOOL)isEqualToRemoteHost:(VT100RemoteHost *)other {
    return ([_hostname isEqualToString:other.hostname] &&
            [_username isEqualToString:other.username]);
}

- (NSString *)usernameAndHostname {
    return [NSString stringWithFormat:@"%@@%@", _username, _hostname];
}

- (BOOL)isLocalhost {
    NSString *localHostName = [NSHost fullyQualifiedDomainName];
    if ([self.hostname isEqualToString:localHostName]) {
        return YES;
    }
    return [localHostName isEqualToString:self.hostname];
}

#pragma mark - IntervalTreeObject

- (NSDictionary *)dictionaryValue {
    NSDictionary *dict =
        @{ kRemoteHostHostNameKey: _hostname ?: [NSNull null],
           kRemoteHostUserNameKey: _username ?: [NSNull null] };
    return [dict dictionaryByRemovingNullValues];
}

@end
