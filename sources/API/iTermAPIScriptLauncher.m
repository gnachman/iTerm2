//
//  iTermAPIScriptLauncher.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/19/18.
//

#import "iTermAPIScriptLauncher.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermAPIConnectionIdentifierController.h"
#import "iTermAPIHelper.h"
#import "iTermController.h"
#import "iTermNotificationController.h"
#import "iTermOpenDirectory+MainApp.h"
#import "iTermOptionalComponentDownloadWindowController.h"
#import "iTermPythonRuntimeDownloader.h"
#import "iTermScriptConsole.h"
#import "iTermScriptHistory.h"
#import "iTermSetupCfgParser.h"
#import "iTermUserDefaults.h"
#import "iTermWarning.h"
#import "iTermWebSocketCookieJar.h"
#import "NSArray+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "NSWorkspace+iTerm.h"
#import "PTYTask.h"

static NSString *const iTermAPIScriptLauncherScriptDidFailUserNotificationCallbackNotification = @"iTermAPIScriptLauncherScriptDidFailUserNotificationCallbackNotification";

@interface iTermAPIScriptLauncher ()
+ (NSString *)uvCertifiPathInVenv:(NSString *)venvDirectory;
@end

@implementation iTermAPIScriptLauncher

+ (void)launchScript:(NSString *)filename
           arguments:(NSArray<NSString *> *)arguments
  explicitUserAction:(BOOL)explicitUserAction {
    DLog(@"filename=%@ arguments=%@ explicitUserAction=%@", filename, arguments, @(explicitUserAction));
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
    DLog(@"%@", fullPath);
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
    DLog(@"fullPath=%@", fullPath);
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
            RLog(@"remove broken %@: %@", existingEnv.path, error);
        } else {
            NSError *error = nil;
            [[NSFileManager defaultManager] moveItemAtURL:existingEnv toURL:savedEnv error:&error];
            RLog(@"saving - move '%@' to '%@': %@", existingEnv.path, savedEnv.path, error);
        }
    }
    [[iTermPythonRuntimeDownloader sharedInstance] installPythonEnvironmentTo:url
                                                                 dependencies:configParser.dependencies
                                                                pythonVersion:configParser.pythonVersion
                                                                   completion:^(NSError *errorStatus) {
        if (!errorStatus) {
            NSError *error = nil;
            [[NSFileManager defaultManager] removeItemAtURL:savedEnv error:&error];
            RLog(@"remove saved - %@: %@", savedEnv.path, error);
            NSString *venv = [self environmentForScript:fullPath checkForMain:YES checkForSaved:NO];
            completion(venv);
            return;
        }

        NSError *error = nil;
        [[NSFileManager defaultManager] removeItemAtURL:existingEnv error:&error];
        RLog(@"remove failed install - %@: %@", existingEnv.path, error);

        error = nil;
        [[NSFileManager defaultManager] moveItemAtURL:savedEnv toURL:existingEnv error:&error];
        RLog(@"restore saved - move '%@' to '%@': %@", savedEnv.path, existingEnv.path, error);

        dispatch_async(dispatch_get_main_queue(), ^{
            [iTermWarning showWarningWithTitle:errorStatus.localizedDescription
                                       actions:@[ @"OK" ]
                                     accessory:nil
                                    identifier:nil
                                   silenceable:kiTermWarningTypePersistent
                                       heading:@"Error Upgrading Script"
                                        window:nil];
        });
    }];
}

