//
//  iTermPythonRuntimeDownloader.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/28/18.
//

#import "iTermPythonRuntimeDownloader.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermBuildingScriptWindowController.h"
#import "iTermCommandRunner.h"
#import "iTermDisclosableView.h"
#import "iTermNotificationController.h"
#import "iTermOptionalComponentDownloadWindowController.h"
#import "iTermPreferences.h"
#import "iTermRateLimitedUpdate.h"
#import "iTermSetupCfgParser.h"
#import "iTermSignatureVerifier.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSMutableData+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "NSWorkspace+iTerm.h"

#import <Sparkle/Sparkle.h>

NSString *const iTermPythonRuntimeDownloaderDidInstallRuntimeNotification = @"iTermPythonRuntimeDownloaderDidInstallRuntimeNotification";

@implementation iTermPythonRuntimeDownloader {
    iTermOptionalComponentDownloadWindowController *_downloadController;
    dispatch_group_t _downloadGroup;
    iTermPythonRuntimeDownloaderStatus _status;  // Set when _downloadGroup notified.
    dispatch_queue_t _queue;  // Used to serialize installs
    iTermPersistentRateLimitedUpdate *_checkForUpdateRateLimit;
    NSInteger _busy;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.iterm2.python-runtime", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

// Picks the largest 3-part version given a 2-part version. E.g., if you give it 3.7 and 3.7.0 and
// 3.7.1 exist in `versionsPath` it will return 3.7.1. Returns nil if none found.
- (NSString *)threePartVersionForTwoPartVersion:(NSString *)twoPartVersion
                                             at:(NSString *)versionsPath {
    SUStandardVersionComparator *comparator = [[SUStandardVersionComparator alloc] init];
    return [[[iTermPythonRuntimeDownloader pythonVersionsAt:versionsPath] filteredArrayUsingBlock:^BOOL(NSString *anObject) {
        return [anObject.it_twoPartVersionNumber isEqualToString:twoPartVersion];
    }] maxWithComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [comparator compareVersion:a toVersion:b];
    }];
}

- (NSString *)executableNamed:(NSString *)name
                  atPyenvRoot:(NSString *)root
                pythonVersion:(NSString *)pythonVersion
                   searchPath:(NSString *)searchPath {
    NSString *path = [searchPath stringByAppendingPathComponent:@"versions"];
    NSString *bestVersion = nil;
    if (pythonVersion) {
        if (pythonVersion.it_twoPartVersionNumber) {
            bestVersion = [self threePartVersionForTwoPartVersion:pythonVersion.it_twoPartVersionNumber at:path];
        } else {
            bestVersion = pythonVersion;
        }
    } else {
        bestVersion = [iTermPythonRuntimeDownloader bestPythonVersionAt:path];
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:[path stringByAppendingPathComponent:bestVersion]]) {
        NSString *result = [root stringByAppendingPathComponent:@"versions"];
        result = [result stringByAppendingPathComponent:bestVersion];
        result = [result stringByAppendingPathComponent:@"bin"];
        result = [result stringByAppendingPathComponent:name];
        return result;
    }
    return nil;
}

- (NSString *)pip3At:(NSString *)root pythonVersion:(NSString *)pythonVersion {
    return [self executableNamed:@"pip3" atPyenvRoot:root pythonVersion:pythonVersion searchPath:root];
}

- (NSString *)pyenvAt:(NSString *)root pythonVersion:(NSString *)pythonVersion {
    return [self executableNamed:@"python3" atPyenvRoot:root pythonVersion:pythonVersion searchPath:root];
}

- (NSString *)pathToStandardPyenvPythonWithPythonVersion:(NSString *)pythonVersion {
    return [self pyenvAt:[self pathToStandardPyenvWithVersion:pythonVersion
                                      creatingSymlinkIfNeeded:NO]
           pythonVersion:pythonVersion];
}

- (NSString *)pathToStandardPyenvWithVersion:(NSString *)pythonVersion
                           creatingSymlinkIfNeeded:(BOOL)createSymlink {
    NSString *appsupport;
    if (createSymlink) {
        appsupport = [[NSFileManager defaultManager] spacelessAppSupportCreatingLink];
    } else {
        appsupport = [[NSFileManager defaultManager] spacelessAppSupportWithoutCreatingLink];
    }
    if (pythonVersion) {
        return [appsupport stringByAppendingPathComponent:[NSString stringWithFormat:@"iterm2env-%@", pythonVersion]];
    } else {
        return [appsupport stringByAppendingPathComponent:@"iterm2env"];
    }
}

- (NSURL *)pathToMetadataWithPythonVersion:(NSString *)pythonVersion {
    NSString *path = [self pathToStandardPyenvWithVersion:pythonVersion creatingSymlinkIfNeeded:NO];
    if (!path) {
        return nil;
    }
    path = [path stringByAppendingPathComponent:@"iterm2env-metadata.json"];
    return [NSURL fileURLWithPath:path];
}

// Parent directory of standard pyenv folder
- (NSURL *)urlOfStandardEnvironmentContainerCreatingSymlinkForVersion:(NSString *)pythonVersion {
    NSString *path = [self pathToStandardPyenvWithVersion:pythonVersion creatingSymlinkIfNeeded:YES];
    path = [path stringByDeletingLastPathComponent];
    return [NSURL fileURLWithPath:path];
}

- (BOOL)shouldDownloadEnvironmentForPythonVersion:(NSString *)pythonVersion
                        minimumEnvironmentVersion:(NSInteger)minimumEnvironmentVersion {
    return ([self installedVersionWithPythonVersion:pythonVersion] < MAX(minimumEnvironmentVersion, iTermMinimumPythonEnvironmentVersion));
}

- (BOOL)isPythonRuntimeInstalled {
    if (![[NSFileManager defaultManager] homeDirectoryDotDir]) {
        return NO;
    }
    return ![self shouldDownloadEnvironmentForPythonVersion:nil
                                  minimumEnvironmentVersion:0];
}

- (int)versionInMetadataAtURL:(NSURL *)metadataURL {
    if (!metadataURL) {
        return 0;
    }
    NSData *data = [NSData dataWithContentsOfURL:metadataURL];
    if (!data) {
        return 0;
    }

    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (!dict) {
        return 0;
    }

    NSNumber *version = dict[@"version"];
    if (!version) {
        return 0;
    }

    return version.intValue;
}

