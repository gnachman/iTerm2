//
//  iTermAPIAuthorizationController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/11/18.
//

#import "iTermAPIAuthorizationController.h"

#import "iTermAdvancedSettingsModel.h"
#import "iTermLSOF.h"
#import "iTermNotificationCenter+Protected.h"
#import "iTermPythonArgumentParser.h"
#import "iTermScriptHistory.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSData+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSStringITerm.h"

static NSString *const iTermAPIAuthorizationControllerSavedAccessSettings = @"iTermAPIAuthorizationControllerSavedAccessSettings";
NSString *const iTermAPIServerAuthorizationKey = @"iTermAPIServerAuthorizationKey";
static NSString *const kAPIAccessAllowed = @"allowed";
static NSString *const kAPIAccessDate = @"date";
static NSString *const kAPINextConfirmationDate = @"next confirmation";
static NSString *const kAPIAccessLocalizedName = @"app name";

@interface iTermAPIAuthRequest : NSObject

@property (nonatomic, readonly) NSString *humanReadableName;
@property (nonatomic, readonly) NSString *fullCommandOrBundleID;
@property (nonatomic, readonly) NSString *keyForAuth;
@property (nonatomic, readonly) NSString *reason;
@property (nonatomic, readonly) BOOL identified;
@property (nonatomic, readonly) id identity;

- (instancetype)initWithProcessID:(pid_t)pid NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

typedef NS_ENUM(NSUInteger, iTermPythonProcessAnalyzerResult) {
    iTermPythonProcessAnalyzerResultCocoaApp,
    iTermPythonProcessAnalyzerResultUnidentifiable,
    iTermPythonProcessAnalyzerResultPython,
    iTermPythonProcessAnalyzerResultNotPython
};

@interface iTermPythonProcessAnalyzer : NSObject
@property (nonatomic, readonly) NSRunningApplication *app;
@property (nonatomic, readonly) iTermPythonArgumentParser *argumentParser;
@property (nonatomic, readonly) iTermPythonProcessAnalyzerResult result;
@property (nonatomic, readonly) NSString *fullCommandOrBundleID;
@property (nonatomic, readonly) NSString *execName;

+ (instancetype)forProcessID:(pid_t)pid;
@end

@implementation iTermPythonProcessAnalyzer

+ (instancetype)forProcessID:(pid_t)pid {
    return [[self alloc] initWithProcessID:pid];
}

- (instancetype)initWithProcessID:(pid_t)pid {
    self = [super init];
    if (self) {
        _app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];

        // Note: The org.python.python bundle is PyObjC's wrapper app. We can parse its arguments ok.
        if (_app.localizedName &&
            _app.bundleIdentifier &&
            ![_app.bundleIdentifier isEqualToString:@"org.python.python"]) {
            _fullCommandOrBundleID = _app.bundleIdentifier;
            _result = iTermPythonProcessAnalyzerResultCocoaApp;
            return self;
        }
        NSString *execName = nil;
        _fullCommandOrBundleID = [[iTermLSOF commandForProcess:pid execName:&execName] copy];
        _execName = execName;
        if (!_execName || !_fullCommandOrBundleID) {
            _result = iTermPythonProcessAnalyzerResultUnidentifiable;
            return self;
        }

        NSArray<NSString *> *parts = [_fullCommandOrBundleID componentsInShellCommand];
        NSString *maybePython = parts.firstObject.lastPathComponent;
        if (!maybePython) {
            _result = iTermPythonProcessAnalyzerResultNotPython;
            return nil;
        }

        NSArray<NSString *> *pythonNames = @[ @"python", @"python3.6", @"python3.7", @"python3", @"Python" ];
        if (![pythonNames containsObject:maybePython]) {
            _result = iTermPythonProcessAnalyzerResultNotPython;
            return self;
        }
        _argumentParser = [[iTermPythonArgumentParser alloc] initWithArgs:parts];
        _result = iTermPythonProcessAnalyzerResultPython;
    }
    return self;
}

@end

@implementation iTermAPIAuthRequest {
    iTermPythonProcessAnalyzer *_analyzer;
}

