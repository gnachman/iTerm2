//
//  iTermAPIScriptLauncher.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/19/18.
//

#import "iTermAPIScriptLauncher.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAPIConnectionIdentifierController.h"
#import "iTermAPIHelper.h"
#import "iTermController.h"
#import "iTermNotificationController.h"
#import "iTermOpenDirectory.h"
#import "iTermOptionalComponentDownloadWindowController.h"
#import "iTermPythonRuntimeDownloader.h"
#import "iTermScriptConsole.h"
#import "iTermScriptHistory.h"
#import "iTermSetupCfgParser.h"
#import "iTermWarning.h"
#import "iTermWebSocketCookieJar.h"
#import "NSArray+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "NSWorkspace+iTerm.h"
#import "PTYTask.h"

static NSString *const iTermAPIScriptLauncherScriptDidFailUserNotificationCallbackNotification = @"iTermAPIScriptLauncherScriptDidFailUserNotificationCallbackNotification";

@implementation iTermAPIScriptLauncher

+ (void)launchScript:(NSString *)filename
           arguments:(NSArray<NSString *> *)arguments
  explicitUserAction:(BOOL)explicitUserAction {
    [self launchScript:filename
              fullPath:filename
             arguments:arguments
        withVirtualEnv:nil
          setupCfgPath:nil
    explicitUserAction:explicitUserAction];
}

+ (NSString *)pythonVersionForScript:(NSString *)path {
    NSString *setupCfgPath = [path stringByAppendingPathComponent:@"setup.cfg"];
    iTermSetupCfgParser *parser = [[iTermSetupCfgParser alloc] initWithPath:setupCfgPath];
    if (parser) {
        return parser.pythonVersion;
    } else {
        return [self inferredPythonVersionFromScriptAt:path];
    }
}

+ (int)environmentVersionAt:(NSString *)iterm2env {
    NSString *manifest = [iterm2env stringByAppendingPathComponent:@"iterm2env-metadata.json"];
    return [[iTermPythonRuntimeDownloader sharedInstance] versionInMetadataAtURL:[NSURL fileURLWithPath:manifest]];
}

+ (void)upgradeFullEnvironmentScriptAt:(NSString *)fullPath
                          configParser:(iTermSetupCfgParser *)configParser
                            completion:(void (^)(NSString *))completion {
    NSString *message = [NSString stringWithFormat:@"The Python API script “%@” needs a newer version of the runtime environment for security reasons. You must upgrade it before this version of iTerm2 can launch the script.", fullPath.lastPathComponent];
    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:message
                               actions:@[ @"Upgrade", @"Cancel" ]
                             accessory:nil
                            identifier:@"UpgradeFullEnvironmentScript"
                           silenceable:kiTermWarningTypePersistent
                               heading:@"Upgrade Python Runtime?"
                                window:nil];
    switch (selection) {
        case kiTermWarningSelection0:
            [self downloadIfNeededAndUpgradeFullEnvironmentScriptAt:fullPath
                                                       configParser:configParser
                                                         completion:completion];
            break;

        default:
            break;
    }
}

+ (void)downloadIfNeededAndUpgradeFullEnvironmentScriptAt:(NSString *)fullPath
                                             configParser:(iTermSetupCfgParser *)configParser
                                               completion:(void (^)(NSString *))completion {
    iTermPythonRuntimeDownloader *downloader = [iTermPythonRuntimeDownloader sharedInstance];
    if ([downloader installedVersionWithPythonVersion:configParser.pythonVersion] >= iTermMinimumPythonEnvironmentVersion) {
        [self reallyUpgradeFullEnvironmentScriptAt:fullPath
                                      configParser:configParser
                                        completion:completion];
        return;
    }

    [downloader downloadOptionalComponentsIfNeededWithConfirmation:YES
                                                                                        pythonVersion:nil
                                                                            minimumEnvironmentVersion:0
                                                                                   requiredToContinue:YES
                                                                                       withCompletion:
     ^(iTermPythonRuntimeDownloaderStatus status) {
         switch (status) {
             case iTermPythonRuntimeDownloaderStatusNotNeeded:
             case iTermPythonRuntimeDownloaderStatusDownloaded:
                 [self reallyUpgradeFullEnvironmentScriptAt:fullPath
                                               configParser:configParser
                                                 completion:completion];
                 break;
             case iTermPythonRuntimeDownloaderStatusError:
             case iTermPythonRuntimeDownloaderStatusUnknown:
             case iTermPythonRuntimeDownloaderStatusWorking:
             case iTermPythonRuntimeDownloaderStatusCanceledByUser:
             case iTermPythonRuntimeDownloaderStatusRequestedVersionNotFound:
                 break;
        }
    }];
}

