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

@implementation VT100RemoteHost {
    VT100RemoteHost *_doppelganger;
    __weak VT100RemoteHost *_progenitor;
    BOOL _isDoppelganger;
}

@synthesize entry;
@synthesize username = _username;
@synthesize hostname = _hostname;

- (instancetype)initWithUsername:(NSString *)username hostname:(NSString *)hostname {
    self = [super init];
    if (self) {
        _username = [username copy];
        _hostname = [hostname copy];
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    return [self initWithUsername:dict[kRemoteHostUserNameKey]
                         hostname:dict[kRemoteHostHostNameKey]];
}

+ (instancetype)localhost {
    VT100RemoteHost *localhost = [[self alloc] initWithUsername:NSUserName()
                                                       hostname:[NSHost fullyQualifiedDomainName]];
    return localhost;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p hostname=%@ username=%@ doppelganger=%p (%@) progenitor=%p>",
            self.class, self, self.hostname, self.username, _doppelganger, _isDoppelganger ? @"IsDop" : @"NotDop", _progenitor];
}

- (BOOL)isEqualToRemoteHost:(id<VT100RemoteHostReading>)other {
    return ([_hostname isEqualToString:other.hostname] &&
            [_username isEqualToString:other.username]);
}

- (NSString *)usernameAndHostname {
    return [NSString stringWithFormat:@"%@@%@", _username, _hostname];
}

- (BOOL)isLocalhost {
    NSString *localHostName = [NSHost fullyQualifiedDomainName];
    DLog(@"localHostName=%@, VT100RemoteHost.hostname=%@", localHostName, self.hostname);
    if ([self.hostname isEqualToString:localHostName]) {
        return YES;
    }
    return [localHostName isEqualToString:self.hostname];
}

- (BOOL)isRemoteHost {
    return !self.isLocalhost;
}

#pragma mark - IntervalTreeObject

- (NSDictionary *)dictionaryValue {
    NSDictionary *dict =
        @{ kRemoteHostHostNameKey: _hostname ?: [NSNull null],
           kRemoteHostUserNameKey: _username ?: [NSNull null] };
    return [dict dictionaryByRemovingNullValues];
}

- (instancetype)copyOfIntervalTreeObject {
    VT100RemoteHost *copy = [[VT100RemoteHost alloc] initWithUsername:self.username hostname:self.hostname];
    return copy;
}

- (NSString *)shortDebugDescription {
    return [NSString stringWithFormat:@"[RemoteHost %@@%@]", _username, _hostname];
}

- (id<IntervalTreeObject>)doppelganger {
    @synchronized ([VT100RemoteHost class]) {
        assert(!_isDoppelganger);
        if (!_doppelganger) {
            _doppelganger = [self copyOfIntervalTreeObject];
            _doppelganger->_isDoppelganger = YES;
            _doppelganger->_progenitor = self;
        }
        return _doppelganger;
    }
}

- (id<IntervalTreeObject>)progenitor {
    @synchronized ([VT100RemoteHost class]) {
        return _progenitor;
    }
}

@end