// Returns 0 if no version is installed, otherwise returns the installed version of the python runtime.
- (int)installedVersionWithPythonVersion:(NSString *)pythonVersion {
    return [self versionInMetadataAtURL:[self pathToMetadataWithPythonVersion:pythonVersion]];
}

- (void)upgradeIfPossible {
    const int installedVersion = [self installedVersionWithPythonVersion:nil];
    if (installedVersion == 0) {
        return;
    }
    if (![[NSFileManager defaultManager] homeDirectoryDotDir]) {
        return;
    }

    [self checkForNewerVersionThan:installedVersion
                          silently:YES
                           confirm:YES
                requiredToContinue:NO
                     pythonVersion:nil
               latestFullComponent:@(installedVersion)];
}

- (void)performPeriodicUpgradeCheck {
    if (!_checkForUpdateRateLimit) {
        const NSTimeInterval day = 24 * 60 * 60;
        _checkForUpdateRateLimit = [[iTermPersistentRateLimitedUpdate alloc] initWithName:@"CheckForUpdatedPythonRuntime"
                                                                          minimumInterval:2 * day];
    }
    if (![[NSFileManager defaultManager] homeDirectoryDotDir]) {
        return;
    }
    [_checkForUpdateRateLimit performRateLimitedBlock:^{
        DLog(@"Called");
        [self upgradeIfPossible];
    }];
}

- (void)userRequestedCheckForUpdate {
    if (![[NSFileManager defaultManager] homeDirectoryDotDir]) {
        return;
    }
    const int installedVersion = [self installedVersionWithPythonVersion:nil];
    [self checkForNewerVersionThan:installedVersion
                          silently:NO
                           confirm:YES
                requiredToContinue:NO
                     pythonVersion:nil
               latestFullComponent:@(installedVersion)];
}

- (void)downloadOptionalComponentsIfNeededWithConfirmation:(BOOL)confirm
                                             pythonVersion:(NSString *)pythonVersion
                                 minimumEnvironmentVersion:(NSInteger)minimumEnvironmentVersion
                                        requiredToContinue:(BOOL)requiredToContinue
                                            withCompletion:(void (^)(iTermPythonRuntimeDownloaderStatus))completion {
    DLog(@"confirm=%@ pythonVersion=%@ minimumEnvironmentVersion=%@ requiredToContinue=%@",
         @(confirm), pythonVersion, @(minimumEnvironmentVersion), @(requiredToContinue));
    if (![self shouldDownloadEnvironmentForPythonVersion:pythonVersion
                               minimumEnvironmentVersion:minimumEnvironmentVersion]) {
        DLog(@"Don't need it");
        [self performPeriodicUpgradeCheck];
        completion(iTermPythonRuntimeDownloaderStatusNotNeeded);
        return;
    }

    const int installedVersion = [self installedVersionWithPythonVersion:pythonVersion];
    [self checkForNewerVersionThan:MAX(minimumEnvironmentVersion - 1, installedVersion)
                          silently:YES
                           confirm:confirm
                requiredToContinue:requiredToContinue
                     pythonVersion:pythonVersion
               latestFullComponent:installedVersion ? @(installedVersion) : nil];
    dispatch_group_notify(self->_downloadGroup, dispatch_get_main_queue(), ^{
        completion(self->_status);
    });
}

- (void)unzip:(NSURL *)zipFileURL to:(NSURL *)destination completion:(void (^)(NSError *))completion {
    DLog(@"zipFileURL=%@ destination=%@", zipFileURL, destination);

    // This serializes unzips so only one can happen at a time.
    dispatch_async(_queue, ^{
        NSError *error = nil;
        DLog(@"mkdir %@", destination.path);
        [[NSFileManager defaultManager] createDirectoryAtPath:destination.path
                                  withIntermediateDirectories:NO
                                                   attributes:nil
                                                        error:&error];
        if (error) {
            DLog(@"failed %@", error);
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(error);
            });
            return;
        }
        [iTermCommandRunner unzipURL:zipFileURL
                       withArguments:@[ @"-o", @"-q" ]
                         destination:destination.path
                       callbackQueue:dispatch_get_main_queue()
                          completion:^(NSError *error) {
            DLog(@"%@", error);
            completion(error);
        }];
    });
}