+ (void)upgradeIfNeededFullEnvironmentScriptAt:(NSString *)fullPath
                                  configParser:(iTermSetupCfgParser *)configParser
                                    virtualEnv:(NSString *)originalVirtualenv
                                    completion:(void (^)(NSString *))completion {
    DLog(@"fullPath=%@ originalVirtualenv=%@", fullPath, originalVirtualenv);
    // A uv-provisioned script has no legacy iterm2env version to check; the legacy
    // runtime-upgrade path does not apply to it, so launch it directly.
    if ([iTermScriptRuntime backendForScriptContainer:fullPath] == iTermScriptRuntimeBackendUv) {
        // If a prior migration completed (the .venv and marker are present) but the app
        // died before dropping the backup, a saved-iterm2env (potentially multi-GB) is
        // orphaned here and no later code path would ever remove it. Reclaim it now.
        [iTermUvMigration discardLegacyBackupWithContainer:fullPath completion:nil];
        completion(originalVirtualenv);
        return;
    }
    if ([iTermAdvancedSettingsModel pythonRuntimeUsesUV]) {
        // Gate on and this is still a legacy script: migrate it to uv (once), then
        // launch under the new .venv. On failure the legacy env is restored and the
        // script launches on it as before.
        if (configParser == nil || configParser.dependenciesError != nil) {
            // No parseable setup.cfg means we cannot know the script's dependencies.
            // Migrating with an empty dependency list would silently produce a broken
            // uv environment (missing packages), so leave the script on its working
            // legacy environment and log loudly instead.
            NSString *reason = configParser == nil ? @"setup.cfg is missing" : configParser.dependenciesError.localizedDescription ?: @"setup.cfg could not be parsed";
            RLog(@"Not migrating %@ to uv: %@. Launching on the legacy environment.", fullPath, reason);
            completion(originalVirtualenv);
            return;
        }
        __block iTermProvisioningProgressWindowController *progress = [[iTermProvisioningProgressWindowController alloc] init];
        [[iTermUvProvisioner shared] migrateLegacyScriptToUvWithContainer:fullPath
                                                  requestedPythonVersion:configParser.pythonVersion ?: [iTermScriptRuntime defaultPythonVersion]
                                                            dependencies:configParser.dependencies ?: @[]
                                                    provisioningDidBegin:^{
            // Show progress only once the download phase is done and the venv build
            // starts, so a launch-time migration is not a silent multi-second stall.
            [progress showWithMessage:@"Migrating this script to the new Python runtime…"];
        }
                                                              completion:^(NSError *migrationError) {
            [progress dismiss];
            progress = nil;
            if (migrationError != nil) {
                RLog(@"uv migration of %@ failed; launching on the legacy environment: %@", fullPath, migrationError);
                if (![iTermUvProvisioner isCancelationError:migrationError]) {
                    // A real failure (not the user declining the download): the script
                    // silently ran on its old runtime, so leave a Script Console record so
                    // an opted-in user can discover why nothing changed. No modal.
                    NSString *name = [[fullPath pathComponents] lastObject] ?: fullPath;
                    NSString *line = [NSString stringWithFormat:@"Could not migrate “%@” to the uv Python runtime (%@). It launched on the existing runtime instead.\n",
                                      name, migrationError.localizedDescription];
                    [[iTermScriptHistoryEntry globalEntry] addOutput:line completion:^{}];
                }
                // The rollback restored the legacy env, but on a Rosetta-less macOS that
                // env may be Intel-only and unrunnable. Show a clear error rather than
                // exec-failing cryptically. (gate on -> .unrunnable per the disposition;
                // gate off would rebuild, but that path is handled below, not here.)
                if (![iTermRosettaSupport canInstallRosetta] && originalVirtualenv != nil &&
                    [iTermRosettaSupport legacyLaunchDispositionWithInterpreterHasNativeSlice:[iTermRosettaSupport binaryHasArm64SliceAtPath:originalVirtualenv]
                                                                          canInstallRosetta:NO
                                                                                     gateOn:YES] == iTermLegacyLaunchDispositionUnrunnable) {
                    [self showIntelOnlyUnrunnableErrorForScript:fullPath
                                                       recovery:@"Its environment is intact; turn off the uv advanced setting to rebuild it for Apple Silicon."];
                    return;
                }
                completion(originalVirtualenv);
                return;
            }
            completion([iTermScriptRuntime uvInterpreterPathForScriptContainer:fullPath]);
        }];
        return;
    }
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
    RLog(@"version=%@", @(version));
    if (version < iTermMinimumPythonEnvironmentVersion) {
        [self upgradeFullEnvironmentScriptAt:fullPath
                                configParser:configParser
                                  completion:completion];
        return;
    }
    // On a Rosetta-less macOS (27+), an Intel-only legacy interpreter cannot run. Rebuild
    // the env from setup.cfg against the current (arm64) runtime via the same path
    // version-based upgrades use, rather than exec-failing. Only read the binary's arch
    // when Rosetta is actually unavailable, so macOS <= 26 launches are unchanged.
    if (virtualenv != nil && ![iTermRosettaSupport canInstallRosetta]) {
        const BOOL native = [iTermRosettaSupport binaryHasArm64SliceAtPath:virtualenv];
        if ([iTermRosettaSupport legacyLaunchDispositionWithInterpreterHasNativeSlice:native
                                                                    canInstallRosetta:NO
                                                                               gateOn:NO] == iTermLegacyLaunchDispositionRebuild) {
            NSString *line = [NSString stringWithFormat:@"“%@” has an Intel-only Python environment, which cannot run on this version of macOS. Rebuilding it for Apple Silicon…\n",
                              fullPath.lastPathComponent];
            [[iTermScriptHistoryEntry globalEntry] addOutput:line completion:^{}];
            // reallyUpgradeFullEnvironmentScriptAt rebuilds from setup.cfg and calls
            // completion with the new venv on success; on failure it shows its own error.
            [self reallyUpgradeFullEnvironmentScriptAt:fullPath
                                          configParser:configParser
                                            completion:completion];
            return;
        }
    }
    completion(virtualenv);
}

