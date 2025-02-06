//
//  iTermLoggingHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/4/19.
//

#import "iTermLoggingHelper.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermNotificationController.h"
#import "iTermVariableScope+Session.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSDate+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "PreferencePanel.h"

NSString *const iTermLoggingHelperErrorNotificationName = @"SessionLogWriteFailed";
NSString *const iTermLoggingHelperErrorNotificationGUIDKey = @"guid";

@implementation iTermAsciicastMetadata

- (instancetype)initWithWidth:(int)width
                       height:(int)height
                      command:(NSString *)command
                        title:(NSString *)title
                  environment:(NSDictionary *)environment
                           fg:(NSColor *)fg
                           bg:(NSColor *)bg
                         ansi:(NSArray<NSColor *> *)ansi {
    self = [super init];
    if (self) {
        _width = width;
        _height = height;
        _command = [command copy];
        _title = [title copy];
        _environment = [environment copy];
        _startTime = [NSDate it_timeSinceBoot];
        _fgString = [fg colorUsingColorSpace:[NSColorSpace sRGBColorSpace]].srgbHexString;
        _bgString = [bg colorUsingColorSpace:[NSColorSpace sRGBColorSpace]].srgbHexString;
        _paletteString = [[ansi mapWithBlock:^id _Nonnull(NSColor * _Nonnull color) {
            return [[color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]] srgbHexString];
        }] componentsJoinedByString:@":"];
    }
    return self;
}

@end
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
asciicastMetadata:(iTermAsciicastMetadata *)asciicastMetadata
         append:(nullable NSNumber *)append
         window:(nullable NSWindow *)window {
    if (path) {
        const BOOL ok =[[NSFileManager defaultManager] it_promptToCreateEnclosingDirectoryFor:path
                                                                                        title:@"Logging Folder Not Found"
                                                                                   identifier:@"LoggingFolder"
                                                                                       window:window];
        if (!ok) {
            return;
        }
    }
    const BOOL wasLoggingRaw = self.isLoggingRaw;
    const BOOL wasLoggingCooked = self.isLoggingCooked;
    _path = [path copy];
    _enabled = path != nil && enabled;
    _style = style;
    _appending = append ? append.boolValue : [iTermAdvancedSettingsModel autologAppends];

    if (_style == iTermLoggingStyleAsciicast) {
        assert(asciicastMetadata != nil);
        _asciicastMetadata = asciicastMetadata;
    }
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

// https://github.com/asciinema/asciinema/blob/develop/doc/asciicast-v2.md
- (void)queueWriteAsciicastPrologue {
    NSDictionary *payload = @{
        @"version": @2,
        @"width": @(_asciicastMetadata.width),
        @"height": @(_asciicastMetadata.height),
        @"timestamp": @(round([[NSDate date] timeIntervalSince1970])),
        @"idle_time_limit": @1,
        @"command": _asciicastMetadata.command,
        @"title": _asciicastMetadata.title,
        @"env": [_asciicastMetadata.environment filteredWithBlock:^BOOL(id key, id value) {
            return [@[@"SHELL", @"TERM"] containsObject:key];
        }],
        @"theme": @{
            @"fg": _asciicastMetadata.fgString,
            @"bg": _asciicastMetadata.bgString,
            @"palette": _asciicastMetadata.paletteString
        }
    };
    NSString *string = [[[NSJSONSerialization it_jsonStringForObject:payload] stringByReplacingOccurrencesOfString:@"\n" withString:@" "] stringByAppendingString:@"\n"];
    @try {
        [self.fileHandle writeData:[string dataUsingEncoding:NSUTF8StringEncoding]];
    } @catch (NSException *exception) {
        DLog(@"%@", exception);
    }
}

- (void)start {
    _scope.logFilename = self.path;
    dispatch_async(_queue, ^{
        [self queueStart];
    });
}

// Called on _queue
- (void)queueStart {
    [self.fileHandle closeFile];
    self.fileHandle = nil;
    self.fileHandle = [self newFileHandle];
    if (self.fileHandle) {
        self->_needsTimestamp = YES;
        switch (_style) {
            case iTermLoggingStyleAsciicast:
                [self queueWriteAsciicastPrologue];
                break;
            case iTermLoggingStyleRaw:
            case iTermLoggingStyleHTML:
            case iTermLoggingStylePlainText:
                break;
        }
    } else {
        self->_enabled = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[iTermNotificationController sharedInstance] postNotificationWithTitle:@"Couldn’t write to session log"
                                                                             detail:self.path
                                                           callbackNotificationName:iTermLoggingHelperErrorNotificationName
                                                       callbackNotificationUserInfo:@{ iTermLoggingHelperErrorNotificationGUIDKey: self->_profileGUID ?: @"" }];
        });
    }
}

