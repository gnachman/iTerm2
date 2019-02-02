//
//  iTermPythonRuntimeDownloader.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/28/18.
//

#import "iTermPythonRuntimeDownloader.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermCommandRunner.h"
#import "iTermDisclosableView.h"
#import "iTermNotificationController.h"
#import "iTermOptionalComponentDownloadWindowController.h"
#import "iTermRateLimitedUpdate.h"
#import "iTermSetupPyParser.h"
#import "iTermSignatureVerifier.h"
#import "NSArray+iTerm.h"
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
    BOOL _didDownload;  // Set when _downloadGroup notified.
    dispatch_queue_t _queue;  // Used to serialize installs
    iTermPersistentRateLimitedUpdate *_checkForUpdateRateLimit;
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
        appsupport = [[NSFileManager defaultManager] applicationSupportDirectoryWithoutSpaces];
    } else {
        appsupport = [[NSFileManager defaultManager] applicationSupportDirectoryWithoutSpacesWithoutCreatingSymlink];
    }
    if (pythonVersion) {
        return [appsupport stringByAppendingPathComponent:[NSString stringWithFormat:@"iterm2env-%@", pythonVersion]];
    } else {
        return [appsupport stringByAppendingPathComponent:@"iterm2env"];
    }
}

- (NSURL *)pathToMetadataWithPythonVersion:(NSString *)pythonVersion {
    NSString *path = [self pathToStandardPyenvWithVersion:pythonVersion creatingSymlinkIfNeeded:NO];
    path = [path stringByAppendingPathComponent:@"iterm2env-metadata.json"];
    return [NSURL fileURLWithPath:path];
}

// Parent directory of standard pyenv folder
- (NSURL *)urlOfStandardEnvironmentContainerCreatingSymlinkForVersion:(NSString *)pythonVersion {
    NSString *path = [self pathToStandardPyenvWithVersion:pythonVersion creatingSymlinkIfNeeded:YES];
    path = [path stringByDeletingLastPathComponent];
    return [NSURL fileURLWithPath:path];
}

- (BOOL)shouldDownloadEnvironmentForPythonVersion:(NSString *)pythonVersion {
    return ([self installedVersionWithPythonVersion:pythonVersion] < iTermMinimumPythonEnvironmentVersion);
}

- (BOOL)isPythonRuntimeInstalled {
    return ![self shouldDownloadEnvironmentForPythonVersion:nil];
}