+ (void)launchScript:(NSString *)filename
            fullPath:(NSString *)fullPath
           arguments:(NSArray<NSString *> *)arguments
      withVirtualEnv:(NSString *)virtualenv
        setupCfgPath:(NSString *)setupCfgPath
  explicitUserAction:(BOOL)explicitUserAction {
    DLog(@"launchScript:%@ fullPath:%@ arguments:%@ withVirtualEnv:%@ setupCfgPath:%@ explicitUserAction:%@",
         filename,
         fullPath,
         arguments,
         virtualenv,
         setupCfgPath,
         @(explicitUserAction));
    if (![[NSFileManager defaultManager] homeDirectoryDotDir]) {
        return;
    }
    void (^afterRosetta)(void) = ^{
        DLog(@"virtualenv=%@", virtualenv);
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
                       isFullEnvironment:YES
                           pythonVersion:pythonVersion
                      explicitUserAction:explicitUserAction];
            }];
            return;
        }

        NSString *pythonVersion = [self inferredPythonVersionFromScriptAt:filename];
        if ([iTermAdvancedSettingsModel pythonRuntimeUsesUV]) {
            // Basic scripts share a per-minor uv venv. Ensure it exists (downloading
            // uv and provisioning on first use), then launch the script with it. Once
            // provisioned this is offline; launch is a bare exec of the venv python.
            [[iTermUvProvisioner shared] downloadAndProvisionSharedVenvWithRequestedPythonVersion:pythonVersion ?: [iTermScriptRuntime defaultPythonVersion]
                                                                                      completion:^(NSError *uvError, NSString *sharedPython) {
                if (uvError != nil && [iTermUvProvisioner isCancelationError:uvError]) {
                    // The user declined the download; do not report a failure.
                    return;
                }
                if (uvError != nil || sharedPython == nil) {
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = @"Python Environment Unavailable";
                    alert.informativeText = [NSString stringWithFormat:@"Could not prepare the Python environment for this script: %@",
                                             uvError.localizedDescription ?: @"unknown error"];
                    [alert runModal];
                    return;
                }
                [self reallyLaunchScript:filename
                                fullPath:fullPath
                               arguments:arguments
                          withVirtualEnv:sharedPython
                       isFullEnvironment:NO
                           pythonVersion:pythonVersion
                      explicitUserAction:explicitUserAction];
            }];
            return;
        }
        [[iTermPythonRuntimeDownloader sharedInstance] downloadOptionalComponentsIfNeededWithConfirmation:YES
                                                                                            pythonVersion:pythonVersion
                                                                                minimumEnvironmentVersion:0
                                                                                       requiredToContinue:YES
                                                                                           withCompletion:
         ^(iTermPythonRuntimeDownloaderStatus status) {
            RLog(@"status=%@", @(status));
            switch (status) {
                case iTermPythonRuntimeDownloaderStatusNotNeeded:
                case iTermPythonRuntimeDownloaderStatusDownloaded: {
                    // On a Rosetta-less macOS (27+), a pre-existing Intel-only shared
                    // runtime is current by version but cannot run. The version-based
                    // download above will not refetch it, so replace it with the arm64
                    // build (which the manifest now serves) before launching.
                    NSString *stdPython = [[iTermPythonRuntimeDownloader sharedInstance] pathToStandardPyenvPythonWithPythonVersion:pythonVersion];
                    if (![iTermRosettaSupport canInstallRosetta] && stdPython != nil &&
                        ![iTermRosettaSupport binaryHasArm64SliceAtPath:stdPython]) {
                        [self refetchArm64StandardRuntimeThenLaunch:filename
                                                           fullPath:fullPath
                                                          arguments:arguments
                                                      pythonVersion:pythonVersion
                                                 explicitUserAction:explicitUserAction];
                        break;
                    }
                    [self reallyLaunchScript:filename
                                    fullPath:fullPath
                                   arguments:arguments
                              withVirtualEnv:virtualenv
                           isFullEnvironment:NO
                               pythonVersion:pythonVersion
                          explicitUserAction:explicitUserAction];
                    break;
                }
                case iTermPythonRuntimeDownloaderStatusError:
                case iTermPythonRuntimeDownloaderStatusUnknown:
                case iTermPythonRuntimeDownloaderStatusWorking:
                case iTermPythonRuntimeDownloaderStatusCanceledByUser:
                case iTermPythonRuntimeDownloaderStatusRequestedVersionNotFound:
                    break;
            }
        }];
    };
    // uv interpreters are native (universal2); Rosetta is only needed for the legacy
    // x86_64 runtime. Skip the Rosetta prompt/install only when this launch is CERTAIN
    // to use uv: an already-uv-backed full-env script, or a basic script under the gate
    // (which runs from a native shared venv). A legacy full-env script under the gate is
    // NOT certain: if its migration fails or is canceled it falls back to the x86_64
    // legacy env, which still needs Rosetta, so keep the check for that case (harmless
    // if the migration then succeeds; the script becomes uv-backed and skips it next
    // time). This also matters after macOS 27, which drops Rosetta entirely.
    const BOOL scriptIsUvBacked =
        (fullPath != nil && [iTermScriptRuntime backendForScriptContainer:fullPath] == iTermScriptRuntimeBackendUv);
    const BOOL basicUnderUvGate = (virtualenv == nil) && [iTermAdvancedSettingsModel pythonRuntimeUsesUV];
    if (scriptIsUvBacked || basicUnderUvGate) {
        afterRosetta();
    } else {
        [self installRosettaIfNeededThen:afterRosetta];
    }
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

