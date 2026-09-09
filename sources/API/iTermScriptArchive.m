//
//  iTermScriptArchive.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/24/18.
//

#import "iTermScriptArchive.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermPythonRuntimeDownloader.h"
#import "iTermSetupCfgParser.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "RegexKitLite.h"

NSString *const iTermScriptSetupCfgName = @"setup.cfg";
NSString *const iTermScriptDeprecatedSetupPyName = @"setup.py";
NSString *const iTermScriptMetadataName = @"metadata.json";

@interface iTermScriptArchive()
@property (nonatomic, copy, readwrite) NSString *container;
@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, strong, readwrite) NSDictionary *metadata;
@property (nonatomic, readwrite) BOOL fullEnvironment;
@end

@implementation iTermScriptArchive

+ (instancetype)archiveForScriptIn:(NSString *)container
                             named:(NSString *)name
                   fullEnvironment:(BOOL)fullEnvironment {
    iTermScriptArchive *archive = [[self alloc] init];
    archive.container = container.copy;
    archive.name = name.copy;
    archive.fullEnvironment = fullEnvironment;
    archive.metadata = [self metadataInContainer:container name:name];
    return archive;
}

+ (NSDictionary *)metadataInContainer:(NSString *)container name:(NSString *)name {
    NSString *path = [[container stringByAppendingPathComponent:name] stringByAppendingPathComponent:@"metadata.json"];
    NSString *stringValue = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!stringValue) {
        return nil;
    }
    return [NSDictionary castFrom:[NSJSONSerialization it_objectForJsonString:stringValue]];
}

+ (NSArray<NSString *> *)absolutePathsOfNonDotFilesIn:(NSString *)container {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray<NSString *> *topLevelItems = [fileManager it_itemsInDirectory:container];
    topLevelItems = [topLevelItems filteredArrayUsingBlock:^BOOL(NSString *anObject) {
        return ![anObject hasPrefix:@"."];
    }];
    topLevelItems = [topLevelItems mapWithBlock:^id(NSString *anObject) {
        return [container stringByAppendingPathComponent:anObject];
    }];
    return topLevelItems;
}

+ (instancetype)archiveFromContainer:(NSString *)container
                          deprecated:(out BOOL *)deprecatedPtr {
    if (deprecatedPtr) {
        *deprecatedPtr = NO;
    }
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray<NSString *> *topLevelItems = [self absolutePathsOfNonDotFilesIn:container];
    if (topLevelItems.count != 1) {
        return nil;
    }

    NSString *topLevelItem = topLevelItems.firstObject;
    const BOOL topLevelItemIsDirectory = [fileManager itemIsDirectory:topLevelItem];
    if ([[topLevelItem pathExtension] isEqualToString:@"py"] &&
        !topLevelItemIsDirectory &&
        [topLevelItem isEqualToString:[container stringByAppendingPathComponent:topLevelItem.lastPathComponent]]) {
        // Basic script
        return [iTermScriptArchive archiveForScriptIn:container named:topLevelItems[0].lastPathComponent fullEnvironment:NO];
    }
    if (!topLevelItemIsDirectory) {
        // File not ending in .py
        return nil;
    }

    NSArray<NSString *> *innerItems = [self absolutePathsOfNonDotFilesIn:topLevelItem];
    if (innerItems.count < 2) {
        return nil;
    }
    // Maps a boolean number to an item name. True key = setup.cfg, false key = not setup.py
    NSString *setupCfg = [topLevelItem stringByAppendingPathComponent:iTermScriptSetupCfgName];
    NSString *deprecatedSetupPy = [topLevelItem stringByAppendingPathComponent:iTermScriptDeprecatedSetupPyName];
    NSString *metadata = [topLevelItem stringByAppendingPathComponent:iTermScriptMetadataName];
    NSArray<NSString *> *requiredFiles = @[ setupCfg ];
    NSArray<NSString *> *optionalFiles = @[ metadata ];
    NSString *folder = nil;

    for (NSString *item in innerItems) {
        if ([requiredFiles containsObject:item]) {
            requiredFiles = [requiredFiles arrayByRemovingObject:item];
            continue;
        }
        if ([optionalFiles containsObject:item]) {
            continue;
        }
        if (folder == nil && [fileManager itemIsDirectory:item]) {
            folder = item;
            continue;
        }
        if ([item isEqualToString:deprecatedSetupPy]) {
            if (deprecatedPtr) {
                *deprecatedPtr = YES;
            }
        }
        return nil;
    }
    if (!folder || requiredFiles.count) {
        return nil;
    }
    NSString *name = [folder lastPathComponent];
    BOOL isDirectory;
    // mainPy="dir/name/name.py"
    NSString *mainPy = [[topLevelItem stringByAppendingPathComponent:name] stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"py"]];
    if (![fileManager fileExistsAtPath:mainPy isDirectory:&isDirectory] ||
        isDirectory) {
        return nil;
    }

    return [iTermScriptArchive archiveForScriptIn:container named:name fullEnvironment:YES];
}