- (void)checkForNewerVersionThan:(int)installedVersion
                        silently:(BOOL)silent
                         confirm:(BOOL)confirm
              requiredToContinue:(BOOL)requiredToContinue
                   pythonVersion:(NSString *)pythonVersion
             latestFullComponent:(NSNumber *)latestFullComponent {
    DLog(@"installedVersion=%@ silent=%@ confirm=%@ requiredToContinue=%@ pythonVersion=%@ latestFullComponent=%@",
         @(installedVersion), @(silent), @(confirm), @(requiredToContinue), pythonVersion, latestFullComponent);
    if (_status == iTermPythonRuntimeDownloaderStatusWorking) {
        DLog(@"Already existed and had a current phase");
        [[_downloadController window] makeKeyAndOrderFront:nil];
        return;
    }

    _status = iTermPythonRuntimeDownloaderStatusWorking;
    _downloadGroup = dispatch_group_create();
    __block dispatch_group_t group = _downloadGroup;
    dispatch_group_enter(_downloadGroup);
    if (_downloadController.isWindowLoaded) {
        [_downloadController.window close];
    }
    _downloadController = [[iTermOptionalComponentDownloadWindowController alloc] initWithWindowNibName:@"iTermOptionalComponentDownloadWindowController"];
    __block BOOL declined = NO;
    __block BOOL raiseOnCompletion = (!silent || !confirm);
    NSURL *url;
#if BETA
    url = [NSURL URLWithString:[iTermAdvancedSettingsModel pythonRuntimeBetaDownloadURL]];
#else
    if ([iTermPreferences boolForKey:kPreferenceKeyCheckForTestReleases]) {
        url = [NSURL URLWithString:[iTermAdvancedSettingsModel pythonRuntimeBetaDownloadURL]];
    } else {
        url = [NSURL URLWithString:[iTermAdvancedSettingsModel pythonRuntimeDownloadURL]];
    }
#endif
    __weak __typeof(self) weakSelf = self;
    __block BOOL stillNeedsConfirmation = confirm;
    iTermManifestDownloadPhase *manifestPhase =
    [[iTermManifestDownloadPhase alloc] initWithURL:url
                             requestedPythonVersion:pythonVersion
                                   nextPhaseFactory:
     ^iTermOptionalComponentDownloadPhase *(iTermOptionalComponentDownloadPhase *currentPhase) {
        DLog(@"Begin manifest phase");
        iTermPythonRuntimeDownloader *strongSelf = weakSelf;
        if (!strongSelf) {
            DLog(@"self dealloced");
            return nil;
        }
        iTermManifestDownloadPhase *mphase = [iTermManifestDownloadPhase castFrom:currentPhase];
        if (mphase.version <= installedVersion) {
            DLog(@"mphase gave version %@ but I have %@", @(mphase.version), @(installedVersion));
            strongSelf->_status = iTermPythonRuntimeDownloaderStatusRequestedVersionNotFound;
            if (group) {
                dispatch_group_leave(group);
                group = nil;
            }
            return nil;
        }
        iTermDownloadableComponentInfo *const info = [mphase infoGivenExistingFullComponent:latestFullComponent];
        if (stillNeedsConfirmation) {
            DLog(@"Request confirmation from user with alert box");
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Download Python Runtime?";
            if (requiredToContinue) {
                alert.informativeText = [NSString stringWithFormat:@"The Python Runtime is used by Python scripts that work with iTerm2. It must be downloaded to complete the requested action. The download is about %@. OK to download it now?", [NSString it_formatBytes:info.size]];
            } else {
                alert.informativeText = [NSString stringWithFormat:@"The Python Runtime is used by Python scripts that work with iTerm2. The download is about %@. OK to download it now?", [NSString it_formatBytes:info.size]];
            }
            [alert addButtonWithTitle:silent ? @"Download" : @"OK"];
            [alert addButtonWithTitle:@"Cancel"];
            if ([alert runModal] == NSAlertSecondButtonReturn) {
                DLog(@"Canceled by user");
                declined = YES;
                if (group) {
                    dispatch_group_leave(group);
                    group = nil;
                }
                strongSelf->_status = iTermPythonRuntimeDownloaderStatusCanceledByUser;
                return nil;
            }
            stillNeedsConfirmation = NO;
        }
        if (silent) {
            [strongSelf->_downloadController.window makeKeyAndOrderFront:nil];
            raiseOnCompletion = YES;
        }
        DLog(@"Return download phase");
        return [[iTermPayloadDownloadPhase alloc] initWithURL:info.URL
                                                      version:mphase.version
                                            expectedSignature:info.signature
                                       requestedPythonVersion:mphase.requestedPythonVersion
                                             expectedVersions:mphase.pythonVersionsInArchive
                                             nextPhaseFactory:^iTermOptionalComponentDownloadPhase *(iTermOptionalComponentDownloadPhase *completedPhase) {
            DLog(@"Download phase completed");
            const BOOL shouldContinue = [weakSelf payloadDownloadPhaseDidComplete:(iTermPayloadDownloadPhase *)completedPhase
                                                                 sitePackagesOnly:info.isSitePackagesOnly
                                                              latestFullComponent:latestFullComponent];
            if (!shouldContinue) {
                return nil;
            }
            return [[iTermInstallingPhase alloc] initWithURL:nil title:@"Download Finished" nextPhaseFactory:nil];
        }];
    }];
    _downloadController.completion = ^(iTermOptionalComponentDownloadPhase *lastPhase) {
        if (lastPhase.error) {
            [weakSelf showDownloadFailedAlertWithError:lastPhase.error
                                         pythonVersion:pythonVersion
                                    requiredToContinue:requiredToContinue];

            if (group) {
                dispatch_group_leave(group);
                group = nil;
            }
            return;
        }
        if (lastPhase == manifestPhase) {
            iTermPythonRuntimeDownloader *strongSelf = weakSelf;
            [strongSelf didStopCheckAfterReceivingManifestBecauseDeclined:declined
                                                        raiseOnCompletion:raiseOnCompletion];
        }
    };
    if (!silent) {
        [_downloadController.window makeKeyAndOrderFront:nil];
    }
    [_downloadController beginPhase:manifestPhase];
}

- (void)didStopCheckAfterReceivingManifestBecauseDeclined:(BOOL)declined
                                        raiseOnCompletion:(BOOL)raiseOnCompletion {
    if (declined) {
        _status = iTermPythonRuntimeDownloaderStatusCanceledByUser;
        [_downloadController close];
        return;
    }
    if (_status == iTermPythonRuntimeDownloaderStatusWorking) {
        // You can get here when the manifest download completes and it decides not to keep going,
        // for example if the requested version was not available.
        _status = iTermPythonRuntimeDownloaderStatusNotNeeded;
    }
    [_downloadController showMessage:@"✅ The Python runtime is up to date."];
    if (raiseOnCompletion) {
        [_downloadController.window makeKeyAndOrderFront:nil];
    }
}

- (BOOL)showDownloadFailedAlertWithError:(NSError *)error
                           pythonVersion:(NSString *)pythonVersion
                      requiredToContinue:(BOOL)requiredToContinue {
    NSAlert *alert = [[NSAlert alloc] init];

    NSString *reason;
    if (error.code == -999 && [error.domain isEqualToString:@"com.iterm2"]) {
        if (!requiredToContinue) {
            [_downloadController close];
            return YES;
        }
        _status = iTermPythonRuntimeDownloaderStatusCanceledByUser;
        alert.messageText = @"Download Canceled";
        reason = @"";
    } else {
        _status = iTermPythonRuntimeDownloaderStatusError;
        alert.messageText = @"Python Runtime Unavailable";
        reason = [NSString stringWithFormat:@"\n\nThe download failed: %@", error.localizedDescription];
    }

    if (pythonVersion) {
        alert.informativeText = [NSString stringWithFormat:@"An iTerm2 Python Runtime with Python version %@ must be downloaded to proceed.%@",
                                 pythonVersion, reason];
    } else {
        alert.informativeText = [NSString stringWithFormat:@"An iTerm2 Python Runtime must be downloaded to proceed.%@",
                                 reason];
    }
    [alert runModal];
    return NO;
}