+ (void)reallyUpgradeFullEnvironmentScriptAt:(NSString *)fullPath
                                configParser:(iTermSetupCfgParser *)configParser
                                  completion:(void (^)(NSString *))completion {
    NSURL *url = [NSURL fileURLWithPath:fullPath];
    NSURL *existingEnv = [url URLByAppendingPathComponent:@"iterm2env"];
    NSURL *savedEnv = [url URLByAppendingPathComponent:@"saved-iterm2env"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:existingEnv.path]) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:savedEnv.path]) {
            NSError *error = nil;
            [[NSFileManager defaultManager] removeItemAtURL:existingEnv error:&error];
            DLog(@"remove broken %@: %@", existingEnv.path, error);
        } else {
            NSError *error = nil;
            [[NSFileManager defaultManager] moveItemAtURL:existingEnv toURL:savedEnv error:&error];
            DLog(@"saving - move '%@' to '%@': %@", existingEnv.path, savedEnv.path, error);
        }
    }
    [[iTermPythonRuntimeDownloader sharedInstance] installPythonEnvironmentTo:url
                                                                 dependencies:configParser.dependencies
                                                                pythonVersion:configParser.pythonVersion
                                                                   completion:^(BOOL ok) {
        if (ok) {
            NSError *error = nil;
            [[NSFileManager defaultManager] removeItemAtURL:savedEnv error:&error];
            DLog(@"remove saved - %@: %@", savedEnv.path, error);
            NSString *venv = [self environmentForScript:fullPath checkForMain:YES checkForSaved:NO];
            completion(venv);
            return;
        }

        NSError *error = nil;
        [[NSFileManager defaultManager] removeItemAtURL:existingEnv error:&error];
        DLog(@"remove failed install - %@: %@", existingEnv.path, error);

        error = nil;
        [[NSFileManager defaultManager] moveItemAtURL:savedEnv toURL:existingEnv error:&error];
        DLog(@"restore saved - move '%@' to '%@': %@", savedEnv.path, existingEnv.path, error);
    }];
}

+ (void)upgradeIfNeededFullEnvironmentScriptAt:(NSString *)fullPath
                                  configParser:(iTermSetupCfgParser *)configParser
                                    virtualEnv:(NSString *)originalVirtualenv
                                    completion:(void (^)(NSString *))completion {
    NSString *virtualenv = originalVirtualenv;
    NSString *iterm2env = [fullPath stringByAppendingPathComponent:@"iterm2env"];
    NSString *saved = [fullPath stringByAppendingPathComponent:@"saved-iterm2env"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:saved]) {
        // If there's a saved folder, then something went wrong while upgrading. Restore it.
        NSError *error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:iterm2env
                                                   error:&error];
        DLog(@"Remove unfinished %@: %@", iterm2env, error);

        [[NSFileManager defaultManager] moveItemAtPath:saved
                                                toPath:iterm2env
                                                 error:&error];
        DLog(@"Move %@ to %@: %@", saved, iterm2env, error);
        virtualenv = [self environmentForScript:fullPath checkForMain:YES checkForSaved:NO];
    }

    const int version = [self environmentVersionAt:iterm2env];
    if (version < iTermMinimumPythonEnvironmentVersion) {
        [self upgradeFullEnvironmentScriptAt:fullPath
                                configParser:configParser
                                  completion:completion];
        return;
    }
    completion(virtualenv);
}