- (BOOL)wantsAutoLaunch {
    return [[NSNumber castFrom:self.metadata[@"AutoLaunch"]] boolValue];
}

- (BOOL)userAcceptsTrustedScriptAutoLaunchInstall {
    NSString *body = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"ScriptArchive.TrustedAutoLaunchMessage", nil, [NSBundle mainBundle], @"“%@” would like to launch automatically when iTerm2 starts. Would you like to allow that?", @"Prompt asking whether to allow a trusted script to auto-launch; %@ is the script name"), self.name];
    const iTermWarningSelection selection = [iTermWarning showWarningWithTitle:body
                                                                       actions:@[ NSLocalizedStringWithDefaultValue(@"ScriptArchive.LaunchAutomatically", nil, [NSBundle mainBundle], @"Launch Automatically", @"Button to allow a script to launch automatically"), NSLocalizedStringWithDefaultValue(@"ScriptArchive.LaunchManually", nil, [NSBundle mainBundle], @"Lauch Manually", @"Button to require launching a script manually") ]
                                                                     accessory:nil
                                                                    identifier:nil
                                                                   silenceable:kiTermWarningTypePersistent
                                                                       heading:NSLocalizedStringWithDefaultValue(@"ScriptArchive.AllowAutoLaunchHeading", nil, [NSBundle mainBundle], @"Allow Auto-Launch?", @"Heading for the allow-auto-launch dialog")
                                                                        window:nil];
    return (selection == kiTermWarningSelection0);
}

- (BOOL)userAcceptsExplicitAutoLaunchInstall {
    NSString *body = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"ScriptArchive.ExplicitAutoLaunchMessage", nil, [NSBundle mainBundle], @"“%@” can launch automatically when iTerm2 starts. Would you like to allow that?", @"Prompt asking whether to allow a script to auto-launch; %@ is the script name"), self.name];
    const iTermWarningSelection selection = [iTermWarning showWarningWithTitle:body
                                                                       actions:@[ NSLocalizedStringWithDefaultValue(@"ScriptArchive.LaunchAutomatically", nil, [NSBundle mainBundle], @"Launch Automatically", @"Button to allow a script to launch automatically"), NSLocalizedStringWithDefaultValue(@"ScriptArchive.LaunchManually", nil, [NSBundle mainBundle], @"Lauch Manually", @"Button to require launching a script manually") ]
                                                                     accessory:nil
                                                                    identifier:nil
                                                                   silenceable:kiTermWarningTypePersistent
                                                                       heading:NSLocalizedStringWithDefaultValue(@"ScriptArchive.AllowAutoLaunchHeading", nil, [NSBundle mainBundle], @"Allow Auto-Launch?", @"Heading for the allow-auto-launch dialog")
                                                                        window:nil];
    return (selection == kiTermWarningSelection0);
}