- (BOOL)payloadDownloadPhaseDidComplete:(iTermPayloadDownloadPhase *)payloadPhase
                       sitePackagesOnly:(BOOL)sitePackagesOnly
                    latestFullComponent:(NSNumber *)latestFullComponent {
    DLog(@"sitePackagesOnly=%@ latestFullComponent=%@", @(sitePackagesOnly), latestFullComponent);

    if (!payloadPhase || payloadPhase.error) {
        DLog(@"Download failed");
        [_downloadController.window makeKeyAndOrderFront:nil];
        [[iTermNotificationController sharedInstance] notify:@"Download failed ☹️"];
        _status = iTermPythonRuntimeDownloaderStatusError;
        dispatch_group_leave(self->_downloadGroup);
        return NO;
    }
    NSString *tempfile = [[NSWorkspace sharedWorkspace] temporaryFileNameWithPrefix:@"iterm2-pyenv" suffix:@".zip"];
    const BOOL ok = [self writeInputStream:payloadPhase.stream toFile:tempfile];
    if (!ok) {
        DLog(@"Failed to write to %@", tempfile);
        [[iTermNotificationController sharedInstance] notify:@"Could not extract archive ☹️"];
        _status = iTermPythonRuntimeDownloaderStatusError;
        dispatch_group_leave(self->_downloadGroup);
        return NO;
    }

    NSURL *tempURL = [NSURL fileURLWithPath:tempfile isDirectory:NO];
    NSString *pubkey = [NSString stringWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"rsa_pub" withExtension:@"pem"]
                                                encoding:NSUTF8StringEncoding
                                                   error:nil];
    NSError *verifyError = [iTermSignatureVerifier validateFileURL:tempURL withEncodedSignature:payloadPhase.expectedSignature publicKey:pubkey];
    if (verifyError) {
        DLog(@"Signature validation failed");
        [[NSFileManager defaultManager] removeItemAtPath:tempfile error:nil];
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Signature Verification Failed";
        alert.informativeText = [NSString stringWithFormat:@"The Python runtime's signature failed validation: %@", verifyError.localizedDescription];
        [alert runModal];
        _status = iTermPythonRuntimeDownloaderStatusError;
        [self->_downloadController.window close];
        self->_downloadController = nil;
        dispatch_group_leave(self->_downloadGroup);
    } else {
        DLog(@"Signature OK");
        void (^completion)(NSError *) = ^(NSError *error){
            if (!error) {
                [[NSNotificationCenter defaultCenter] postNotificationName:iTermPythonRuntimeDownloaderDidInstallRuntimeNotification object:nil];
                [[iTermNotificationController sharedInstance] notify:@"Download finished!"];
                [self->_downloadController.window close];
                self->_downloadController = nil;
                self->_status = iTermPythonRuntimeDownloaderStatusDownloaded;
                dispatch_group_leave(self->_downloadGroup);
                return;
            }
            [self->_downloadController.window close];
            self->_downloadController = nil;
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Error unzipping python environment";
            alert.informativeText = error.localizedDescription ?: @"An error occurred while unzipping the downloaded python environment";
            [alert runModal];
            self->_status = iTermPythonRuntimeDownloaderStatusError;
            dispatch_group_leave(self->_downloadGroup);
        };
        if (sitePackagesOnly) {
            DLog(@"Installing site packages only");
            [self installSitePackagesFromZip:tempfile
                              runtimeVersion:payloadPhase.version
                              pythonVersions:payloadPhase.expectedVersions
                         latestFullComponent:latestFullComponent.integerValue
                                  completion:completion];
        } else {
            DLog(@"Installing environment");
            [self installPythonEnvironmentFromZip:tempfile
                                   runtimeVersion:payloadPhase.version
                                   pythonVersions:payloadPhase.expectedVersions
                                       completion:completion];
        }
    }
    return YES;
}

+ (NSArray<NSString *> *)pythonVersionsAt:(NSString *)path {
    NSDirectoryEnumerator *enumerator = [NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:path]
                                                           includingPropertiesForKeys:nil
                                                                              options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
                                                                         errorHandler:nil];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (NSURL *url in enumerator) {
        NSString *file = url.path.lastPathComponent;
        NSArray<NSString *> *parts = [file componentsSeparatedByString:@"."];
        const BOOL allNumeric = [parts allWithBlock:^BOOL(NSString *anObject) {
            return [anObject isNumeric];
        }];
        if (allNumeric) {
            [result addObject:file];
        }
    }
    return result;
}

+ (NSString *)bestPythonVersionAt:(NSString *)path {
    // TODO: This is convenient but I'm not sure it's technically correct for all possible Python
    // versions. But it'll do for three dotted numbers, which is the norm.
    SUStandardVersionComparator *comparator = [[SUStandardVersionComparator alloc] init];
    NSArray<NSString *> *versions = [self pythonVersionsAt:path];
    return [versions maxWithComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [comparator compareVersion:a toVersion:b];
    }];
}

+ (NSString *)latestPythonVersion {
    NSArray<NSString *> *components = @[ @"iterm2env", @"versions" ];
    NSString *path = [[NSFileManager defaultManager] spacelessAppSupportCreatingLink];
    for (NSString *part in components) {
        path = [path stringByAppendingPathComponent:part];
    }
    return [self bestPythonVersionAt:path];
}

- (NSSet<NSString *> *)twoPartPythonVersionsInRuntimeVersion:(NSInteger)pythonVersion {
    NSString *const path = [self pathToStandardPyenvWithVersion:[@(pythonVersion) stringValue]
                                        creatingSymlinkIfNeeded:NO];
    NSString *versionsPath = [path stringByAppendingPathComponent:@"versions"];
    NSArray<NSString *> *versions = [iTermPythonRuntimeDownloader pythonVersionsAt:versionsPath];
    NSArray<NSString *> *twoPartVersions = iTermConvertThreePartVersionNumbersToTwoPart(versions);
    return [NSSet setWithArray:twoPartVersions];
}

