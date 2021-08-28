//
//  iTermLoggingHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/4/19.
//

#import "iTermLoggingHelper.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermNotificationController.h"
#import "iTermVariableScope+Session.h"
#import "PreferencePanel.h"

NSString *const iTermLoggingHelperErrorNotificationName = @"SessionLogWriteFailed";
NSString *const iTermLoggingHelperErrorNotificationGUIDKey = @"guid";

@interface iTermLoggingHelper()
@property (nullable, nonatomic, strong) NSFileHandle *fileHandle;
@end

@implementation iTermLoggingHelper {
    // File handle can only be accessed on this queue.
    dispatch_queue_t _queue;
    NSString *_profileGUID;
    BOOL _needsTimestamp;  // Access only on _queue.
}

+ (void)observeNotificationsWithHandler:(void (^)(NSString * _Nonnull))handler {
    [[NSNotificationCenter defaultCenter] addObserverForName:iTermLoggingHelperErrorNotificationName
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification * _Nonnull notification) {
        NSString *guid = notification.userInfo[iTermLoggingHelperErrorNotificationGUIDKey];
        if (!guid) {
            return;
        }
        handler(guid);
    }];
}

- (instancetype)initWithRawLogger:(id<iTermLogging>)rawLogger
                     cookedLogger:(id<iTermLogging>)cookedLogger
                      profileGUID:(NSString *)profileGUID
                            scope:(nonnull iTermVariableScope *)scope {
    self = [super init];
    if (self) {
        _path = nil;
        _enabled = NO;
        _style = iTermLoggingStyleRaw;
        _rawLogger = rawLogger;
        _cookedLogger = cookedLogger;
        _appending = [iTermAdvancedSettingsModel autologAppends];
        _queue = dispatch_queue_create("com.iterm2.logging", DISPATCH_QUEUE_SERIAL);
        _profileGUID = [profileGUID copy];
        _scope = scope;
    }
    return self;
}

- (void)setPath:(NSString *)path
        enabled:(BOOL)enabled
          style:(iTermLoggingStyle)style
         append:(nullable NSNumber *)append {
    const BOOL wasLoggingRaw = self.isLoggingRaw;
    const BOOL wasLoggingCooked = self.isLoggingCooked;

    _path = [path copy];
    _enabled = path != nil && enabled;
    _style = style;
    _appending = append ? append.boolValue : [iTermAdvancedSettingsModel autologAppends];

    if (wasLoggingRaw && !self.isLoggingRaw) {
        [_rawLogger loggingHelperStop:self];
        [self close];
    }
    if (wasLoggingCooked && !self.isLoggingCooked) {
        [_cookedLogger loggingHelperStop:self];
        [self close];
    }
    if (!wasLoggingRaw && self.isLoggingRaw) {
        [self start];
        [_rawLogger loggingHelperStart:self];
    }
    if (!wasLoggingCooked && self.isLoggingCooked) {
        [self start];
        [_cookedLogger loggingHelperStart:self];
    }
}

- (void)stop {
    if (self.isLoggingRaw) {
        [_rawLogger loggingHelperStop:self];
    }
    if (self.isLoggingCooked) {
        [_cookedLogger loggingHelperStop:self];
    }
    [self close];
    _enabled = NO;
}

- (void)close {
    _scope.logFilename = nil;
    dispatch_async(_queue, ^{
        [self.fileHandle closeFile];
        self.fileHandle = nil;
    });
}

- (void)start {
    _scope.logFilename = self.path;
    dispatch_async(_queue, ^{
        [self.fileHandle closeFile];
        self.fileHandle = nil;
        self.fileHandle = [self newFileHandle];
        if (self.fileHandle) {
            self->_needsTimestamp = YES;
        } else {
            self->_enabled = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                [[iTermNotificationController sharedInstance] postNotificationWithTitle:@"Couldn’t write to session log"
                                                                                 detail:self.path
                                                               callbackNotificationName:iTermLoggingHelperErrorNotificationName
                                                           callbackNotificationUserInfo:@{ iTermLoggingHelperErrorNotificationGUIDKey: self->_profileGUID ?: @"" }];
            });
        }
    });
}

- (BOOL)isLoggingRaw {
    return _enabled && _style == iTermLoggingStyleRaw;
}

- (BOOL)isLoggingCooked {
    return _enabled && _style != iTermLoggingStyleRaw;
}

- (NSFileHandle *)newFileHandle {
    NSString *path = [_path stringByStandardizingPath];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (handle == nil) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        [fileManager createFileAtPath:path contents:nil attributes:nil];
        handle = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    if (_appending) {
        [handle seekToEndOfFile];
    } else {
        [handle truncateFileAtOffset:0];
    }
    return handle;
}

- (void)logData:(NSData *)data {
    dispatch_async(_queue, ^{
        if (self->_style != iTermLoggingStyleRaw && self->_needsTimestamp) {
            self->_needsTimestamp = NO;
            [self queueLogTimestamp];
        }
        [self queueLogData:data];
    });
}

- (void)logWithoutTimestamp:(NSData *)data {
    dispatch_async(_queue, ^{
        [self queueLogData:data];
    });
}

// Called on _queue
- (void)queueLogData:(NSData *)data {
    NSFileHandle *fileHandle = self.fileHandle;
    @try {
        [fileHandle writeData:data];
    } @catch (NSException *exception) {
        DLog(@"Exception while logging %@ bytes of data: %@", @(data.length), exception);
        [self.fileHandle closeFile];
        self.fileHandle = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_enabled = NO;
        });
    }
}

- (void)logNewline:(NSData *)data {
    dispatch_async(_queue, ^{
        [self queueLogData:data ?: [NSData dataWithBytesNoCopy:"\n" length:1 freeWhenDone:NO]];
        self->_needsTimestamp = YES;
    });
}

// Called on _queue
- (void)queueLogTimestamp {
    NSString *string = [self.cookedLogger loggingHelperTimestamp:self];
    if (!string) {
        return;
    }
    [self queueLogData:[string dataUsingEncoding:NSUTF8StringEncoding]];
    _needsTimestamp = NO;
}

@end