// Returns 0 if no version is installed, otherwise returns the installed version of the python runtime.
- (int)installedVersionWithPythonVersion:(NSString *)pythonVersion {
    NSData *data = [NSData dataWithContentsOfURL:[self pathToMetadataWithPythonVersion:pythonVersion]];
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

- (void)upgradeIfPossible {
    const int installedVersion = [self installedVersionWithPythonVersion:nil];
    if (installedVersion == 0) {
        return;
    }

    [self checkForNewerVersionThan:installedVersion silently:YES confirm:YES requiredToContinue:NO pythonVersion:nil];
}

- (void)performPeriodicUpgradeCheck {
    if (!_checkForUpdateRateLimit) {
        _checkForUpdateRateLimit = [[iTermPersistentRateLimitedUpdate alloc] initWithName:@"CheckForUpdatedPythonRuntime"];
        const NSTimeInterval day = 24 * 60 * 60;
        _checkForUpdateRateLimit.minimumInterval = 2 * day;
    }
    [_checkForUpdateRateLimit performRateLimitedBlock:^{
        [self upgradeIfPossible];
    }];
}

- (void)userRequestedCheckForUpdate {
    [self checkForNewerVersionThan:[self installedVersionWithPythonVersion:nil]
                          silently:NO
                           confirm:YES
                requiredToContinue:NO
                     pythonVersion:nil];
}

- (void)downloadOptionalComponentsIfNeededWithConfirmation:(BOOL)confirm
                                             pythonVersion:(NSString *)pythonVersion
                                        requiredToContinue:(BOOL)requiredToContinue
                                            withCompletion:(void (^)(BOOL))completion {
    if (![self shouldDownloadEnvironmentForPythonVersion:pythonVersion]) {
        [self performPeriodicUpgradeCheck];
        completion(YES);
        return;
    }

    [self checkForNewerVersionThan:[self installedVersionWithPythonVersion:pythonVersion]
                          silently:YES
                           confirm:confirm
                requiredToContinue:requiredToContinue
                     pythonVersion:pythonVersion];
    dispatch_group_notify(self->_downloadGroup, dispatch_get_main_queue(), ^{
        completion(self->_didDownload);
    });
}

- (void)unzip:(NSURL *)zipFileURL to:(NSURL *)destination completion:(void (^)(BOOL))completion {
    // This serializes unzips so only one can happen at a time.
    dispatch_async(_queue, ^{
        [[NSFileManager defaultManager] createDirectoryAtPath:destination.path
                                  withIntermediateDirectories:NO
                                                   attributes:nil
                                                        error:NULL];
        [iTermCommandRunner unzipURL:zipFileURL
                       withArguments:@[ @"-o", @"-q" ]
                         destination:destination.path
                          completion:^(BOOL ok) {
            completion(ok);
        }];
    });
}

- (void)checkForNewerVersionThan:(int)installedVersion
                        silently:(BOOL)silent
                         confirm:(BOOL)confirm
              requiredToContinue:(BOOL)requiredToContinue
                   pythonVersion:(NSString *)pythonVersion {
    BOOL shouldBeginDownload = NO;
    if (!_downloadController) {
        _downloadGroup = dispatch_group_create();
        dispatch_group_enter(_downloadGroup);
        _downloadController = [[iTermOptionalComponentDownloadWindowController alloc] initWithWindowNibName:@"iTermOptionalComponentDownloadWindowController"];
        shouldBeginDownload = YES;
    } else if (!_downloadController.currentPhase) {
        shouldBeginDownload = YES;
    }

    if (shouldBeginDownload) {
        __block BOOL declined = NO;
        __block BOOL raiseOnCompletion = (!silent || !confirm);
        NSURL *url = [NSURL URLWithString:[iTermAdvancedSettingsModel pythonRuntimeDownloadURL]];
        __weak __typeof(self) weakSelf = self;
        __block BOOL stillNeedsConfirmation = confirm;
        iTermManifestDownloadPhase *manifestPhase = [[iTermManifestDownloadPhase alloc] initWithURL:url
                                                                             requestedPythonVersion:pythonVersion
                                                                                   nextPhaseFactory:^iTermOptionalComponentDownloadPhase *(iTermOptionalComponentDownloadPhase *currentPhase) {
            iTermPythonRuntimeDownloader *strongSelf = weakSelf;
            if (!strongSelf) {
                return nil;
            }
            iTermManifestDownloadPhase *mphase = [iTermManifestDownloadPhase castFrom:currentPhase];
            if (mphase.version <= installedVersion) {
                return nil;
            }
            if (stillNeedsConfirmation) {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"Download Python Runtime?";
                if (requiredToContinue) {
                    alert.informativeText = @"The Python Runtime is used by Python scripts that work with iTerm2. It must be downloaded to complete the requested action. The download is about 29 MB. OK to download it now?";
                } else {
                    alert.informativeText = @"The Python Runtime is used by Python scripts that work with iTerm2. The download is about 30 MB. OK to download it now?";
                }
                [alert addButtonWithTitle:silent ? @"Download" : @"OK"];
                [alert addButtonWithTitle:@"Cancel"];
                if ([alert runModal] == NSAlertSecondButtonReturn) {
                    declined = YES;
                    return nil;
                }
                stillNeedsConfirmation = NO;
            }
            if (silent) {
                [strongSelf->_downloadController.window makeKeyAndOrderFront:nil];
                raiseOnCompletion = YES;
            }
            return [[iTermPayloadDownloadPhase alloc] initWithURL:mphase.nextURL
                                                          version:mphase.version
                                                expectedSignature:mphase.signature
                                           requestedPythonVersion:mphase.requestedPythonVersion
                                                 expectedVersions:mphase.pythonVersionsInArchive
                                                 nextPhaseFactory:^iTermOptionalComponentDownloadPhase *(iTermOptionalComponentDownloadPhase *completedPhase) {
                                                     const BOOL shouldContinue = [weakSelf payloadDownloadPhaseDidComplete:(iTermPayloadDownloadPhase *)completedPhase];
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
    } else if (_downloadController.isWindowLoaded && !_downloadController.window.visible) {
        // Already existed and had a current phase.
        [[_downloadController window] makeKeyAndOrderFront:nil];
    }
}

- (void)didStopCheckAfterReceivingManifestBecauseDeclined:(BOOL)declined
                                        raiseOnCompletion:(BOOL)raiseOnCompletion {
    if (declined) {
        [_downloadController close];
        return;
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
        alert.messageText = @"Download Canceled";
        reason = @"";
    } else {
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

- (BOOL)payloadDownloadPhaseDidComplete:(iTermPayloadDownloadPhase *)payloadPhase {
    if (!payloadPhase || payloadPhase.error) {
        [_downloadController.window makeKeyAndOrderFront:nil];
        [[iTermNotificationController sharedInstance] notify:@"Download failed ☹️"];
        return NO;
    }
    NSString *tempfile = [[NSWorkspace sharedWorkspace] temporaryFileNameWithPrefix:@"iterm2-pyenv" suffix:@".zip"];
    const BOOL ok = [self writeInputStream:payloadPhase.stream toFile:tempfile];
    if (!ok) {
        [[iTermNotificationController sharedInstance] notify:@"Could not extract archive ☹️"];
        return NO;
    }

    NSURL *tempURL = [NSURL fileURLWithPath:tempfile isDirectory:NO];
    NSString *pubkey = [NSString stringWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"rsa_pub" withExtension:@"pem"]
                                                encoding:NSUTF8StringEncoding
                                                   error:nil];
    NSError *verifyError = [iTermSignatureVerifier validateFileURL:tempURL withEncodedSignature:payloadPhase.expectedSignature publicKey:pubkey];
    if (verifyError) {
        [[NSFileManager defaultManager] removeItemAtPath:tempfile error:nil];
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Signature Verification Failed";
        alert.informativeText = [NSString stringWithFormat:@"The Python runtime's signature failed validation: %@", verifyError.localizedDescription];
        [alert runModal];
    } else {
        [self installPythonEnvironmentFromZip:tempfile
                               runtimeVersion:payloadPhase.version
                               pythonVersions:payloadPhase.expectedVersions
                                   completion:
         ^(BOOL ok) {
             if (ok) {
                 [[NSNotificationCenter defaultCenter] postNotificationName:iTermPythonRuntimeDownloaderDidInstallRuntimeNotification object:nil];
                 [[iTermNotificationController sharedInstance] notify:@"Download finished!"];
                 [self->_downloadController.window close];
                 self->_downloadController = nil;
                 self->_didDownload = ok;
                 dispatch_group_leave(self->_downloadGroup);
             } else {
                 NSAlert *alert = [[NSAlert alloc] init];
                 alert.messageText = @"Error unzipping python environment";
                 alert.informativeText = @"An error occurred while unzipping the downloaded python environment";
                 [alert runModal];
             }
         }];
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
    NSString *path = [[NSFileManager defaultManager] applicationSupportDirectoryWithoutSpaces];
    for (NSString *part in components) {
        path = [path stringByAppendingPathComponent:part];
    }
    return [self bestPythonVersionAt:path];
}

- (void)installPythonEnvironmentFromZip:(NSString *)zip
                         runtimeVersion:(int)runtimeVersion
                         pythonVersions:(NSArray<NSString *> *)pythonVersions
                             completion:(void (^)(BOOL))completion {
    NSURL *finalDestination = [NSURL fileURLWithPath:[self pathToStandardPyenvWithVersion:[@(runtimeVersion) stringValue]
                                                                  creatingSymlinkIfNeeded:YES]];
    NSURL *tempDestination = [NSURL fileURLWithPath:[[[NSFileManager defaultManager] applicationSupportDirectoryWithoutSpaces] stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]]];

    [[NSFileManager defaultManager] removeItemAtPath:finalDestination.path error:nil];
    [self unzip:[NSURL fileURLWithPath:zip] to:tempDestination completion:^(BOOL unzipOk) {
        if (unzipOk) {
            NSDictionary<NSString *, NSString *> *subs = @{ @"__ITERM2_ENV__": finalDestination.path,
                                                            @"__ITERM2_PYENV__": [finalDestination.path stringByAppendingPathComponent:@"pyenv"] };
            [self performSubstitutions:subs inFilesUnderFolder:tempDestination];
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSArray<NSString *> *twoPartVersions = [pythonVersions mapWithBlock:^id(NSString *possibleThreePart) {
                    NSArray<NSString *> *parts = [possibleThreePart componentsSeparatedByString:@"."];
                    if (parts.count == 3) {
                        return [[parts subarrayToIndex:2] componentsJoinedByString:@"."];
                    } else {
                        return nil;
                    }
                }];
                NSArray<NSString *> *extendedPythonVersions = [NSSet setWithArray:[pythonVersions arrayByAddingObjectsFromArray:twoPartVersions]].allObjects;
                [self createDeepLinksTo:[tempDestination.path stringByAppendingPathComponent:@"iterm2env"]
                         runtimeVersion:runtimeVersion
                            forVersions:extendedPythonVersions];
                [self createDeepLinkTo:[tempDestination.path stringByAppendingPathComponent:@"iterm2env"]
                         pythonVersion:nil
                        runtimeVersion:runtimeVersion];
                [[NSFileManager defaultManager] moveItemAtURL:[tempDestination URLByAppendingPathComponent:@"iterm2env"]
                                                        toURL:finalDestination
                                                        error:nil];
                // Delete older versions
                for (int i = 1; i < runtimeVersion; i++) {
                    [[NSFileManager defaultManager] removeItemAtPath:[self pathToStandardPyenvWithVersion:[@(i) stringValue]
                                                                                  creatingSymlinkIfNeeded:NO]
                                                               error:nil];
                }
                [[NSFileManager defaultManager] removeItemAtURL:tempDestination error:nil];
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(YES);
                });
            });
        } else {
            completion(NO);
        }
    }];
}

- (void)createDeepLinkTo:(NSString *)container pythonVersion:(NSString *)pythonVersion runtimeVersion:(int)runtimeVersion {
    const int existingVersion = [self installedVersionWithPythonVersion:pythonVersion];
    if (runtimeVersion > existingVersion) {
        NSString *pathToVersionedEnvironment = [self pathToStandardPyenvWithVersion:pythonVersion
                                                            creatingSymlinkIfNeeded:NO];
        [[NSFileManager defaultManager] removeItemAtPath:pathToVersionedEnvironment
                                                   error:nil];
        NSError *error = nil;
        [[NSFileManager defaultManager] linkItemAtPath:container
                                                toPath:pathToVersionedEnvironment
                                                 error:&error];
    }
}

- (void)createDeepLinksTo:(NSString *)container
           runtimeVersion:(int)runtimeVersion
              forVersions:(NSArray<NSString *> *)pythonVersions {
    for (NSString *pythonVersion in pythonVersions) {
        [self createDeepLinkTo:container pythonVersion:pythonVersion runtimeVersion:runtimeVersion];
    }
}

- (void)installPythonEnvironmentTo:(NSURL *)container
                  eventualLocation:(NSURL *)eventualLocation
                     pythonVersion:(NSString *)pythonVersion
                      dependencies:(NSArray<NSString *> *)dependencies
                     createSetupPy:(BOOL)createSetupPy
                        completion:(void (^)(BOOL))completion {
    NSString *source = [self pathToStandardPyenvWithVersion:pythonVersion
                                    creatingSymlinkIfNeeded:NO];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        NSString *destination = [container URLByAppendingPathComponent:@"iterm2env"].path;
        BOOL ok;
        ok = [[NSFileManager defaultManager] createDirectoryAtPath:container.path
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:&error];
        if (!ok) {
            XLog(@"Failed to create %@: %@", container, error);
        }
        ok = [[NSFileManager defaultManager] linkItemAtPath:source
                                                     toPath:destination
                                                      error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ok) {
                XLog(@"Failed to link %@ to %@: %@", source, destination, error);
                completion(NO);
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
                    };
                    alert.accessoryView = accessory;

                    [alert runModal];
                }

                NSString *pythonVersionToUse = pythonVersion ?: [self.class latestPythonVersion];
                if (!pythonVersionToUse) {
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = @"Could not determine Python version";
                    alert.informativeText = @"Please file an issue report.";
                    [alert runModal];
                    return;
                }
                if (createSetupPy) {
                    [iTermSetupPyParser writeSetupPyToFile:[container.path stringByAppendingPathComponent:@"setup.py"]
                                                      name:container.path.lastPathComponent
                                              dependencies:dependencies
                                       ensureiTerm2Present:YES
                                             pythonVersion:pythonVersionToUse];
                }
                completion(YES);
            }];
        });
    });
}