- (void)installTrusted:(BOOL)trusted
       offerAutoLaunch:(BOOL)offerAutoLaunch
               avoidUI:(BOOL)avoidUI
  provisioningDidBegin:(void (^)(void))provisioningDidBegin
        withCompletion:(void (^)(NSError *, NSURL *location))completion {
    RLog(@"trusted=%@ offerAutoLaunch=%@", @(trusted), @(offerAutoLaunch));
    if (self.fullEnvironment) {
        [self installFullEnvironmentTrusted:trusted
                            offerAutoLaunch:offerAutoLaunch
                                    avoidUI:avoidUI
                       provisioningDidBegin:provisioningDidBegin
                                 completion:completion];
    } else {
        // A basic script install is an instant file move; no provisioning phase.
        [self installBasicTrusted:trusted
                  offerAutoLaunch:offerAutoLaunch
                          avoidUI:avoidUI
                       completion:completion];
    }
}

- (void)installBasicTrusted:(BOOL)trusted
            offerAutoLaunch:(BOOL)offerAutoLaunch
                    avoidUI:(BOOL)avoidUI
                 completion:(void (^)(NSError *, NSURL *location))completion {
    NSString *from = [self.container stringByAppendingPathComponent:self.name];
    NSString *to;
    if ([self shouldAutoLaunchWhenTrusted:trusted offerAutoLaunch:offerAutoLaunch avoidUI:avoidUI]) {
        to = [[[NSFileManager defaultManager] autolaunchScriptPathCreatingLink] stringByAppendingPathComponent:self.name];
    } else {
        to = [[[NSFileManager defaultManager] scriptsPathWithoutSpaces] stringByAppendingPathComponent:self.name];
    }
    NSError *error = nil;
    [[NSFileManager defaultManager] moveItemAtPath:from
                                            toPath:to
                                             error:&error];
    completion(error, [NSURL fileURLWithPath:to]);
}

- (BOOL)shouldOfferAutoLaunchWhenTrusted:(BOOL)trusted
                         offerAutoLaunch:(BOOL)offerAutoLaunch {
    if (offerAutoLaunch) {
        return YES;
    }
    if (trusted && [self wantsAutoLaunch]) {
        return YES;
    }
    return NO;
}

- (BOOL)shouldAutoLaunchWhenTrusted:(BOOL)trusted
                    offerAutoLaunch:(BOOL)offerAutoLaunch
                            avoidUI:(BOOL)avoidUI {
    if (![self shouldOfferAutoLaunchWhenTrusted:trusted offerAutoLaunch:offerAutoLaunch]) {
        return NO;
    }
    if (avoidUI) {
        return YES;
    }
    if (offerAutoLaunch) {
        return [self userAcceptsExplicitAutoLaunchInstall];
    } else {
        return [self userAcceptsTrustedScriptAutoLaunchInstall];
    }
}