// Show a clear error (alert + Script Console) when a legacy script's Python environment
// is Intel-only and cannot run because Rosetta is unavailable (macOS 27+). recovery is a
// caller-specific hint for what the user can do about it.
+ (void)showIntelOnlyUnrunnableErrorForScript:(NSString *)fullPath recovery:(NSString *)recovery {
    NSString *name = [[fullPath pathComponents] lastObject] ?: fullPath;
    NSString *base = [NSString stringWithFormat:@"“%@” uses an Intel-only Python environment, which cannot run on this version of macOS because Rosetta is not available.", name];
    [[iTermScriptHistoryEntry globalEntry] addOutput:[NSString stringWithFormat:@"%@ %@\n", base, recovery] completion:^{}];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Script Cannot Run";
        alert.informativeText = [NSString stringWithFormat:@"%@ %@", base, recovery];
        [alert runModal];
    });
}

// A pre-existing Intel-only shared runtime is current by version but unrunnable on a
// Rosetta-less macOS. Remove it so the (version-based) download refetches the arm64 build
// the manifest now serves, then launch. If it still is not native, show a clear error.
+ (void)refetchArm64StandardRuntimeThenLaunch:(NSString *)filename
                                     fullPath:(NSString *)fullPath
                                    arguments:(NSArray<NSString *> *)arguments
                                pythonVersion:(NSString *)pythonVersion
                           explicitUserAction:(BOOL)explicitUserAction {
    iTermPythonRuntimeDownloader *downloader = [iTermPythonRuntimeDownloader sharedInstance];
    NSString *pyenvDir = [downloader pathToStandardPyenvWithVersion:pythonVersion creatingSymlinkIfNeeded:NO];
    if (pyenvDir.length > 0) {
        NSError *error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:pyenvDir error:&error];
        RLog(@"Removed Intel-only standard runtime at %@: %@", pyenvDir, error);
    }
    [[iTermScriptHistoryEntry globalEntry] addOutput:@"The shared Python runtime is Intel-only and cannot run on this version of macOS. Downloading the Apple Silicon runtime…\n"
                                          completion:^{}];
    [downloader downloadOptionalComponentsIfNeededWithConfirmation:YES
                                                    pythonVersion:pythonVersion
                                        minimumEnvironmentVersion:0
                                               requiredToContinue:YES
                                                   withCompletion:^(iTermPythonRuntimeDownloaderStatus status) {
        NSString *stdPython = [downloader pathToStandardPyenvPythonWithPythonVersion:pythonVersion];
        if (stdPython == nil || ![iTermRosettaSupport binaryHasArm64SliceAtPath:stdPython]) {
            [self showIntelOnlyUnrunnableErrorForScript:fullPath
                                               recovery:@"The Apple Silicon runtime could not be downloaded. Check your network connection and try again."];
            return;
        }
        [self reallyLaunchScript:filename
                        fullPath:fullPath
                       arguments:arguments
                  withVirtualEnv:nil
               isFullEnvironment:NO
                   pythonVersion:pythonVersion
              explicitUserAction:explicitUserAction];
    }];
}