- (void)installSitePackagesFromZip:(NSString *)zip
                    runtimeVersion:(int)runtimeVersion
                    pythonVersions:(NSArray<NSString *> *)pythonVersions
               latestFullComponent:(NSInteger)latestFullComponent
                        completion:(void (^)(NSError *))completion {
    DLog(@"zip=%@ runtimeVersion=%@ pythonVersions=%@ latestFullComponent=%@",
         zip, @(runtimeVersion), pythonVersions, @(latestFullComponent));
    NSURL *const finalDestination =
    [NSURL fileURLWithPath:[self pathToStandardPyenvWithVersion:[@(runtimeVersion) stringValue]
                                        creatingSymlinkIfNeeded:YES]];
    NSURL *const tempDestination =
    [NSURL fileURLWithPath:[[[NSFileManager defaultManager] spacelessAppSupportCreatingLink] stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]]];

    NSURL *const sourceURL =
    [NSURL fileURLWithPath:[self pathToStandardPyenvWithVersion:[@(latestFullComponent) stringValue]
                                        creatingSymlinkIfNeeded:NO]];
    [[NSFileManager defaultManager] removeItemAtPath:finalDestination.path error:nil];
    NSURL *overwritableURL = [tempDestination URLByAppendingPathComponent:@"iterm2env"];
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:tempDestination.path withIntermediateDirectories:YES attributes:nil error:&error];
    if (error) {
        DLog(@"Failed to create %@: %@", tempDestination, error);
        completion(error);
        return;
    }
    [self copyFullEnvironmentFrom:sourceURL
                               to:overwritableURL
                       completion:^(NSError *error) {
        if (error) {
            DLog(@"failed with %@", error);
            completion(error);
            return;
        }
        NSString *searchFor1 = [NSString stringWithFormat:@"/iterm2env-%@/", @(latestFullComponent)];
        NSString *replaceWith1 = [NSString stringWithFormat:@"/iterm2env-%@/", @(runtimeVersion)];
        NSString *searchFor2 = [NSString stringWithFormat:@"/iterm2env-%@\"", @(latestFullComponent)];
        NSString *replaceWith2 = [NSString stringWithFormat:@"/iterm2env-%@\"", @(runtimeVersion)];
        NSDictionary<NSString *, NSString *> *subs =
            @{ searchFor1: replaceWith1,
               searchFor2: replaceWith2 } ;
        [self performSubstitutions:subs inFilesUnderFolder:tempDestination];
        [self unzip:[NSURL fileURLWithPath:zip] to:tempDestination completion:^(NSError *error) {
            if (error) {
                DLog(@"Failed with %@", error);
                completion(error);
                return;
            }
            [self finishInstallingRuntimeVersion:runtimeVersion
                                  pythonVersions:pythonVersions
                                 tempDestination:tempDestination
                                finalDestination:finalDestination
                                      completion:completion];
        }];
    }];
}

- (void)copyFullEnvironmentFrom:(NSURL *)source
                             to:(NSURL *)destination
                     completion:(void (^)(NSError *))completion {
    DLog(@"source=%@ destinatino=%@", source, destination);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        [[NSFileManager defaultManager] copyItemAtURL:source
                                                toURL:destination
                                                error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            DLog(@"Finished with error=%@", error);
            completion(error);
        });
    });
}

- (int)runtimeVersionFromFilename:(NSString *)filename {
    NSString *name = [[filename lastPathComponent] stringByDeletingPathExtension];
    NSScanner *scanner = [[NSScanner alloc] initWithString:name];
    if (![scanner scanString:@"iterm2env-" intoString:nil]) {
        return -1;
    }
    int version = -1;
    if (![scanner scanInt:&version]) {
        return -1;
    }
    return version;
}

- (void)installPythonEnvironmentFromZip:(NSString *)zip completion:(void (^)(NSError *))completion {
    DLog(@"zip=%@", zip);
    const int runtimeVersion = [self runtimeVersionFromFilename:zip];
    if (runtimeVersion < 0) {
        completion([NSError errorWithDomain:@"com.googlecode.iterm2"
                                       code:-1
                                   userInfo:@{ NSLocalizedDescriptionKey: @"Invalid filename. Expected `iterm2env-<version>.zip`."}]);
        return;
    }
    [self installPythonEnvironmentFromZip:zip
                           runtimeVersion:runtimeVersion
                           pythonVersions:nil
                               completion:completion];

}

- (NSArray<NSString *> *)discoveredPythonVersionsAt:(NSString *)base {
    NSURL *url = [NSURL fileURLWithPath:[base stringByAppendingPathComponents:@[ @"iterm2env", @"versions" ]]];
    NSDirectoryEnumerator *enumerator = [NSFileManager.defaultManager enumeratorAtURL:url
                                                           includingPropertiesForKeys:nil
                                                                              options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
                                                                         errorHandler:nil];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (NSURL *url in enumerator) {
        if (![[NSFileManager defaultManager] itemIsDirectory:url.path]) {
            continue;
        }
        [result addObject:url.lastPathComponent];
    }
    return result;
}

- (void)installPythonEnvironmentFromZip:(NSString *)zip
                         runtimeVersion:(int)runtimeVersion
                         pythonVersions:(NSArray<NSString *> *)pythonVersions
                             completion:(void (^)(NSError *))completion {
    DLog(@"zip=%@ runtimeVersion=%@ pythonVersions=%@", zip, @(runtimeVersion), pythonVersions);
    NSURL *finalDestination = [NSURL fileURLWithPath:[self pathToStandardPyenvWithVersion:[@(runtimeVersion) stringValue]
                                                                  creatingSymlinkIfNeeded:YES]];
    NSURL *tempDestination = [NSURL fileURLWithPath:[[[NSFileManager defaultManager] spacelessAppSupportCreatingLink] stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]]];

    [[NSFileManager defaultManager] removeItemAtPath:finalDestination.path error:nil];
    [self unzip:[NSURL fileURLWithPath:zip] to:tempDestination completion:^(NSError *error) {
        DLog(@"unzip done error=%@", error);;
        if (!error) {
            NSDictionary<NSString *, NSString *> *subs = @{ @"__ITERM2_ENV__": finalDestination.path,
                                                            @"__ITERM2_PYENV__": [finalDestination.path stringByAppendingPathComponent:@"pyenv"] };
            DLog(@"perform subs");
            [self performSubstitutions:subs inFilesUnderFolder:tempDestination];
            DLog(@"finish installing");
            [self finishInstallingRuntimeVersion:runtimeVersion
                                  pythonVersions:pythonVersions ?: [self discoveredPythonVersionsAt:tempDestination.path]
                                 tempDestination:tempDestination
                                finalDestination:finalDestination
                                      completion:completion];
        } else {
            completion(error);
        }
    }];
}