- (void)installFullEnvironmentTrusted:(BOOL)trusted
                      offerAutoLaunch:(BOOL)offerAutoLaunch
                              avoidUI:(BOOL)avoidUI
                 provisioningDidBegin:(void (^)(void))provisioningDidBegin
                           completion:(void (^)(NSError *, NSURL *location))completion {
    DLog(@"trusted=%@ offerAutoLaunch=%@", @(trusted), @(offerAutoLaunch));
    NSString *from = [self.container stringByAppendingPathComponent:self.name];

    NSString *setupCfg = [from stringByAppendingPathComponent:iTermScriptSetupCfgName];
    iTermSetupCfgParser *setupParser = [[iTermSetupCfgParser alloc] initWithPath:setupCfg];
    if (!setupParser) {
        RLog(@"Can't find setup.cfg");
        NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: NSLocalizedStringWithDefaultValue(@"ScriptArchive.MissingSetupCfg", nil, [NSBundle mainBundle], @"Cannot find setup.cfg", @"Error shown when a script archive is missing its required setup.cfg file") };
        NSError *error = [NSError errorWithDomain:@"com.iterm2.scriptarchive" code:1 userInfo:userInfo];
        completion(error, nil);
        return;
    }

    NSArray<NSString *> *dependencies = setupParser.dependencies;
    if (setupParser.dependenciesError) {
        RLog(@"deps error %@", setupParser.dependenciesError);
        completion(setupParser.dependenciesError, nil);
        return;
    }

    // You always get the iterm2 module so don't bother to pip install it.
    dependencies = [dependencies arrayByRemovingObject:@"iterm2"];

    // Decide where to put it and make the directory if needed.
    NSString *containingFolder;
    if ([self shouldAutoLaunchWhenTrusted:trusted offerAutoLaunch:offerAutoLaunch avoidUI:avoidUI]) {
        containingFolder = [[NSFileManager defaultManager] autolaunchScriptPathCreatingLink];
    } else {
        containingFolder = [[NSFileManager defaultManager] scriptsPathWithoutSpaces];
    }
    DLog(@"mkdir %@", containingFolder);
    [[NSFileManager defaultManager] createDirectoryAtPath:containingFolder
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    NSString *to = [containingFolder stringByAppendingPathComponent:self.name];

    // Create a symlink from the final location to the temporary location so shebangs will work.
    // First try to remove a dangling link.
    if ([[[[NSFileManager defaultManager] attributesOfItemAtPath:to error:nil] fileType] isEqualToString:NSFileTypeSymbolicLink]) {
        NSString *expanded = [[NSFileManager defaultManager] destinationOfSymbolicLinkAtPath:to error:nil];
        if (expanded && ![[NSFileManager defaultManager] fileExistsAtPath:expanded]) {
            DLog(@"rm %@", to);
            [[NSFileManager defaultManager] removeItemAtPath:to error:nil];
        }
    }

    NSError *error = nil;
    DLog(@"ln -s %@ %@", to, from);
    [[NSFileManager defaultManager] createSymbolicLinkAtPath:to
                                         withDestinationPath:from
                                                       error:&error];
    if (error) {
        RLog(@"%@", error);
        NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"ScriptArchive.WriteFailed", nil, [NSBundle mainBundle], @"Could not write to %@", @"Error shown when a script archive cannot create a file during installation; %@ is the path"), to] };
        NSError *error = [NSError errorWithDomain:@"com.iterm2.scriptarchive" code:1 userInfo:userInfo];
        completion(error, nil);
        return;
    }

    if ([iTermAdvancedSettingsModel pythonRuntimeUsesUV]) {
        // uv path: downloading uv and building the .venv are one step, so skip the
        // legacy runtime download/install entirely and provision into `from`.
        DLog(@"Will provision uv environment at %@", from);
        [[iTermUvProvisioner shared] downloadAndProvisionFullEnvironmentWithContainer:from
                                                              requestedPythonVersion:setupParser.pythonVersion ?: [iTermScriptRuntime defaultPythonVersion]
                                                                        dependencies:dependencies ?: @[]
                                                                      createSetupCfg:NO
                                                                provisioningDidBegin:provisioningDidBegin
                                                                          completion:^(NSError *errorStatus) {
            [self didInstallPythonRuntimeWithError:errorStatus
                                              from:from
                                                to:to
                                        completion:^(NSError *runtimeInstallError) {
                completion(runtimeInstallError,
                           runtimeInstallError == nil ? [NSURL fileURLWithPath:to] : nil);
            }];
        }];
        return;
    }

    DLog(@"Will download optional components if needed");
    [[iTermPythonRuntimeDownloader sharedInstance] downloadOptionalComponentsIfNeededWithConfirmation:YES
                                                                                        pythonVersion:setupParser.pythonVersion
                                                                            minimumEnvironmentVersion:setupParser.minimumEnvironmentVersion
                                                                                   requiredToContinue:YES
                                                                                       withCompletion:
     ^(iTermPythonRuntimeDownloaderStatus status) {
        DLog(@"status=%@", @(status));
        switch (status) {
            case iTermPythonRuntimeDownloaderStatusRequestedVersionNotFound:
            case iTermPythonRuntimeDownloaderStatusCanceledByUser:
            case iTermPythonRuntimeDownloaderStatusUnknown:
            case iTermPythonRuntimeDownloaderStatusWorking:
            case iTermPythonRuntimeDownloaderStatusError: {
                [[NSFileManager defaultManager] removeItemAtPath:to error:nil];
                NSString *reason = [self errorReasonForRuntimeDownloaderStatus:status];
                NSString *description = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"ScriptArchive.RuntimeNotDownloaded", nil, [NSBundle mainBundle], @"Python Runtime not downloaded: %@", @"Error shown when the Python runtime needed to install a script could not be downloaded; %@ is the reason"), reason];
                NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: description };
                NSError *error = [NSError errorWithDomain:@"com.iterm2.scriptarchive" code:3 userInfo:userInfo];
                completion(error, nil);
                return;
            }

            case iTermPythonRuntimeDownloaderStatusNotNeeded:
            case iTermPythonRuntimeDownloaderStatusDownloaded:
                DLog(@"No need to download");
                break;
        }
        NSURL *toURL = [NSURL fileURLWithPath:to];
        DLog(@"Will install python environment to %@", from);
        // Show the please-wait window now (gate off): the env copy + pip install below is
        // the slow part and, unlike the uv path (where downloadAndProvisionFullEnvironment
        // invokes this itself), the legacy install has no progress UI of its own. Doing it
        // here keeps the window deferred past the download-consent prompt.
        if (provisioningDidBegin) {
            provisioningDidBegin();
        }
        [[iTermPythonRuntimeDownloader sharedInstance] installPythonEnvironmentTo:[NSURL fileURLWithPath:from]
                                                                 eventualLocation:toURL
                                                                    pythonVersion:setupParser.pythonVersion
                                                               environmentVersion:setupParser.minimumEnvironmentVersion
                                                                     dependencies:dependencies
                                                                   createSetupCfg:NO
                                                                       completion:^(NSError *errorStatus) {
            RLog(@"Install python environment done with status %@", errorStatus);
            [self didInstallPythonRuntimeWithError:errorStatus
                                              from:from
                                                to:to
                                        completion:
             ^(NSError *runtimeInstallError) {
                DLog(@"didInstallPythonRuntime done with error %@", runtimeInstallError);
                completion(runtimeInstallError,
                           runtimeInstallError == nil ? toURL : nil);
            }];
        }];
    }];
}