+ (void)installRosettaIfNeededThen:(void (^)(void))completion {
    const BOOL hasARM = [NSProcessInfo it_hasARMProcessor];
    if (hasARM && ![self rosettaIsInstalled] &&
        [iTermRosettaSupport shouldPromptForRosettaWithHasARM:hasARM
                                            canInstallRosetta:[iTermRosettaSupport canInstallRosetta]]) {
        [self installRosettaIfUserConsentsWithCompletion:completion];
    } else {
        // No ARM, Rosetta already present, or (macOS 27+) Rosetta cannot be installed:
        // do not prompt or run `softwareupdate --install-rosetta` (it cannot succeed
        // there). Continue; the x86-leftover handling deals with an unrunnable env.
        completion();
    }
}

// Takes a file starting with:
// #!/usr/bin/env python3.7
// and returns "3.7", or nil if it was malformed.
+ (NSString *)inferredPythonVersionFromScriptAt:(NSString *)path {
    DLog(@"Getting version from %@", path);
    FILE *file = fopen(path.UTF8String, "r");
    if (!file) {
        DLog(@"Failed to open it: %s", strerror(errno));
        return nil;
    }
    size_t length;
    char *byteArray = fgetln(file, &length);
    if (length == 0 || byteArray == NULL) {
        DLog(@"File is empty");
        fclose(file);
        return nil;
    }
    NSData *data = [NSData dataWithBytes:byteArray length:length];
    fclose(file);
    NSString *line = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSString *const expectedPrefix = @"#!/usr/bin/env python";
    if (![line hasPrefix:expectedPrefix]) {
        DLog(@"First line does not match expected prefix. It is: %@", line);
        return nil;
    }
    NSString *candidate = [[line substringFromIndex:expectedPrefix.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (candidate.length == 0) {
        DLog(@"Empty candidate");
        return nil;
    }

    NSArray<NSString *> *parts = [candidate componentsSeparatedByString:@"."];
    const BOOL allNumeric = [parts allWithBlock:^BOOL(NSString *anObject) {
        DLog(@"Consider part %@. isNumeric=%@", anObject, @(anObject.isNumeric));
        return [anObject isNumeric];
    }];
    DLog(@"parts=%@", parts);
    if (!allNumeric) {
        DLog(@"Not all parts numeric");
        return nil;
    }

    if (parts.count < 2) {
        DLog(@"Not enough parts");
        return nil;
    }

    DLog(@"Return %@", candidate);
    return candidate;
}

+ (void)reallyLaunchScript:(NSString *)filename
                  fullPath:(NSString *)fullPath
                 arguments:(NSArray<NSString *> *)arguments
            withVirtualEnv:(NSString *)virtualenv
           isFullEnvironment:(BOOL)isFullEnvironment
             pythonVersion:(NSString *)pythonVersion
        explicitUserAction:(BOOL)explicitUserAction {
     RLog(@"reallyLaunchScript:%@ fullPath:%@ arguments:%@ withVirtualEnv:%@ isFullEnvironment:%@ pythonVersion:%@ explicitUserAction:%@",
          filename,
          fullPath,
          RLogRedact(arguments, @(arguments.count)),
          virtualenv,
          @(isFullEnvironment),
          pythonVersion,
          @(explicitUserAction));

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
    if (isFullEnvironment) {
        // Convert /foo/bar/Name/Name/main.py to Name. A basic uv script also has a
        // (shared) virtualenv, so full-environment status is passed explicitly rather
        // than inferred from virtualenv != nil.
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
                                                                   isFullEnvironment:isFullEnvironment
                                                                       pythonVersion:pythonVersion
                                                                  explicitUserAction:explicitUserAction];
                                      }];
    entry.path = filename;
    [[iTermScriptHistory sharedInstance] addHistoryEntry:entry];

    // Wait for the API server socket to be ready before launching the script.
    // This avoids a race condition where the script tries to connect before
    // the server is listening. Issue 12776.
    [iTermAPIHelper whenSocketReadyRunBlock:^(BOOL ready) {
        @try {
            [self tryLaunchScript:filename
                        arguments:arguments
                     historyEntry:entry
                              key:key
                   withVirtualEnv:virtualenv
                    pythonVersion:pythonVersion];
        }
        @catch (NSException *e) {
            RLog(@"%@", e);
            [[iTermScriptHistory sharedInstance] addHistoryEntry:entry];
            [entry addOutput:[NSString stringWithFormat:@"ERROR: Failed to launch: %@", e.reason]
                  completion:^{}];
            [self didFailToLaunchScript:filename withException:e];
        }
    }];
}