static NSArray<NSString *> *iTermConvertThreePartVersionNumbersToTwoPart(NSArray<NSString *> *pythonVersions) {
    return [pythonVersions mapWithBlock:^id(NSString *possibleThreePart) {
        NSArray<NSString *> *parts = [possibleThreePart componentsSeparatedByString:@"."];
        if (parts.count == 3) {
            return [[parts subarrayToIndex:2] componentsJoinedByString:@"."];
        } else {
            return nil;
        }
    }];
}

- (void)finishInstallingRuntimeVersion:(int)runtimeVersion
                        pythonVersions:(NSArray<NSString *> *)pythonVersions
                       tempDestination:(NSURL *)tempDestination
                      finalDestination:(NSURL *)finalDestination
                            completion:(void (^)(NSError *))completion {
    DLog(@"runtimeVersion=%@ pythonVersions=%@ tempDestination=%@ finalDestination=%@",
         @(runtimeVersion), pythonVersions, tempDestination, finalDestination);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray<NSString *> *twoPartVersions = iTermConvertThreePartVersionNumbersToTwoPart(pythonVersions);
        NSArray<NSString *> *extendedPythonVersions = [NSSet setWithArray:[pythonVersions arrayByAddingObjectsFromArray:twoPartVersions]].allObjects;
        [self createDeepLinksTo:[tempDestination.path stringByAppendingPathComponent:@"iterm2env"]
                 runtimeVersion:runtimeVersion
                    forVersions:extendedPythonVersions];
        [self createDeepLinkTo:[tempDestination.path stringByAppendingPathComponent:@"iterm2env"]
                 pythonVersion:nil
                runtimeVersion:runtimeVersion];
        NSError *error = nil;
        DLog(@"Move %@ to %@", [tempDestination URLByAppendingPathComponent:@"iterm2env"], finalDestination);
        [[NSFileManager defaultManager] moveItemAtURL:[tempDestination URLByAppendingPathComponent:@"iterm2env"]
                                                toURL:finalDestination
                                                error:&error];
        if (error) {
            DLog(@"Move failed with error=%@", error);
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(error);
            });
            return;
        }
        // Delete older versions that have the same Python versions.
        NSSet<NSString *> *versionsToRemove = [NSSet setWithArray:twoPartVersions];
        DLog(@"versionsToRemove=%@", versionsToRemove);
        for (int i = 1; i < runtimeVersion; i++) {
            NSSet<NSString *> *pythonVersionsInOldRuntime = [self twoPartPythonVersionsInRuntimeVersion:i];
            if (![pythonVersionsInOldRuntime isSubsetOfSet:versionsToRemove]) {
                // There’s at least one python version in the old runtime that isn’t in the new one
                // so keep it around.
                continue;
            }
            NSError *error = nil;
            DLog(@"Remove %@", [self pathToStandardPyenvWithVersion:[@(i) stringValue]
                                            creatingSymlinkIfNeeded:NO]);
            [[NSFileManager defaultManager] removeItemAtPath:[self pathToStandardPyenvWithVersion:[@(i) stringValue]
                                                                          creatingSymlinkIfNeeded:NO]
                                                       error:&error];
            if (error) {
                DLog(@"%@", error);
            }
        }

        DLog(@"rm temp destination %@", tempDestination);
        [[NSFileManager defaultManager] removeItemAtURL:tempDestination error:&error];
        DLog(@"%@", error);
        dispatch_async(dispatch_get_main_queue(), ^{
            DLog(@"Done");
            completion(nil);
        });
    });
}

- (void)createDeepLinkTo:(NSString *)container pythonVersion:(NSString *)pythonVersion runtimeVersion:(int)runtimeVersion {
    const int existingVersion = [self installedVersionWithPythonVersion:pythonVersion];
    if (runtimeVersion > existingVersion) {
        NSString *pathToVersionedEnvironment = [self pathToStandardPyenvWithVersion:pythonVersion
                                                            creatingSymlinkIfNeeded:NO];
        [[NSFileManager defaultManager] removeItemAtPath:pathToVersionedEnvironment
                                                   error:nil];
        NSError *error = nil;
        DLog(@"Will link %@ to %@", container, pathToVersionedEnvironment);
        [[NSFileManager defaultManager] linkItemAtPath:container
                                                toPath:pathToVersionedEnvironment
                                                 error:&error];
        DLog(@"Done linking error=%@", error);
    }
}

- (void)createDeepLinksTo:(NSString *)container
           runtimeVersion:(int)runtimeVersion
              forVersions:(NSArray<NSString *> *)pythonVersions {
    DLog(@"container=%@ runtimeVersion=%@", container, @(runtimeVersion));
    for (NSString *pythonVersion in pythonVersions) {
        DLog(@"Begin linking %@", pythonVersion);
        [self createDeepLinkTo:container pythonVersion:pythonVersion runtimeVersion:runtimeVersion];
    }
    DLog(@"Done");
}

- (BOOL)busy {
    return _busy > 0;
}

- (void)installPythonEnvironmentTo:(NSURL *)folder
                      dependencies:(NSArray<NSString *> *)dependencies
                     pythonVersion:(nullable NSString *)pythonVersion
                        completion:(void (^)(BOOL ok))completion {
    DLog(@"Begin folder=%@ dependencies=%@ pythonVersion=%@", folder, dependencies, pythonVersion);
    iTermBuildingScriptWindowController *pleaseWait = [iTermBuildingScriptWindowController newPleaseWaitWindowController];
    id token = [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidBecomeActiveNotification
                                                                 object:nil
                                                                  queue:nil
                                                             usingBlock:^(NSNotification * _Nonnull note) {
                                                                 [pleaseWait.window makeKeyAndOrderFront:nil];
                                                             }];
    _busy++;
    [[iTermPythonRuntimeDownloader sharedInstance] installPythonEnvironmentTo:folder
                                                             eventualLocation:folder
                                                                pythonVersion:pythonVersion
                                                           environmentVersion:[[iTermPythonRuntimeDownloader sharedInstance] installedVersionWithPythonVersion:pythonVersion]
                                                                 dependencies:dependencies
                                                               createSetupCfg:YES
                                                                   completion:
     ^(iTermInstallPythonStatus status) {
         [[NSNotificationCenter defaultCenter] removeObserver:token];
         [pleaseWait.window close];
        self->_busy--;
        completion(status == iTermInstallPythonStatusOK);
    }];
}

