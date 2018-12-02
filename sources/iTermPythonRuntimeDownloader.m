//
//  iTermPythonRuntimeDownloader.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/28/18.
//

#import "iTermPythonRuntimeDownloader.h"

#import "iTermAdvancedSettingsModel.h"
#import "iTermCommandRunner.h"
#import "iTermDisclosableView.h"
#import "iTermNotificationController.h"
#import "iTermOptionalComponentDownloadWindowController.h"
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

- (NSString *)executableNamed:(NSString *)name atPyenvRoot:(NSString *)root {
    NSString *path = [root stringByAppendingPathComponent:@"versions"];
    for (NSString *version in [[NSFileManager defaultManager] enumeratorAtPath:path]) {
        if ([version hasPrefix:@"3."]) {
            path = [path stringByAppendingPathComponent:version];
            path = [path stringByAppendingPathComponent:@"bin"];
            path = [path stringByAppendingPathComponent:name];
            return path;
        }
    }
    return nil;
}

- (NSString *)pip3At:(NSString *)root {
    return [self executableNamed:@"pip3" atPyenvRoot:root];
}

- (NSString *)pyenvAt:(NSString *)root {
    return [self executableNamed:@"python3" atPyenvRoot:root];
}

- (NSString *)pathToStandardPyenvPythonWithPythonVersion:(NSString *)pythonVersion {
    return [self pyenvAt:[self pathToStandardPyenvWithVersion:pythonVersion
                                      creatingSymlinkIfNeeded:NO]];
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

- (void)userRequestedCheckForUpdate {
    [self checkForNewerVersionThan:[self installedVersionWithPythonVersion:nil]
                          silently:NO
                           confirm:YES
                requiredToContinue:NO
                     pythonVersion:nil];
}

- (void)downloadOptionalComponentsIfNeededWithConfirmation:(BOOL)confirm
                                             pythonVersion:(NSString *)pythonVersion
                                            withCompletion:(void (^)(BOOL))completion {
    if (![self shouldDownloadEnvironmentForPythonVersion:pythonVersion]) {
        completion(YES);
        return;
    }

    [self checkForNewerVersionThan:[self installedVersionWithPythonVersion:pythonVersion]
                          silently:YES
                           confirm:confirm
                requiredToContinue:YES
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
                    alert.informativeText = @"The Python Runtime is used by Python scripts that work with iTerm2. The download is about 29 MB. OK to download it now?";
                }
                [alert addButtonWithTitle:@"OK"];
                [alert addButtonWithTitle:@"Cancel"];
                if ([alert runModal] == NSAlertSecondButtonReturn) {
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
                                                 expectedVersions:mphase.pythonVersionsInArchive];
        }];
        _downloadController.completion = ^(iTermOptionalComponentDownloadPhase *lastPhase) {
            if (lastPhase.error) {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"Python Runtime Unavailable";
                if (pythonVersion) {
                    alert.informativeText = [NSString stringWithFormat:@"An iTerm2 Python Runtime with Python version %@ must be downloaded to proceed. The download failed: %@",
                                             pythonVersion, lastPhase.error.localizedDescription];
                } else {
                    alert.informativeText = [NSString stringWithFormat:@"An iTerm2 Python Runtime must be downloaded to proceed. The download failed: %@",
                                             lastPhase.error.localizedDescription];
                }
                [alert runModal];
                return;
            }
            if (lastPhase == manifestPhase) {
                iTermPythonRuntimeDownloader *strongSelf = weakSelf;
                if (strongSelf) {
                    [strongSelf->_downloadController showMessage:@"✅ The Python runtime is up to date."];
                    if (raiseOnCompletion) {
                        [strongSelf->_downloadController.window makeKeyAndOrderFront:nil];
                    }
                }
            } else {
                [weakSelf downloadDidCompleteWithFinalPhase:lastPhase];
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

- (void)downloadDidCompleteWithFinalPhase:(iTermOptionalComponentDownloadPhase *)lastPhase {
    iTermPayloadDownloadPhase *payloadPhase = [iTermPayloadDownloadPhase castFrom:lastPhase];
    if (!payloadPhase || payloadPhase.error) {
        [_downloadController.window makeKeyAndOrderFront:nil];
        [[iTermNotificationController sharedInstance] notify:@"Download failed ☹️"];
        return;
    }
    NSString *tempfile = [[NSWorkspace sharedWorkspace] temporaryFileNameWithPrefix:@"iterm2-pyenv" suffix:@".zip"];
    const BOOL ok = [self writeInputStream:payloadPhase.stream toFile:tempfile];
    if (!ok) {
        [[iTermNotificationController sharedInstance] notify:@"Could not extract archive ☹️"];
        return;
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
}

+ (NSString *)bestPythonVersionAt:(NSString *)path {
    // TODO: This is convenient but I'm not sure it's technically correct for all possible Python
    // versions. But it'll do for three dotted numbers, which is the norm.
    SUStandardVersionComparator *comparator = [[SUStandardVersionComparator alloc] init];
    NSString *best = nil;
    NSDirectoryEnumerator *enumerator = [NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:path]
                                                           includingPropertiesForKeys:nil
                                                                              options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
                                                                         errorHandler:nil];
    for (NSURL *url in enumerator) {
        NSString *file = url.path.lastPathComponent;
        NSArray<NSString *> *parts = [file componentsSeparatedByString:@"."];
        const BOOL allNumeric = [parts allWithBlock:^BOOL(NSString *anObject) {
            return [anObject isNumeric];
        }];
        if (allNumeric) {
            if (!best || [comparator compareVersion:best toVersion:file] == NSOrderedAscending) {
                best = file;
            }
        }
    }
    return best;
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
                     pythonVersion:(NSString *)pythonVersion
                      dependencies:(NSArray<NSString *> *)dependencies
                     createSetupPy:(BOOL)createSetupPy
                        completion:(void (^)(BOOL))completion {
    NSString *source = [self pathToStandardPyenvWithVersion:pythonVersion
                                    creatingSymlinkIfNeeded:NO];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        const BOOL ok = [[NSFileManager defaultManager] linkItemAtPath:source
                                                                toPath:[container URLByAppendingPathComponent:@"iterm2env"].path
                                                                 error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ok) {
                completion(NO);
                return;
            }

            [self installDependencies:dependencies to:container completion:^(NSArray<NSString *> *failures, NSArray<NSData *> *outputs) {
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
                                             pythonVersion:pythonVersionToUse];
                }
                completion(YES);
            }];
        });
    });
}

- (void)installDependencies:(NSArray<NSString *> *)dependencies
                         to:(NSURL *)container
                 completion:(void (^)(NSArray<NSString *> *failures,
                                      NSArray<NSData *> *outputs))completion {
    if (dependencies.count == 0) {
        completion(@[], @[]);
        return;
    }
    [self runPip3InContainer:container
               withArguments:@[ @"install", dependencies.firstObject ]
                  completion:^(BOOL thisOK, NSData *output) {
                      [self installDependencies:[dependencies subarrayFromIndex:1]
                                             to:container
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

- (void)runPip3InContainer:(NSURL *)container withArguments:(NSArray<NSString *> *)arguments completion:(void (^)(BOOL ok, NSData *output))completion {
    NSString *pip3 = [self pip3At:[container.path stringByAppendingPathComponent:@"iterm2env"]];
    NSMutableData *output = [NSMutableData data];
    iTermCommandRunner *runner = [[iTermCommandRunner alloc] initWithCommand:pip3
                                                               withArguments:arguments
                                                                        path:container.path];
    runner.outputHandler = ^(NSData *data) {
        [output appendData:data];
    };
    runner.completion = ^(int status) {
        completion(status == 0, output);
    };
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