// THROWS
+ (void)tryLaunchScript:(NSString *)filename
              arguments:(NSArray<NSString *> *)arguments
           historyEntry:(iTermScriptHistoryEntry *)entry
                    key:(NSString *)key
         withVirtualEnv:(NSString *)virtualenv
          pythonVersion:(NSString *)pythonVersion {
    DLog(@"tryLaunchScript:%@ arguments:%@ historyEntry:%@ key:%@ withVirtualEnv:%@ pythonVersion:%@",
         filename,
         arguments,
         entry,
         key,
         virtualenv,
         pythonVersion);

    NSTask *task = [[NSTask alloc] init];

    // Run through the user's shell so their PATH is set properly.
    NSString *shell = [iTermOpenDirectory userShell];
    // I've tested these shells and they all work when run as: $SHELL -c command arg arg
    NSArray<NSString *> *const knownShells = @[ @"bash", @"tcsh", @"zsh", @"fish", @"xonsh" ];
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
    DLog(@"cookie=%@ standardEnv=%@ searchPath=%@, path=%@, standardPythonVersion=%@ environment=%@",
         cookie, standardEnv, searchPath, path, standardPythonVersion, task.environment);
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
    NSString *suiteName = [iTermUserDefaults customSuiteName];
    if (suiteName) {
        // Point the script's API client at this instance's socket. Without it
        // the iterm2 Python library falls back to the default “iTerm2” suite
        // and would connect to a different instance's API server (for example
        // a separately running production build), operating on the wrong app.
        // Terminal sessions already export this (see PTYSession); menu-launched
        // API scripts need it too.
        environment[@"IT2_SUITE"] = suiteName;
    }
    environment[@"HOME"] = NSHomeDirectory();

    // When this build runs under a custom -suite (e.g. a developer build launched
    // alongside the user’s main iTerm2), the API server’s unix socket lives under
    // ~/Library/Application Support/<suite>/private/socket. The iterm2 Python module
    // reads IT2_SUITE to find that path; without it a menu-launched script would
    // default to “iTerm2” and connect to the main instance’s socket instead. Mirror
    // what PTYSession does for terminal sessions.
    NSString *suiteName = [iTermUserDefaults customSuiteName];
    if (suiteName) {
        environment[@"IT2_SUITE"] = suiteName;
    } else {
        // Do not let a stale IT2_SUITE inherited from our own environment leak through
        // to the script and point it at the wrong instance's socket.
        [environment removeObjectForKey:@"IT2_SUITE"];
    }
    if (shell) {
        environment[@"SHELL"] = shell;
    }
    environment[@"PYTHONIOENCODING"] = @"utf-8";

    // OpenSSL bakes in the directory where you compiled it so it can find root certs.
    // That works great if you happen to be me, but it seems that most people aren't.
    // Luckily it lets you set some environment variables to find cert stores.
    NSString *venvDirectory = [[virtualenv stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    NSString *pyvenvCfg = [venvDirectory stringByAppendingPathComponent:@"pyvenv.cfg"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:pyvenvCfg]) {
        // A uv-provisioned venv (a per-script .venv or a shared basic-script venv):
        // certifi is an ordinary wheel and there is no baked-in openssl cert
        // directory, so point at the venv's certifi and do not set SSL_CERT_DIR.
        NSString *certifi = [self uvCertifiPathInVenv:venvDirectory];
        if (certifi) {
            environment[@"SSL_CERT_FILE"] = certifi;
        }
    } else {
        environment[@"SSL_CERT_FILE"] = [venvDirectory stringByAppendingPathComponents:@[
            @"lib",
            [NSString stringWithFormat:@"python%@", pythonVersion],
            @"site-packages",
            @"pip",
            @"_vendor",
            @"certifi",
            @"cacert.pem"
        ]];
        environment[@"SSL_CERT_DIR"] = [venvDirectory stringByAppendingPathComponents:@[
            @"openssl",
            @"ssl",
            @"certs"
        ]];
    }
    return environment;
}

// The certifi cacert.pem inside a uv .venv, whose interpreter-relative lib path is
// lib/python<X.Y>/site-packages/certifi/cacert.pem. The minor version is discovered
// from the single python* directory so we do not depend on the requested version
// (which may have been remapped during provisioning).
+ (NSString *)uvCertifiPathInVenv:(NSString *)venvDirectory {
    NSString *lib = [venvDirectory stringByAppendingPathComponent:@"lib"];
    NSArray<NSString *> *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:lib error:nil];
    for (NSString *entry in entries) {
        if (![entry hasPrefix:@"python"]) {
            continue;
        }
        NSString *candidate = [lib stringByAppendingPathComponents:@[ entry, @"site-packages", @"certifi", @"cacert.pem" ]];
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
            return candidate;
        }
    }
    return nil;
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

+ (NSString *)fullEnvironmentContainerForMainPyPath:(NSString *)path {
    if (![[path pathExtension] isEqualToString:@"py"]) {
        return nil;
    }
    // A full-environment script's main is at <container>/<name>/<name>.py.
    NSString *container = [[path stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    NSString *name = container.lastPathComponent;
    NSString *expectedMain = [[[container stringByAppendingPathComponent:name]
                               stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"py"];
    if (![path isEqualToString:expectedMain]) {
        return nil;
    }
    // Only redirect when the container actually has a runnable full environment; a plain
    // folder of .py files must still launch as basic scripts.
    if (![self environmentForScript:container checkForMain:YES checkForSaved:YES]) {
        return nil;
    }
    return container;
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

    // A uv-provisioned script is detected purely from what is on disk (a .venv plus
    // the python-runtime.json marker), independent of the pythonRuntimeUsesUV gate,
    // so toggling the gate never strands an already-provisioned script.
    if ([iTermScriptRuntime backendForScriptContainer:path] == iTermScriptRuntimeBackendUv) {
        return [iTermScriptRuntime uvInterpreterPathForScriptContainer:path];
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