- (void)installPythonEnvironmentTo:(NSURL *)container
                  eventualLocation:(NSURL *)eventualLocation
                     pythonVersion:(NSString *)pythonVersion
                environmentVersion:(NSInteger)environmentVersion
                      dependencies:(NSArray<NSString *> *)dependencies
                    createSetupCfg:(BOOL)createSetupCfg
                        completion:(void (^)(iTermInstallPythonStatus))completion {
    DLog(@"Begin. container=%@ eventualLocation=%@ pythonVersion=%@ environmentVersion=%@ dependencies=%@ createSetupCfg=%@",
         container, eventualLocation, pythonVersion, @(environmentVersion), dependencies, @(createSetupCfg));
    NSString *source = [self pathToStandardPyenvWithVersion:pythonVersion
                                    creatingSymlinkIfNeeded:NO];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        DLog(@"On bg queue");
        NSError *error = nil;
        NSString *destination = [container URLByAppendingPathComponent:@"iterm2env"].path;
        BOOL ok;
        DLog(@"mkdir %@", container.path);
        ok = [[NSFileManager defaultManager] createDirectoryAtPath:container.path
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:&error];
        if (!ok) {
            XLog(@"Failed to create %@: %@", container, error);
        }

        DLog(@"Will create hard links at %@ to %@", source, destination);
        ok = [[NSFileManager defaultManager] linkItemAtPath:source
                                                     toPath:destination
                                                      error:&error];
        DLog(@"Done creating hard links. error=%@", error);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ok) {
                XLog(@"Failed to link %@ to %@: %@", source, destination, error);
                completion(iTermInstallPythonStatusGeneralFailure);
                return;
            }

            // pip3 must use the python in this environment so it will install new dependencies to the right place.
            NSString *const pathToEnvironment = [container.path stringByAppendingPathComponent:@"iterm2env"];
            NSString *const pip3 = [self pip3At:pathToEnvironment pythonVersion:pythonVersion];
            NSString *const pathToPython = [self executableNamed:@"python3"
                                                     atPyenvRoot:[eventualLocation.path stringByAppendingPathComponent:@"iterm2env"]
                                                   pythonVersion:pythonVersion
                                                      searchPath:source];


            // Replace the shebang in pip3 to point at the right version of python.
            [self replaceShebangInScriptAtPath:pip3 with:[NSString stringWithFormat:@"#!%@", pathToPython]];

            [self installDependencies:dependencies to:container pythonVersion:pythonVersion completion:^(NSArray<NSString *> *failures, NSArray<NSData *> *outputs) {
                DLog(@"Dependency installation finished with these failures: %@", failures);
                if (failures.count) {
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = @"Dependency Installation Failed";
                    NSString *failureList = [[failures sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "];
                    alert.informativeText = [NSString stringWithFormat:@"The following dependencies failed to install: %@", failureList];

                    NSMutableArray<NSString *> *messages = [NSMutableArray array];
                    for (NSInteger i = 0; i < failures.count; i++) {
                        NSData *output = outputs[i];
                        NSString *stringOutput = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
                        if (!stringOutput) {
                            stringOutput = [[NSString alloc] initWithData:output encoding:NSISOLatin1StringEncoding];
                        }
                        [messages addObject:[NSString stringWithFormat:@"%@\n%@", failures[i], stringOutput]];
                    }
                    iTermDisclosableView *accessory = [[iTermDisclosableView alloc] initWithFrame:NSZeroRect
                                                                                           prompt:@"Output"
                                                                                          message:[messages componentsJoinedByString:@"\n\n"]];
                    accessory.frame = NSMakeRect(0, 0, accessory.intrinsicContentSize.width, accessory.intrinsicContentSize.height);
                    accessory.textView.selectable = YES;
                    accessory.requestLayout = ^{
                        [alert layout];
                        if (@available(macOS 10.16, *)) {
                            // FB8897296:
                            // Prior to Big Sur, you could call [NSAlert layout] on an already-visible NSAlert
                            // to have it change its size to accommodate an accessory view controller whose
                            // frame changed.
                            //
                            // On Big Sur, it no longer works. Instead, you must call NSAlert.layout *twice*.
                            [alert layout];
                        }
                    };
                    alert.accessoryView = accessory;

                    [alert runModal];
                    completion(iTermInstallPythonStatusDependencyFailed);
                    return;
                }

                NSString *pythonVersionToUse = pythonVersion ?: [self.class latestPythonVersion];
                if (!pythonVersionToUse) {
                    DLog(@"Could not determine Python version");
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = @"Could not determine Python version";
                    alert.informativeText = @"Please file an issue report.";
                    [alert runModal];
                    completion(iTermInstallPythonStatusGeneralFailure);
                    return;
                }
                if (createSetupCfg) {
                    [iTermSetupCfgParser writeSetupCfgToFile:[container.path stringByAppendingPathComponent:@"setup.cfg"]
                                                        name:container.path.lastPathComponent
                                                dependencies:dependencies
                                         ensureiTerm2Present:YES
                                               pythonVersion:pythonVersionToUse
                                          environmentVersion:environmentVersion];
                }
                completion(iTermInstallPythonStatusOK);
            }];
        });
    });
}