- (NSString *)errorReasonForRuntimeDownloaderStatus:(iTermPythonRuntimeDownloaderStatus)status {
    switch (status) {
        case iTermPythonRuntimeDownloaderStatusRequestedVersionNotFound:
            return NSLocalizedStringWithDefaultValue(@"ScriptArchive.RequestedVersionUnavailable", nil, [NSBundle mainBundle], @"Requested version not available", @"Reason shown when the requested Python version for a script is not available for download");
        case iTermPythonRuntimeDownloaderStatusCanceledByUser:
            return NSLocalizedStringWithDefaultValue(@"ScriptArchive.CanceledByUser", nil, [NSBundle mainBundle], @"Canceled by user", @"Reason shown when the user cancels the Python runtime download during script installation");
        case iTermPythonRuntimeDownloaderStatusUnknown:
        case iTermPythonRuntimeDownloaderStatusWorking:
            return NSLocalizedStringWithDefaultValue(@"ScriptArchive.UnknownProblem", nil, [NSBundle mainBundle], @"An unknown problem occurred", @"Reason shown when the Python runtime download fails for an unknown reason during script installation");
        case iTermPythonRuntimeDownloaderStatusError:
            return NSLocalizedStringWithDefaultValue(@"ScriptArchive.NetworkError", nil, [NSBundle mainBundle], @"Network error", @"Reason shown when the Python runtime download fails due to a network error during script installation");
        case iTermPythonRuntimeDownloaderStatusNotNeeded:
        case iTermPythonRuntimeDownloaderStatusDownloaded:
            return nil;
    }
}

