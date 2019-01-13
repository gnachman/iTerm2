//
//  iTermAPIScriptLauncher.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/19/18.
//

#import "iTermAPIScriptLauncher.h"

#import "DebugLogging.h"
#import "iTermAPIConnectionIdentifierController.h"
#import "iTermAPIHelper.h"
#import "iTermNotificationController.h"
#import "iTermOptionalComponentDownloadWindowController.h"
#import "iTermPythonRuntimeDownloader.h"
#import "iTermScriptConsole.h"
#import "iTermScriptHistory.h"
#import "iTermSetupPyParser.h"
#import "iTermWebSocketCookieJar.h"
#import "NSArray+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "NSWorkspace+iTerm.h"
#import "PTYTask.h"

@import Sparkle;

@implementation iTermAPIScriptLauncher

+ (void)launchScript:(NSString *)filename {
    [self launchScript:filename fullPath:filename withVirtualEnv:nil setupPyPath:nil];
}

+ (NSString *)pythonVersionForScript:(NSString *)path {
    NSString *setupPyPath = [path stringByAppendingPathComponent:@"setup.py"];
    iTermSetupPyParser *parser = [[iTermSetupPyParser alloc] initWithPath:setupPyPath];
    if (parser) {
        return parser.pythonVersion;
    } else {
        return [self inferredPythonVersionFromScriptAt:path];
    }
}

+ (void)launchScript:(NSString *)filename
            fullPath:(NSString *)fullPath
      withVirtualEnv:(NSString *)virtualenv
         setupPyPath:(NSString *)setupPyPath {
    if (virtualenv != nil) {
        iTermSetupPyParser *parser = [[iTermSetupPyParser alloc] initWithPath:setupPyPath];
        NSString *pythonVersion = parser.pythonVersion;
        // Launching a full environment script: do not check for a newer version, as it is frozen and
        // downloading wouldn't affect it anyway.
        [self reallyLaunchScript:filename
                        fullPath:fullPath
                  withVirtualEnv:virtualenv
                   pythonVersion:pythonVersion];
        return;
    }

    NSString *pythonVersion = [self inferredPythonVersionFromScriptAt:filename];
    [[iTermPythonRuntimeDownloader sharedInstance] downloadOptionalComponentsIfNeededWithConfirmation:YES
                                                                                        pythonVersion:pythonVersion
                                                                                       withCompletion:^(BOOL ok) {
        if (ok) {
            [self reallyLaunchScript:filename
                            fullPath:fullPath
                      withVirtualEnv:virtualenv
                       pythonVersion:pythonVersion];
        }
    }];
}