- (void)replaceShebangInScriptAtPath:(NSString *)scriptPath with:(NSString *)newShebang {
    DLog(@"scriptPath=%@ newShebang=%@", scriptPath, newShebang);
    NSError *error = nil;
    NSString *script = [NSString stringWithContentsOfFile:scriptPath encoding:NSUTF8StringEncoding error:&error];
    if (!script) {
        DLog(@"Failed to replace shebang in %@ because I couldn't read the file contents: %@", scriptPath, error);
        return;
    }
    NSMutableArray<NSString *> *lines = [[script componentsSeparatedByString:@"\n"] mutableCopy];
    if (lines.count == 0) {
        DLog(@"Empty script at %@", scriptPath);
        return;
    }
    if (![lines.firstObject hasPrefix:@"#!/"]) {
        DLog(@"First line of %@ is not a shebang: %@", scriptPath, lines.firstObject);
        return;
    }
    const BOOL unlinkedOk = [[NSFileManager defaultManager] removeItemAtPath:scriptPath error:&error];
    if (!unlinkedOk) {
        DLog(@"Failed to unlink %@: %@", scriptPath, error);
        return;
    }
    lines[0] = newShebang;
    NSString *fixedScript = [lines componentsJoinedByString:@"\n"];
    const BOOL ok = [fixedScript writeToFile:scriptPath atomically:NO encoding:NSUTF8StringEncoding error:&error];
    if (!ok) {
        DLog(@"Write to %@ failed: %@", scriptPath, error);
    }
    const BOOL chmodOk = [[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: @(0755) }
                                                          ofItemAtPath:scriptPath
                                                                 error:&error];
    if (!chmodOk) {
        DLog(@"Failed to chmod 0755 %@: %@", scriptPath, error);
    }

}

- (void)installDependencies:(NSArray<NSString *> *)dependencies
                         to:(NSURL *)container
              pythonVersion:(NSString *)pythonVersion
                 completion:(void (^)(NSArray<NSString *> *failures,
                                      NSArray<NSData *> *outputs))completion {
    DLog(@"dependencies=%@ container=%@ pythonVersion=%@", dependencies, container, pythonVersion);
    if (dependencies.count == 0) {
        DLog(@"No more deps");
        completion(@[], @[]);
        return;
    }
    [self runPip3InContainer:container
               pythonVersion:pythonVersion
               withArguments:@[ @"install", dependencies.firstObject ]
                  completion:^(BOOL thisOK, NSData *output) {
                      if (!thisOK) {
                          DLog(@"Running pip3 failed so don't install dependencies");
                          completion(@[ dependencies.firstObject ], @[ output ?: [NSData data] ]);
                          return;
                      }
                      [self installDependencies:[dependencies subarrayFromIndex:1]
                                             to:container
                                  pythonVersion:pythonVersion
                                     completion:^(NSArray<NSString *> *failures,
                                                  NSArray<NSData *> *outputs) {
                                         if (!thisOK) {
                                             completion([failures arrayByAddingObject:dependencies.firstObject],
                                                        [outputs arrayByAddingObject:output]);
                                         } else {
                                             completion(failures, outputs);
                                         }
                                     }];
                  }];
}

- (void)runPip3InContainer:(NSURL *)container
             pythonVersion:(NSString *)pythonVersion
             withArguments:(NSArray<NSString *> *)arguments
                completion:(void (^)(BOOL ok, NSData *output))completion {
    DLog(@"container=%@ pythonVersion=%@ arguments=%@", container, pythonVersion, arguments);
    NSString *pip3 = [self pip3At:[container.path stringByAppendingPathComponent:@"iterm2env"]
                    pythonVersion:pythonVersion];
    if (!pip3) {
        DLog(@"pip3 not found");
        completion(NO, [[NSString stringWithFormat:@"pip3 not found for python version %@ in %@", pythonVersion, container.path] dataUsingEncoding:NSUTF8StringEncoding]);
        return;
    }
    NSMutableData *output = [NSMutableData data];
    iTermCommandRunner *runner = [[iTermCommandRunner alloc] initWithCommand:pip3
                                                               withArguments:arguments
                                                                        path:container.path];
    NSString *identifier = [runner description];
    runner.outputHandler = ^(NSData *data, void (^completion)(void)) {
        DLog(@"Runner %@ recvd: %@", identifier, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
        [output appendData:data];
        completion();
    };
    runner.completion = ^(int status) {
        if (status != 0) {
            DLog(@"Runner %@ FAILED with %@", identifier, [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding]);
        }
        completion(status == 0, output);
    };
    DLog(@"Runner %@ running pip3 %@", runner, arguments);
    [runner run];
}

- (BOOL)writeInputStream:(NSInputStream *)inputStream toFile:(NSString *)destination {
    NSOutputStream *outputStream = [NSOutputStream outputStreamToFileAtPath:destination append:NO];
    [outputStream open];
    NSMutableData *buffer = [NSMutableData dataWithLength:4096];
    BOOL ok = NO;
    while (YES) {
        NSInteger n = [inputStream read:buffer.mutableBytes maxLength:buffer.length];
        if (n < 0) {
            break;
        }
        if (n == 0) {
            ok = YES;
            break;
        }
        if ([outputStream write:buffer.mutableBytes maxLength:n] != n) {
            break;
        }
    }
    [outputStream close];
    [inputStream close];
    return ok;
}

- (void)performSubstitutions:(NSDictionary *)subs inFilesUnderFolder:(NSURL *)folderURL {
    DLog(@"subs=%@ folderURL=%@", subs, folderURL);
    NSMutableDictionary *dataSubs = [NSMutableDictionary dictionary];
    [subs enumerateKeysAndObjectsUsingBlock:^(NSString *  _Nonnull key, NSString *  _Nonnull obj, BOOL * _Nonnull stop) {
        NSData *dataKey = [key dataUsingEncoding:NSUTF8StringEncoding];
        NSData *valueKey = [obj dataUsingEncoding:NSUTF8StringEncoding];
        dataSubs[dataKey] = valueKey;
    }];
    NSDirectoryEnumerator *directoryEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:folderURL.path];
    for (NSString *file in directoryEnumerator) {
        [self performSubstitutions:dataSubs inFile:[folderURL.path stringByAppendingPathComponent:file]];
    }
    DLog(@"Done");
}

- (void)performSubstitutions:(NSDictionary *)subs inFile:(NSString *)path {
    DLog(@"Perform subs in %@", path);
    NSMutableData *data = [NSMutableData dataWithContentsOfFile:path];
    [subs enumerateKeysAndObjectsUsingBlock:^(NSData * _Nonnull key, NSData * _Nonnull obj, BOOL * _Nonnull stop) {
        const NSInteger count = [data it_replaceOccurrencesOfData:key withData:obj];
        if (count) {
            [data writeToFile:path atomically:NO];
        }
    }];
}

@end