- (instancetype)initWithProcessID:(pid_t)pid {
    self = [super init];
    if (self) {
        _analyzer = [iTermPythonProcessAnalyzer forProcessID:pid];
        assert(_analyzer);
        _identified = (_analyzer.result != iTermPythonProcessAnalyzerResultUnidentifiable);

        // Compute the file ID, which gives a unique identifier to the executable. It combines the
        // file device ID, inode number, and hash of the binary. This makes it hard to keep the same
        // binary as the user has already approvide but make it do something different.
        NSString *fileId = nil;
        NSString *const executable = _analyzer.execName;
        if (executable) {
            NSError *error = nil;
            NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:executable
                                                                                        error:&error];
            NSNumber *deviceId = attributes[NSFileSystemNumber];
            NSNumber *inode = attributes[NSFileSystemFileNumber];
            if (error || !deviceId || !inode) {
                _reason = [NSString stringWithFormat:@"Could not stat %@: %@", _analyzer.fullCommandOrBundleID, error.localizedDescription];
                _identified = NO;
                return self;
            }
            NSData *data = [NSData dataWithContentsOfFile:executable];
            if (!data) {
                _reason = [NSString stringWithFormat:@"Could not read executable %@", executable];
                _identified = NO;
                return self;
            }
            fileId = [NSString stringWithFormat:@"%@:%@:%@", deviceId, inode, [[data it_sha256] it_hexEncoded]];
        }

        switch (_analyzer.result) {
            case iTermPythonProcessAnalyzerResultUnidentifiable:
                _reason = [NSString stringWithFormat:@"Could not identify name for process with pid %d", (int)pid];
                break;

            case iTermPythonProcessAnalyzerResultCocoaApp:
                _humanReadableName = [_analyzer.app.localizedName copy];
                _keyForAuth = [_analyzer.fullCommandOrBundleID copy];
                break;

            case iTermPythonProcessAnalyzerResultNotPython:
                _humanReadableName = _analyzer.execName.lastPathComponent;
                _keyForAuth = _analyzer.execName;
                break;

            case iTermPythonProcessAnalyzerResultPython: {
                NSArray<NSString *> *idParts = [self pythonIdentifierArrayWithArgParser:_analyzer.argumentParser];
                NSArray<NSString *> *escapedIdParts = [self pythonEscapedIdentifierArrayWithArgParser:_analyzer.argumentParser];

                NSString *executable = _analyzer.execName;
                NSError *error = nil;
                NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:executable
                                                                                            error:&error];
                NSNumber *deviceId = attributes[NSFileSystemNumber];
                NSNumber *inode = attributes[NSFileSystemFileNumber];
                if (error || !deviceId || !inode) {
                    _reason = [NSString stringWithFormat:@"Could not stat %@: %@", _analyzer.fullCommandOrBundleID, error.localizedDescription];
                    _identified = NO;
                    break;
                }

                _keyForAuth = [escapedIdParts componentsJoinedByString:@" "];
                if (idParts.count > 1) {
                    _humanReadableName = [[idParts subarrayFromIndex:1] componentsJoinedByString:@" "];
                } else {
                    _humanReadableName = [idParts[0] lastPathComponent];
                }
                break;
            }
        }
        _keyForAuth = [NSString stringWithFormat:@"%@:%@", fileId, _keyForAuth];
    }
    return self;
}

- (NSString *)fullCommandOrBundleID {
    return _analyzer.fullCommandOrBundleID;
}

- (id)identity {
    assert(_identified);
    return @{ iTermAPIServerAuthorizationKey: _keyForAuth };
}

- (NSArray<NSString *> *)pythonIdentifierArrayWithArgParser:(iTermPythonArgumentParser *)pythonArgumentParser {
    if (pythonArgumentParser.repl) {
        return @[ @"iTerm2 Python REPL" ];
    }
    NSMutableArray *idParts = [NSMutableArray array];
    [idParts addObject:pythonArgumentParser.fullPythonPath];
    if (pythonArgumentParser.module) {
        [idParts addObject:@"-m"];
        [idParts addObject:pythonArgumentParser.module];
    }
    if (pythonArgumentParser.statement) {
        [idParts addObject:@"-c"];
        [idParts addObject:pythonArgumentParser.statement];
    }
    if (pythonArgumentParser.script) {
        [idParts addObject:pythonArgumentParser.script.lastPathComponent];
    }
    return idParts;
}

- (NSArray<NSString *> *)pythonEscapedIdentifierArrayWithArgParser:(iTermPythonArgumentParser *)pythonArgumentParser {
    NSMutableArray *idParts = [NSMutableArray array];
    [idParts addObject:pythonArgumentParser.escapedFullPythonPath];
    if (pythonArgumentParser.module) {
        [idParts addObject:@"-m"];
        [idParts addObject:pythonArgumentParser.escapedModule];
    }
    if (pythonArgumentParser.statement) {
        [idParts addObject:@"-c"];
        [idParts addObject:pythonArgumentParser.escapedStatement];
    }
    if (pythonArgumentParser.script) {
        [idParts addObject:pythonArgumentParser.escapedScript];
    }
    return idParts;
}

@end


@implementation iTermAPIAuthorizationController {
    iTermAPIAuthRequest *_request;
}

+ (void)resetPermissions {
    if ([iTermWarning showWarningWithTitle:@"This will remove all explicitly allowed and denied programs, and you will be prompted again for each when they attempt to connect in the future."
                                   actions:@[ @"OK", @"Cancel" ]
                                 accessory:nil
                                identifier:@"NoSyncResetAPIPermissions"
                               silenceable:kiTermWarningTypePersistent
                                   heading:@"Reset API Permissions?"
                                    window:nil] == kiTermWarningSelection0) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:iTermAPIAuthorizationControllerSavedAccessSettings];
        [[iTermAPIAuthorizationDidChange notification] post];
    }
}