// Takes a file starting with:
// #!/usr/bin/env python3.7
// and returns "3.7", or nil if it was malformed.
+ (NSString *)inferredPythonVersionFromScriptAt:(NSString *)path {
    FILE *file = fopen(path.UTF8String, "r");
    if (!file) {
        return nil;
    }
    size_t length;
    char *byteArray = fgetln(file, &length);
    if (length == 0 || byteArray == NULL) {
        fclose(file);
        return nil;
    }
    NSData *data = [NSData dataWithBytes:byteArray length:length];
    fclose(file);
    NSString *line = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSString *const expectedPrefix = @"#!/usr/bin/env python";
    if (![line hasPrefix:expectedPrefix]) {
        return nil;
    }
    NSString *candidate = [[line substringFromIndex:expectedPrefix.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];;
    if (candidate.length == 0) {
        return nil;
    }

    NSArray<NSString *> *parts = [candidate componentsSeparatedByString:@"."];
    const BOOL allNumeric = [parts allWithBlock:^BOOL(NSString *anObject) {
        return [anObject isNumeric];
    }];
    if (!allNumeric) {
        return nil;
    }

    if (parts.count < 2) {
        return nil;
    }

    return candidate;
}

+ (void)reallyLaunchScript:(NSString *)filename
                  fullPath:(NSString *)fullPath
            withVirtualEnv:(NSString *)virtualenv
             pythonVersion:(NSString *)pythonVersion {
    if (![iTermAPIHelper sharedInstance]) {
        return;
    }

    NSString *key = [[NSUUID UUID] UUIDString];
    NSString *name = [[filename lastPathComponent] stringByDeletingPathExtension];
    if (virtualenv) {
        // Convert /foo/bar/Name/Name/main.py to Name
        name = [[[filename stringByDeletingLastPathComponent] pathComponents] lastObject];
    }
    NSString *identifier = [[iTermAPIConnectionIdentifierController sharedInstance] identifierForKey:key];
    iTermScriptHistoryEntry *entry = [[iTermScriptHistoryEntry alloc] initWithName:name
                                                                          fullPath:fullPath
                                                                        identifier:identifier
                                                                          relaunch:
                                      ^{
                                          [iTermAPIScriptLauncher reallyLaunchScript:filename
                                                                            fullPath:fullPath
                                                                      withVirtualEnv:virtualenv
                                                                       pythonVersion:pythonVersion];
                                      }];
    entry.path = filename;
    [[iTermScriptHistory sharedInstance] addHistoryEntry:entry];

    @try {
        [self tryLaunchScript:filename historyEntry:entry key:key withVirtualEnv:virtualenv pythonVersion:pythonVersion];
    }
    @catch (NSException *e) {
        [[iTermScriptHistory sharedInstance] addHistoryEntry:entry];
        [entry addOutput:[NSString stringWithFormat:@"ERROR: Failed to launch: %@", e.reason]];
        [self didFailToLaunchScript:filename withException:e];
    }
}

// THROWS
+ (void)tryLaunchScript:(NSString *)filename
           historyEntry:(iTermScriptHistoryEntry *)entry
                    key:(NSString *)key
         withVirtualEnv:(NSString *)virtualenv
          pythonVersion:(NSString *)pythonVersion {
    NSTask *task = [[NSTask alloc] init];
    NSString *shell = [PTYTask userShell];

    task.launchPath = shell;
    task.arguments = [self argumentsToRunScript:filename withVirtualEnv:virtualenv pythonVersion:pythonVersion];
    NSString *cookie = [[iTermWebSocketCookieJar sharedInstance] newCookie];
    task.environment = [self environmentFromEnvironment:task.environment shell:shell cookie:cookie key:key];

    NSPipe *pipe = [[NSPipe alloc] init];
    [task setStandardOutput:pipe];
    [task setStandardError:pipe];

    [entry addOutput:[NSString stringWithFormat:@"%@ %@\n", task.launchPath, [task.arguments componentsJoinedByString:@" "]]];
    [task launch];   // This can throw
    entry.pid = task.processIdentifier;
    [self waitForTask:task readFromPipe:pipe historyEntry:entry];
}

+ (NSDictionary *)environmentFromEnvironment:(NSDictionary *)initialEnvironment
                                       shell:(NSString *)shell
                                      cookie:(NSString *)cookie
                                         key:(NSString *)key {
    NSMutableDictionary *environment = [initialEnvironment ?: @{} mutableCopy];

    environment[@"ITERM2_COOKIE"] = cookie;
    environment[@"ITERM2_KEY"] = key;
    environment[@"HOME"] = NSHomeDirectory();
    environment[@"SHELL"] = shell;
    environment[@"PYTHONIOENCODING"] = @"utf-8";
    return environment;
}

+ (NSArray *)argumentsToRunScript:(NSString *)filename
                   withVirtualEnv:(NSString *)providedVirtualEnv
                    pythonVersion:(NSString *)pythonVersion {
    NSString *wrapper = [[NSBundle bundleForClass:self.class] pathForResource:@"it2_api_wrapper" ofType:@"sh"];
    NSString *pyenv = [[iTermPythonRuntimeDownloader sharedInstance] pathToStandardPyenvPythonWithPythonVersion:pythonVersion];
    NSString *virtualEnv = providedVirtualEnv ?: pyenv;
    NSString *command = [NSString stringWithFormat:@"%@ %@ %@",
                         [wrapper stringWithEscapedShellCharactersExceptTabAndNewline],
                         [virtualEnv stringWithEscapedShellCharactersExceptTabAndNewline],
                         [filename stringWithEscapedShellCharactersExceptTabAndNewline]];
    return @[ @"-c", command ];
}

+ (void)waitForTask:(NSTask *)task readFromPipe:(NSPipe *)pipe historyEntry:(iTermScriptHistoryEntry *)entry {
    static NSMutableArray<dispatch_queue_t> *queues;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queues = [NSMutableArray array];
    });
    dispatch_queue_t q = dispatch_queue_create("com.iterm2.script-launcher", NULL);
    [queues addObject:q];
    dispatch_async(q, ^{
        NSFileHandle *readHandle = [pipe fileHandleForReading];
        NSData *inData = [readHandle availableData];
        while (inData.length) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [entry addOutput:[[NSString alloc] initWithData:inData encoding:NSUTF8StringEncoding]];
            });
            inData = [readHandle availableData];
        }

        [task waitUntilExit];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!task.isRunning && (task.terminationReason == NSTaskTerminationReasonUncaughtSignal || task.terminationStatus != 0)) {
                if (task.terminationReason == NSTaskTerminationReasonUncaughtSignal) {
                    [entry addOutput:@"\n** Script was killed by a signal **"];
                } else {
                    [entry addOutput:[NSString stringWithFormat:@"\n** Script exited with status %@ **", @(task.terminationStatus)]];
                }
                if (!entry.terminatedByUser) {
                    NSString *message = [NSString stringWithFormat:@"Script “%@” failed.", entry.name];
                    [[iTermNotificationController sharedInstance] notify:message];
                }
            }
            [entry stopRunning];
        });
        [queues removeObject:q];
    });
}