+ (void)launchScript:(NSString *)filename
            fullPath:(NSString *)fullPath
           arguments:(NSArray<NSString *> *)arguments
      withVirtualEnv:(NSString *)virtualenv
        setupCfgPath:(NSString *)setupCfgPath
  explicitUserAction:(BOOL)explicitUserAction {
    if (![[NSFileManager defaultManager] homeDirectoryDotDir]) {
        return;
    }
    [self installRosettaIfNeededThen:^{
        if (virtualenv != nil) {
            // This is a full-environment script. Check if its environment version is supported and
            // offer to upgrade.
            iTermSetupCfgParser *parser = [[iTermSetupCfgParser alloc] initWithPath:setupCfgPath];
            [self upgradeIfNeededFullEnvironmentScriptAt:fullPath
                                            configParser:parser
                                              virtualEnv:virtualenv
                                              completion:^(NSString *updatedVirtualEnv) {
                NSString *pythonVersion = parser.pythonVersion;
                [self reallyLaunchScript:filename
                                fullPath:fullPath
                               arguments:arguments
                          withVirtualEnv:updatedVirtualEnv
                           pythonVersion:pythonVersion
                      explicitUserAction:explicitUserAction];
            }];
            return;
        }

        NSString *pythonVersion = [self inferredPythonVersionFromScriptAt:filename];
        [[iTermPythonRuntimeDownloader sharedInstance] downloadOptionalComponentsIfNeededWithConfirmation:YES
                                                                                            pythonVersion:pythonVersion
                                                                                minimumEnvironmentVersion:0
                                                                                       requiredToContinue:YES
                                                                                           withCompletion:
         ^(iTermPythonRuntimeDownloaderStatus status) {
            switch (status) {
                case iTermPythonRuntimeDownloaderStatusNotNeeded:
                case iTermPythonRuntimeDownloaderStatusDownloaded:
                    [self reallyLaunchScript:filename
                                    fullPath:fullPath
                                   arguments:arguments
                              withVirtualEnv:virtualenv
                               pythonVersion:pythonVersion
                          explicitUserAction:explicitUserAction];
                    break;
                case iTermPythonRuntimeDownloaderStatusError:
                case iTermPythonRuntimeDownloaderStatusUnknown:
                case iTermPythonRuntimeDownloaderStatusWorking:
                case iTermPythonRuntimeDownloaderStatusCanceledByUser:
                case iTermPythonRuntimeDownloaderStatusRequestedVersionNotFound:
                    break;
            }
        }];
    }];
}

+ (BOOL)rosettaIsInstalled {
    return [[NSFileManager defaultManager] fileExistsAtPath:@"/usr/libexec/rosetta"];
}

+ (BOOL)userConsentsToInstallingRosetta {
    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:@"You must install Rosetta 2 in order to use the Python API. Install it now?"
                               actions:@[ @"OK", @"Cancel" ]
                             accessory:nil
                            identifier:@"NoSyncInstallRosetta"
                           silenceable:kiTermWarningTypePersistent
                               heading:@"Install Rosetta?"
                                window:nil];
    return selection == kiTermWarningSelection0;
}

+ (void)installRosettaIfUserConsentsWithCompletion:(void (^)(void))completion {
    if (![self userConsentsToInstallingRosetta]) {
        completion();
        return;
    }
    [self reallyInstallRosettaWithCompletion:completion];
}

+ (void)reallyInstallRosettaWithCompletion:(void (^)(void))completion {
    [[iTermController sharedInstance] openSingleUseWindowWithCommand:@"/usr/sbin/softwareupdate"
                                                           arguments:@[ @"--install-rosetta" ]
                                                              inject:nil
                                                         environment:nil
                                                                 pwd:nil
                                                             options:iTermSingleUseWindowOptionsCloseOnTermination
                                                      didMakeSession:nil
                                                          completion:completion];
}

+ (BOOL)rosettaIsNeeded {
    return [NSProcessInfo it_hasARMProcessor];
}