- (instancetype)initWithProcessID:(pid_t)pid {
    self = [super init];
    if (self) {
        _request = [[iTermAPIAuthRequest alloc] initWithProcessID:pid];
    }
    return self;
}

- (NSDictionary *)savedSettings {
    return [self.class savedSettings];
}

+ (NSDictionary *)savedSettings {
    return [[NSUserDefaults standardUserDefaults] objectForKey:iTermAPIAuthorizationControllerSavedAccessSettings] ?: [NSDictionary dictionary];
}

+ (NSDictionary<NSString *, NSString *> *)keyToHumanReadableNameForAllowedPrograms {
    return [[self savedSettings] mapValuesWithBlock:^id(id key, NSDictionary *dict) {
        return dict[kAPIAccessLocalizedName];
    }];
}

+ (void)resetAccessForKey:(NSString *)key {
    NSMutableDictionary *settings = [[self savedSettings] mutableCopy];
    [settings removeObjectForKey:key];
    [[NSUserDefaults standardUserDefaults] setObject:settings forKey:iTermAPIAuthorizationControllerSavedAccessSettings];
    [[iTermAPIAuthorizationDidChange notification] post];
}

- (NSString *)identificationFailureReason {
    if (_request.identified) {
        return nil;
    } else {
        return _request.reason;
    }
}

+ (BOOL)settingForKey:(NSString *)key {
    return [[[[self savedSettings] objectForKey:key] objectForKey:kAPIAccessAllowed] boolValue];
}

- (NSString *)key {
    return [NSString stringWithFormat:@"api_key=%@", _request.keyForAuth];
}

- (id)identity {
    assert(_request.identified);
    return _request.identity;
}

- (BOOL)identified {
    return _request.identified;
}

- (NSDictionary *)savedState {
    assert(_request.identified);
    NSDictionary *savedSettings = [self savedSettings];
    return savedSettings[self.key];
}

- (iTermAPIAuthorizationSetting)setting {
    assert(_request.identified);
    NSDictionary *savedState = self.savedState;
    if (!savedState) {
        return iTermAPIAuthorizationSettingUnknown;
    }

    if (![savedState[kAPIAccessAllowed] boolValue]) {
        return iTermAPIAuthorizationSettingPermanentlyDenied;
    }

    NSString *name = savedState[kAPIAccessLocalizedName];
    if ([_request.humanReadableName isEqualToString:name]) {
        // Access is permanently allowed and the display name is unchanged. Do we need to reauth?

        NSDate *confirm = savedState[kAPINextConfirmationDate];
        if ([[NSDate date] compare:confirm] == NSOrderedAscending) {
            return iTermAPIAuthorizationSettingRecentConsent;
        }

        return iTermAPIAuthorizationSettingExpiredConsent;
    }

    return iTermAPIAuthorizationSettingUnknown;
}

- (void)setAllowed:(BOOL)allow {
    assert(_request.identified);
    NSMutableDictionary *settings = [[self savedSettings] mutableCopy];
    static const NSTimeInterval oneMonthInSeconds = 30 * 24 * 60 * 60;
    settings[self.key] = @{ kAPIAccessAllowed: @(allow),
                            kAPIAccessDate: [NSDate date],
                            kAPINextConfirmationDate: [[NSDate date] dateByAddingTimeInterval:oneMonthInSeconds],
                            kAPIAccessLocalizedName: _request.humanReadableName };
    [[NSUserDefaults standardUserDefaults] setObject:settings forKey:iTermAPIAuthorizationControllerSavedAccessSettings];
    [[iTermAPIAuthorizationDidChange notification] post];
}

- (void)removeSetting {
    assert(_request.identified);
    NSMutableDictionary *settings = [[self savedSettings] mutableCopy];
    [settings removeObjectForKey:self.key];
    [[NSUserDefaults standardUserDefaults] setObject:settings forKey:iTermAPIAuthorizationControllerSavedAccessSettings];
    [[iTermAPIAuthorizationDidChange notification] post];
}

- (NSString *)humanReadableName {
    assert(_request.identified);
    return _request.humanReadableName;
}

- (NSString *)fullCommandOrBundleID {
    assert(_request.identified);
    return _request.fullCommandOrBundleID;
}

@end

@implementation iTermAPIAuthorizationDidChange

+ (instancetype)notification {
    return [[self alloc] initPrivate];
}

+ (void)subscribe:(NSObject *)owner block:(void (^)(iTermBaseNotification * _Nonnull))block {
    [self internalSubscribe:owner withBlock:block];
}

@end