+ (void)didFailToLaunchScript:(NSString *)filename withException:(NSException *)e {
    ELog(@"Exception occurred %@", e);
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Error running script";
    alert.informativeText = [NSString stringWithFormat:@"Script at \"%@\" failed.\n\n%@",
                             filename, e.reason];
    [alert runModal];
}

+ (NSString *)prospectivePythonPathForPyenvScriptNamed:(NSString *)name {
    NSArray<NSString *> *components = @[ name, @"iterm2env", @"versions" ];
    NSString *path = [[NSFileManager defaultManager] scriptsPathWithoutSpaces];
    for (NSString *part in components) {
        path = [path stringByAppendingPathComponent:part];
    }
    NSString *pythonVersion = [iTermPythonRuntimeDownloader bestPythonVersionAt:path] ?: @"_NO_PYTHON_VERSION_FOUND_";
    components = @[ pythonVersion, @"bin", @"python3" ];
    for (NSString *part in components) {
        path = [path stringByAppendingPathComponent:part];
    }

    return path;
}

+ (NSString *)environmentForScript:(NSString *)path checkForMain:(BOOL)checkForMain {
    if (checkForMain) {
        NSString *name = path.lastPathComponent;
        // If path is foo/bar then look for foo/bar/bar/bar.py
        NSString *expectedPath = [[path stringByAppendingPathComponent:name] stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"py"]];
        if (![[NSFileManager defaultManager] fileExistsAtPath:expectedPath isDirectory:nil]) {
            return nil;
        }
    }

    // Does it have an pyenv?
    // foo/bar/iterm2env
    NSString *pyenvPython = [[iTermPythonRuntimeDownloader sharedInstance] pyenvAt:[path stringByAppendingPathComponent:@"iterm2env"]
                                                                     pythonVersion:[iTermAPIScriptLauncher pythonVersionForScript:path]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:pyenvPython isDirectory:nil]) {
        return pyenvPython;
    }

    return nil;
}

@end