+ (void)installRosettaIfNeededThen:(void (^)(void))completion {
    if ([self rosettaIsNeeded] && ![self rosettaIsInstalled]) {
        [self installRosettaIfUserConsentsWithCompletion:completion];
    } else {
        completion();
    }
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
                 arguments:(NSArray<NSString *> *)arguments
            withVirtualEnv:(NSString *)virtualenv
             pythonVersion:(NSString *)pythonVersion
        explicitUserAction:(BOOL)explicitUserAction {
    if (explicitUserAction) {
        if (![iTermAPIHelper sharedInstanceFromExplicitUserAction]) {
            return;
        }
    } else {
        if (![iTermAPIHelper sharedInstance]) {
            return;
        }
    }

    NSString *key = [[NSUUID UUID] UUIDString];
    NSString *identifier = [[iTermAPIConnectionIdentifierController sharedInstance] identifierForKey:key];
    NSString *name = [[filename lastPathComponent] stringByDeletingPathExtension];
    if (virtualenv) {
        // Convert /foo/bar/Name/Name/main.py to Name
        name = [[[filename stringByDeletingLastPathComponent] pathComponents] lastObject];
    }
    iTermScriptHistoryEntry *entry = [[iTermScriptHistoryEntry alloc] initWithName:name
                                                                          fullPath:fullPath
                                                                        identifier:identifier
                                                                          relaunch:
                                      ^{
                                          [iTermAPIScriptLauncher reallyLaunchScript:filename
                                                                            fullPath:fullPath
                                                                           arguments:arguments
                                                                      withVirtualEnv:virtualenv
                                                                       pythonVersion:pythonVersion
                                                                  explicitUserAction:explicitUserAction];
                                      }];
    entry.path = filename;
    [[iTermScriptHistory sharedInstance] addHistoryEntry:entry];

    @try {
        [self tryLaunchScript:filename
                    arguments:arguments
                 historyEntry:entry
                          key:key
               withVirtualEnv:virtualenv
                pythonVersion:pythonVersion];
    }
    @catch (NSException *e) {
        [[iTermScriptHistory sharedInstance] addHistoryEntry:entry];
        [entry addOutput:[NSString stringWithFormat:@"ERROR: Failed to launch: %@", e.reason]
              completion:^{}];
        [self didFailToLaunchScript:filename withException:e];
    }
}

// THROWS
+ (void)tryLaunchScript:(NSString *)filename
              arguments:(NSArray<NSString *> *)arguments
           historyEntry:(iTermScriptHistoryEntry *)entry
                    key:(NSString *)key
         withVirtualEnv:(NSString *)virtualenv
          pythonVersion:(NSString *)pythonVersion {
    NSTask *task = [[NSTask alloc] init];

    // Run through the user's shell so their PATH is set properly.
    NSString *shell = [iTermOpenDirectory userShell];
    // I've tested these shells and they all work when run as: $SHELL -c command arg arg
    NSArray<NSString *> *const knownShells = @[ @"bash", @"tcsh", @"zsh", @"fish" ];
    if ([[NSFileManager defaultManager] fileExistsAtPath:shell] &&
        [knownShells containsObject:[shell lastPathComponent]]) {
        task.launchPath = shell;
    } else {
        task.launchPath = @"/bin/bash";
    }
    task.arguments = [self argumentsToRunScript:filename
                                      arguments:arguments
                                 withVirtualEnv:virtualenv
                                  pythonVersion:pythonVersion];
    NSString *cookie = [[iTermWebSocketCookieJar sharedInstance] randomStringForCookie];
    NSString *standardEnv = [[iTermPythonRuntimeDownloader sharedInstance] pathToStandardPyenvPythonWithPythonVersion:pythonVersion];
    NSString *searchPath = [iTermPythonRuntimeDownloader.sharedInstance pathToStandardPyenvWithVersion:pythonVersion
                                        creatingSymlinkIfNeeded:NO];
    NSString *path = [searchPath stringByAppendingPathComponent:@"versions"];
    NSString *standardPythonVersion = [[iTermPythonRuntimeDownloader bestPythonVersionAt:path] it_twoPartVersionNumber];
    task.environment = [self environmentFromEnvironment:[[NSProcessInfo processInfo] environment]
                                                  shell:[iTermOpenDirectory userShell]
                                                 cookie:cookie
                                                    key:key
                                             virtualenv:virtualenv ?: standardEnv
                                          pythonVersion:pythonVersion ?: standardPythonVersion];

    NSPipe *pipe = [[NSPipe alloc] init];
    [task setStandardOutput:pipe];
    [task setStandardError:pipe];

    [entry addOutput:[NSString stringWithFormat:@"%@ %@\n", task.launchPath, [task.arguments componentsJoinedByString:@" "]]
          completion:^{}];
    [task launch];   // This can throw
    entry.pids = @[ @(task.processIdentifier) ];
    [self waitForTask:task readFromPipe:pipe historyEntry:entry];
}

+ (NSDictionary *)environmentFromEnvironment:(NSDictionary *)initialEnvironment
                                       shell:(NSString *)shell
                                      cookie:(NSString *)cookie
                                         key:(NSString *)key
                                  virtualenv:(NSString *)virtualenv
                               pythonVersion:(NSString *)pythonVersion {
    NSMutableDictionary *environment = [initialEnvironment ?: @{} mutableCopy];

    environment[@"ITERM2_COOKIE"] = cookie;
    environment[@"ITERM2_KEY"] = key;
    environment[@"HOME"] = NSHomeDirectory();
    if (shell) {
        environment[@"SHELL"] = shell;
    }
    environment[@"PYTHONIOENCODING"] = @"utf-8";

    // OpenSSL bakes in the directory where you compiled it so it can find root certs.
    // That works great if you happen to be me, but it seems that most people aren't.
    // Luckily it lets you set some environment variables to find cert stores.
    NSString *version = [[virtualenv stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    environment[@"SSL_CERT_FILE"] = [version stringByAppendingPathComponents:@[
        @"lib",
        [NSString stringWithFormat:@"python%@", pythonVersion],
        @"site-packages",
        @"pip",
        @"_vendor",
        @"certifi",
        @"cacert.pem"
    ]];
    environment[@"SSL_CERT_DIR"] = [version stringByAppendingPathComponents:@[
        @"openssl",
        @"ssl",
        @"certs"
    ]];
    return environment;
}

+ (NSArray *)argumentsToRunScript:(NSString *)filename
                        arguments:(NSArray<NSString *> *)arguments
                   withVirtualEnv:(NSString *)providedVirtualEnv
                    pythonVersion:(NSString *)pythonVersion {
    NSString *wrapper = [[NSBundle bundleForClass:self.class] pathForResource:@"it2_api_wrapper" ofType:@"sh"];
    NSString *pyenv = [[iTermPythonRuntimeDownloader sharedInstance] pathToStandardPyenvPythonWithPythonVersion:pythonVersion];
    NSString *virtualEnv = providedVirtualEnv ?: pyenv;
    NSString *command = [NSString stringWithFormat:@"%@ %@ %@",
                         [wrapper stringWithEscapedShellCharactersExceptTabAndNewline],
                         [virtualEnv stringWithEscapedShellCharactersExceptTabAndNewline],
                         [filename stringWithEscapedShellCharactersExceptTabAndNewline]];
    if (arguments.count > 0) {
        NSArray<NSString *> *escapedArguments = [arguments mapWithBlock:^id(NSString *anObject) {
            return [anObject stringWithEscapedShellCharactersIncludingNewlines:YES];
        }];
        NSString *joinedArguments = [escapedArguments componentsJoinedByString:@" "];
        command = [command stringByAppendingFormat:@" %@", joinedArguments];
    }
    NSArray<NSString *> *result = @[ @"-c", command ];
    return result;
}

+ (void)waitForTask:(NSTask *)task readFromPipe:(NSPipe *)pipe historyEntry:(iTermScriptHistoryEntry *)entry {
    static NSMutableArray<dispatch_queue_t> *queues;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queues = [NSMutableArray array];
    });
    dispatch_queue_t q = dispatch_queue_create("com.iterm2.script-launcher", NULL);
    @synchronized(queues) {
        [queues addObject:q];
    }
    dispatch_async(q, ^{
        NSFileHandle *readHandle = [pipe fileHandleForReading];
        NSData *inData = [readHandle availableData];
        while (inData.length) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [entry addOutput:[[NSString alloc] initWithData:inData encoding:NSUTF8StringEncoding]
                      completion:^{}];
            });
            inData = [readHandle availableData];
        }

        [task waitUntilExit];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!task.isRunning && (task.terminationReason == NSTaskTerminationReasonUncaughtSignal || task.terminationStatus != 0)) {
                if (task.terminationReason == NSTaskTerminationReasonUncaughtSignal) {
                    [entry addOutput:@"\n** Script was killed by a signal **"
                          completion:^{}];
                } else {
                    [entry addOutput:[NSString stringWithFormat:@"\n** Script exited with status %@ **", @(task.terminationStatus)]
                          completion:^{}];
                }
                if (!entry.terminatedByUser) {
                    NSString *message = [NSString stringWithFormat:@"“%@” ended unexpectedly.", entry.name];
                    [[iTermNotificationController sharedInstance] postNotificationWithTitle:@"Script Failed"
                                                                                     detail:message
                                                                   callbackNotificationName:iTermAPIScriptLauncherScriptDidFailUserNotificationCallbackNotification
                                                               callbackNotificationUserInfo:@{ @"entry": entry.identifier ?: @"" }];
                    static dispatch_once_t onceToken;
                    dispatch_once(&onceToken, ^{
                        [[NSNotificationCenter defaultCenter] addObserver:self
                                                                 selector:@selector(revealFailedScriptInConsole:)
                                                                     name:iTermAPIScriptLauncherScriptDidFailUserNotificationCallbackNotification
                                                                   object:nil];
                    });
                }
            }
            [entry stopRunning];
        });
        @synchronized(queues) {
            [queues removeObject:q];
        }
    });
}