- (void)replaceShebangInScriptAtPath:(NSString *)scriptPath with:(NSString *)newShebang {
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
    if (dependencies.count == 0) {
        completion(@[], @[]);
        return;
    }
    [self runPip3InContainer:container
               pythonVersion:pythonVersion
               withArguments:@[ @"install", dependencies.firstObject ]
                  completion:^(BOOL thisOK, NSData *output) {
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
    NSString *pip3 = [self pip3At:[container.path stringByAppendingPathComponent:@"iterm2env"]
                    pythonVersion:pythonVersion];
    if (!pip3) {
        completion(NO, [[NSString stringWithFormat:@"pip3 not found for python version %@ in %@", pythonVersion, container.path] dataUsingEncoding:NSUTF8StringEncoding]);
        return;
    }
    NSMutableData *output = [NSMutableData data];
    iTermCommandRunner *runner = [[iTermCommandRunner alloc] initWithCommand:pip3
                                                               withArguments:arguments
                                                                        path:container.path];
    NSString *identifier = [runner description];
    runner.outputHandler = ^(NSData *data) {
        DLog(@"Runner %@ recvd: %@", identifier, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
        [output appendData:data];
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
    NSInteger total = 0;
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
        total += n;
    }
    [outputStream close];
    [inputStream close];
    return ok;
}

- (void)performSubstitutions:(NSDictionary *)subs inFilesUnderFolder:(NSURL *)folderURL {
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
}

- (void)performSubstitutions:(NSDictionary *)subs inFile:(NSString *)path {
    NSMutableData *data = [NSMutableData dataWithContentsOfFile:path];
    [subs enumerateKeysAndObjectsUsingBlock:^(NSData * _Nonnull key, NSData * _Nonnull obj, BOOL * _Nonnull stop) {
        const NSInteger count = [data it_replaceOccurrencesOfData:key withData:obj];
        if (count) {
            [data writeToFile:path atomically:NO];
        }
    }];
}

@end