- (BOOL)isLoggingRaw {
    switch (_style) {
        case iTermLoggingStyleRaw:
        case iTermLoggingStyleAsciicast:
            return _enabled;

        case iTermLoggingStylePlainText:
        case iTermLoggingStyleHTML:
            return NO;
    }
}

- (BOOL)isLoggingCooked {
    switch (_style) {
        case iTermLoggingStyleRaw:
        case iTermLoggingStyleAsciicast:
            return NO;

        case iTermLoggingStylePlainText:
        case iTermLoggingStyleHTML:
            return _enabled;
    }
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
        [self queueLogDataAndTimestampIfNeeded:data];
    });
}

// Called on _queue
- (void)queueLogDataAndTimestampIfNeeded:(NSData *)data {
    if (_needsTimestamp) {
        switch (_style) {
            case iTermLoggingStyleRaw:
            case iTermLoggingStyleAsciicast:
                break;
            case iTermLoggingStyleHTML:
            case iTermLoggingStylePlainText:
                _needsTimestamp = NO;
                [self queueLogTimestamp];
                break;
        }
    }
    [self queueLogData:data];
}

- (void)logWithoutTimestamp:(NSData *)data {
    dispatch_async(_queue, ^{
        [self queueLogData:data];
    });
}

// Called on _queue
- (void)queueLogData:(NSData *)data {
    switch(_style) {
        case iTermLoggingStyleRaw:
        case iTermLoggingStyleHTML:
        case iTermLoggingStylePlainText:
            [self queueWriteDataToFileHandle:data];
            break;
        case iTermLoggingStyleAsciicast:
            [self queueWriteDataToAsciicast:data];
            break;
    }
}

- (void)queueWriteDataToFileHandle:(NSData *)data {
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

- (void)queueWriteObjectToAsciicast:(NSArray *)object {
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:object
                                                       options:0
                                                         error:nil];
    [self queueWriteDataToFileHandle:jsonData];
    [self queueWriteDataToFileHandle:[NSData dataWithBytes:"\n" length:1]];
}

- (NSArray*)queueAsciicastObjectWithCommand:(NSString *)command argument:(NSString *)argument {
    const NSTimeInterval now = [NSDate it_timeSinceBoot];
    return @[ @(now - _asciicastMetadata.startTime), command, argument ];
}

- (void)queueWriteDataToAsciicast:(NSData *)data {
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: [NSString stringWithLongCharacter:0xfffd];
    [self queueWriteObjectToAsciicast:[self queueAsciicastObjectWithCommand:@"o" argument:string]];
}

- (void)queueLogSetSizeForAsciicast:(VT100GridSize)size {
    NSString *string = [NSString stringWithFormat:@"%@x%@", @(size.width), @(size.height)];
    [self queueWriteObjectToAsciicast:[self queueAsciicastObjectWithCommand:@"r" argument:string]];
}

- (void)logNewline:(NSData *)data {
    dispatch_async(_queue, ^{
        [self queueLogData:data ?: [NSData dataWithBytesNoCopy:"\n" length:1 freeWhenDone:NO]];
        self->_needsTimestamp = YES;
    });
}

- (void)logSetSize:(VT100GridSize)size {
    switch(_style) {
        case iTermLoggingStyleRaw:
        case iTermLoggingStyleHTML:
        case iTermLoggingStylePlainText:
            break;
        case iTermLoggingStyleAsciicast:
            dispatch_async(_queue, ^{
                [self queueLogSetSizeForAsciicast:size];
            });
            break;
    }
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