+ (void)revealFailedScriptInConsole:(NSNotification *)notification {
    NSString *identifier = notification.userInfo[@"entry"];
    iTermScriptHistoryEntry *entry = [[iTermScriptHistory sharedInstance] entryWithIdentifier:identifier];
    if (entry) {
        [[iTermScriptConsole sharedInstance] revealTailOfHistoryEntry:entry];
    }
}

+ (void)didFailToLaunchScript:(NSString *)filename withException:(NSException *)e {
    ELog(@"Exception occurred %@", e);
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Error running script";
    alert.informativeText = [NSString stringWithFormat:@"Script at \"%@\" failed.\n\n%@",
                             filename, e.reason];
    [alert runModal];
}

+ (NSString *)pathToVersionsFolderForPyenvScriptNamed:(NSString *)name {
    NSArray<NSString *> *components = @[ name, @"iterm2env", @"versions" ];
    NSString *path = [[NSFileManager defaultManager] scriptsPathWithoutSpaces];
    for (NSString *part in components) {
        path = [path stringByAppendingPathComponent:part];
    }
    return path;
}

+ (NSString *)prospectivePythonPathForPyenvScriptNamed:(NSString *)name {
    NSString *path = [self pathToVersionsFolderForPyenvScriptNamed:name];
    NSString *pythonVersion = [iTermPythonRuntimeDownloader bestPythonVersionAt:path] ?: @"_NO_PYTHON_VERSION_FOUND_";
    NSArray<NSString *> *components = @[ pythonVersion, @"bin", @"python3" ];
    for (NSString *part in components) {
        path = [path stringByAppendingPathComponent:part];
    }

    return path;
}