- (void)didInstallPythonRuntimeWithError:(NSError *)errorStatus
                                    from:(NSString *)from
                                      to:(NSString *)to
                              completion:(void (^)(NSError *))completion {
    RLog(@"status=%@ from=%@ to=%@", errorStatus, from, to);
    [[NSFileManager defaultManager] removeItemAtPath:to error:nil];
    if (errorStatus != nil) {
        // Any non-nil error means provisioning did not finish. Never fall through to
        // the move-into-place (success) path below, or a half-provisioned directory
        // (no .venv, no marker) would be installed and reported as a working script.
        // The uv path reports errors in its own domain with code -1 (and cancel -2),
        // which do not match iTermInstallPythonStatus (0/1/2); the previous switch had
        // no default, so those errors silently reached the success path.
        if ([iTermUvProvisioner isCancelationError:errorStatus]) {
            // The user declined the download; forward it so the caller stays silent.
            DLog(@"canceled");
            completion(errorStatus);
            return;
        }
        const BOOL dependencyFailed = (errorStatus.code == iTermInstallPythonStatusDependencyFailed);
        NSString *description = dependencyFailed
            ? [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"ScriptArchive.PackageInstallFailed", nil, [NSBundle mainBundle], @"Failed to install Python package: %@", @"Error shown when installing a script’s Python dependency package fails; %@ is the detail"), errorStatus.localizedDescription]
            : [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"ScriptArchive.RuntimeInstallFailed", nil, [NSBundle mainBundle], @"Failed to install Python Runtime: %@", @"Error shown when installing the Python runtime for a script fails; %@ is the detail"), errorStatus.localizedDescription];
        DLog(@"failure: %@", description);
        NSError *error = [NSError errorWithDomain:@"com.iterm2.scriptarchive"
                                             code:(dependencyFailed ? 2 : 1)
                                         userInfo:@{ NSLocalizedDescriptionKey: description }];
        completion(error);
        return;
    }

    // Finally, move it to its destination.
    NSFileManager *fileManager = [NSFileManager defaultManager];
    // Remove the symlink that should have been dropped there.
    DLog(@"remove symlink %@", to);
    [fileManager removeItemAtPath:to error:nil];

    // Make the destination appear atomically. `from` (the temp extraction dir) may be on a
    // different volume than the scripts folder (customScriptsFolder), where moveItemAtPath
    // does a non-atomic copy+delete; a crash mid-copy would leave a partial REAL directory
    // at `to` that the import crash-recovery sweep would mistake for a completed install and
    // delete the user's backup. So stage on the DESTINATION volume under a dotted name
    // (skipped by the menu walk and the recovery sweep) and then rename into place, which is
    // same-volume and atomic. `to` therefore exists only once fully populated.
    NSString *staging = [[to stringByDeletingLastPathComponent]
                         stringByAppendingPathComponent:[NSString stringWithFormat:@".installing-%@-%@",
                                                         to.lastPathComponent, [[NSUUID UUID] UUIDString]]];
    [fileManager removeItemAtPath:staging error:nil];
    NSError *error = nil;
    DLog(@"move %@ to staging %@", from, staging);
    if (![fileManager moveItemAtPath:from toPath:staging error:&error]) {
        DLog(@"move to staging failed: %@", error);
        [fileManager removeItemAtPath:staging error:nil];
        completion(error);
        return;
    }
    DLog(@"rename staging %@ to %@", staging, to);
    if (![fileManager moveItemAtPath:staging toPath:to error:&error]) {
        DLog(@"rename into place failed: %@", error);
        [fileManager removeItemAtPath:staging error:nil];
        completion(error);
        return;
    }
    completion(nil);
}

@end

