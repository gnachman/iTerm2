//
//  iTermProcessInspector.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/11/18.
//

#import "iTermProcessInspector.h"

#import "DebugLogging.h"
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

static NSString *const iTermProcessInspectorSavedAccessSettings = @"iTermProcessInspectorSavedAccessSettings";
NSString *const iTermAPIServerAuthorizationKey = @"iTermAPIServerAuthorizationKey";
static NSString *const kAPIAccessAllowed = @"allowed";
static NSString *const kAPIAccessDate = @"date";
static NSString *const kAPINextConfirmationDate = @"next confirmation";
static NSString *const kAPIAccessLocalizedName = @"app name";

@interface iTermIndividualProcessInspector : NSObject

@property (nonatomic, readonly) NSString *humanReadableName;
@property (nonatomic, readonly) NSString *reason;
@property (nonatomic, readonly) BOOL identified;
@property (nonatomic, readonly) pid_t pid;

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

@implementation iTermIndividualProcessInspector {
    iTermPythonProcessAnalyzer *_analyzer;
}

- (instancetype)initWithProcessID:(pid_t)pid {
    self = [super init];
    if (self) {
        _pid = pid;
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
                break;

            case iTermPythonProcessAnalyzerResultNotPython:
                _humanReadableName = _analyzer.execName.lastPathComponent;
                break;

            case iTermPythonProcessAnalyzerResultPython: {
                NSArray<NSString *> *idParts = [self pythonIdentifierArrayWithArgParser:_analyzer.argumentParser];

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

                if (idParts.count > 1) {
                    _humanReadableName = [[idParts subarrayFromIndex:1] componentsJoinedByString:@" "];
                } else {
                    _humanReadableName = [idParts[0] lastPathComponent];
                }
                break;
            }
        }
    }
    return self;
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

@end


@implementation iTermProcessInspector {
    NSArray<iTermIndividualProcessInspector *> *_requests;
}

- (instancetype)initWithProcessIDs:(NSArray<NSNumber *> *)pids {
    self = [super init];
    if (self) {
        _humanReadableName = @"Unknown";
        for (NSNumber *pid in pids) {
            _humanReadableName = [NSString stringWithFormat:@"Process %@", pid];
            iTermIndividualProcessInspector *inspector = [[iTermIndividualProcessInspector alloc] initWithProcessID:(pid_t)pid.integerValue];
            if (inspector.identified) {
                _humanReadableName = inspector.humanReadableName;
                break;
            }
        }
    }
    return self;
}

@end
