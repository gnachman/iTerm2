//
//  iTermAPIAuthorizationController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/11/18.
//

#import "iTermAPIAuthorizationController.h"

#import "iTermLSOF.h"
#import "iTermPythonArgumentParser.h"
#import "NSArray+iTerm.h"
#import "NSStringITerm.h"

static NSString *const iTermAPIAuthorizationControllerSavedAccessSettings = @"iTermAPIAuthorizationControllerSavedAccessSettings";
NSString *const iTermAPIServerAuthorizationKey = @"iTermAPIServerAuthorizationKey";
NSString *const iTermAPIServerAuthorizationIsREPL = @"iTermAPIServerAuthorizationIsREPL";
static NSString *const kAPIAccessAllowed = @"allowed";
static NSString *const kAPIAccessDate = @"date";
static NSString *const kAPINextConfirmationDate = @"next confirmation";
static NSString *const kAPIAccessLocalizedName = @"app name";

@interface iTermAPIAuthRequest : NSObject

@property (nonatomic, readonly) NSString *humanReadableName;
@property (nonatomic, readonly) NSString *fullCommandOrBundleID;
@property (nonatomic, readonly) NSString *keyForAuth;
@property (nonatomic, readonly) BOOL isRepl;
@property (nonatomic, readonly) NSString *reason;
@property (nonatomic, readonly) BOOL identified;
@property (nonatomic, readonly) id identity;

- (instancetype)initWithProcessID:(pid_t)pid NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@implementation iTermAPIAuthRequest

- (instancetype)initWithProcessID:(pid_t)pid {
    self = [super init];
    if (self) {
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        if (app.localizedName && app.bundleIdentifier) {
            _humanReadableName = [app.localizedName copy];
            _fullCommandOrBundleID = [app.bundleIdentifier copy];
            _keyForAuth = [_fullCommandOrBundleID copy];
        } else {
            NSString *execName = nil;
            _fullCommandOrBundleID = [[iTermLSOF commandForProcess:pid execName:&execName] copy];
            if (!execName || !_fullCommandOrBundleID) {
                _reason = [NSString stringWithFormat:@"Could not identify name for process with pid %d", (int)pid];
                return self;
            }

            NSArray<NSString *> *parts = [_fullCommandOrBundleID componentsInShellCommand];
            NSString *maybePython = parts.firstObject.lastPathComponent;

            if ([maybePython isEqualToString:@"python"] ||
                [maybePython isEqualToString:@"python3.6"] ||
                [maybePython isEqualToString:@"python3"] ||
                [maybePython isEqualToString:@"Python"]) {
                iTermPythonArgumentParser *pythonArgumentParser = [[iTermPythonArgumentParser alloc] initWithArgs:parts];
                NSArray<NSString *> *idParts = [self pythonIdentifierArrayWithArgParser:pythonArgumentParser];
                NSArray<NSString *> *escapedIdParts = [self pythonEscapedIdentifierArrayWithArgParser:pythonArgumentParser];

                _keyForAuth = [escapedIdParts componentsJoinedByString:@" "];
                _isRepl = pythonArgumentParser.repl;
                if (idParts.count > 1) {
                    _humanReadableName = [[idParts subarrayFromIndex:1] componentsJoinedByString:@" "];
                } else {
                    _humanReadableName = [idParts[0] lastPathComponent];
                }
            } else {
                _humanReadableName = execName.lastPathComponent;
                _keyForAuth = execName;
            }
        }
        _identified = YES;
    }
    return self;
}

- (id)identity {
    assert(_identified);
    return @{ iTermAPIServerAuthorizationKey: _keyForAuth,
              iTermAPIServerAuthorizationIsREPL: @(_isRepl) };
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

- (instancetype)initWithProcessID:(pid_t)pid {
    self = [super init];
    if (self) {
        _request = [[iTermAPIAuthRequest alloc] initWithProcessID:pid];
    }
    return self;
}

- (NSDictionary *)savedSettings {
    return [[NSUserDefaults standardUserDefaults] objectForKey:iTermAPIAuthorizationControllerSavedAccessSettings] ?: [NSDictionary dictionary];
}

- (NSString *)identificationFailureReason {
    if (_request.identified) {
        return nil;
    } else {
        return _request.reason;
    }
}

- (NSString *)key {
    return [NSString stringWithFormat:@"is_repl=%@,api_key=%@", @(_request.isRepl), _request.keyForAuth];
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
}

- (void)removeSetting {
    assert(_request.identified);
    NSMutableDictionary *settings = [[self savedSettings] mutableCopy];
    [settings removeObjectForKey:self.key];
    [[NSUserDefaults standardUserDefaults] setObject:settings forKey:iTermAPIAuthorizationControllerSavedAccessSettings];
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