+ (NSString *)environmentForScript:(NSString *)path
                      checkForMain:(BOOL)checkForMain
                     checkForSaved:(BOOL)checkForSaved {
    if (checkForMain) {
        NSString *name = path.lastPathComponent;
        // If path is foo/bar then look for foo/bar/bar/bar.py
        NSString *expectedPath = [[path stringByAppendingPathComponent:name] stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"py"]];
        if (![[NSFileManager defaultManager] fileExistsAtPath:expectedPath isDirectory:nil]) {
            return nil;
        }
    }

    // Does it have a pyenv?
    // foo/bar/iterm2env
    iTermPythonRuntimeDownloader *downloader = [iTermPythonRuntimeDownloader sharedInstance];
    {
        NSString *pyenvPython = [downloader pyenvAt:[path stringByAppendingPathComponent:@"iterm2env"]
                                      pythonVersion:[iTermAPIScriptLauncher pythonVersionForScript:path]];
        if ([[NSFileManager defaultManager] fileExistsAtPath:pyenvPython isDirectory:nil]) {
            return pyenvPython;
        }
    }

    if (!checkForSaved) {
        return nil;
    }

    {
        NSString *pyenvPython = [downloader pyenvAt:[path stringByAppendingPathComponent:@"saved-iterm2env"]
                                      pythonVersion:[iTermAPIScriptLauncher pythonVersionForScript:path]];
        if ([[NSFileManager defaultManager] fileExistsAtPath:pyenvPython isDirectory:nil]) {
            return pyenvPython;
        }
    }

    return nil;
}

@end

