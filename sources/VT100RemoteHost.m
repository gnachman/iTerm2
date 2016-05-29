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
#import "NSObject+iTerm.h"

static NSString *const kRemoteHostHostNameKey = @"Host name";
static NSString *const kRemoteHostUserNameKey = @"User name";

// Protected by @synchronized([VT100RemoteHost class])
static NSString *gLocalHostName;

@implementation VT100RemoteHost
@synthesize entry;

+ (NSString *)localHostName {
    @synchronized (self) {
        return gLocalHostName;
    }
}

+ (void)initialize {
    NSPipe *pipe = [NSPipe pipe];
    if (!pipe) {
        return;
    }

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/hostname";
    task.arguments = @[ @"-f" ];
    task.standardOutput = pipe;
    @try {
        [task launch];
    }
    @catch (NSException *exception) {
        NSLog(@"Failed to launch “hostname -f”: %@", exception);
        return;
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [task waitUntilExit];
        DLog(@"hostname -f finished with status %d", task.terminationStatus);
        if (task.terminationStatus == 0) {
            NSPipe *pipe = task.standardOutput;
            NSFileHandle *fileHandle = pipe.fileHandleForReading;
            NSData *data = [fileHandle readDataToEndOfFile];
            NSString *name = [[[NSString alloc] initWithData:data
                                                    encoding:NSUTF8StringEncoding] autorelease];
            @synchronized(self) {
                gLocalHostName = [[name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
            }
        }
        [task release];
    });
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        self.hostname = dict[kRemoteHostHostNameKey];
        self.username = dict[kRemoteHostUserNameKey];
    }
    return self;
}

- (void)dealloc {   
    [_hostname release];
    [_username release];
    [super dealloc];
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
    if ([self.hostname isEqualToString:@"localhost"]) {
        return YES;
    }
    return [[VT100RemoteHost localHostName] isEqualToString:self.hostname];
}

#pragma mark - IntervalTreeObject

- (NSDictionary *)dictionaryValue {
    NSDictionary *dict =
        @{ kRemoteHostHostNameKey: _hostname ?: [NSNull null],
           kRemoteHostUserNameKey: _username ?: [NSNull null] };
    return [dict dictionaryByRemovingNullValues];
}

@end
