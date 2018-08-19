//
//  iTermPythonRuntimeDownloader.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/28/18.
//

#import "iTermPythonRuntimeDownloader.h"

#import "iTermCommandRunner.h"
#import "iTermDisclosableView.h"
#import "iTermNotificationController.h"
#import "iTermOptionalComponentDownloadWindowController.h"
#import "iTermSignatureVerifier.h"
#import "NSArray+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSMutableData+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSWorkspace+iTerm.h"

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

- (NSString *)pathToStandardPyenvPython {
    return [self pyenvAt:[self pathToStandardPyenvCreatingSymlinkIfNeeded:NO]];
}

- (NSString *)pathToStandardPyenvCreatingSymlinkIfNeeded:(BOOL)createSymlink {
    NSString *appsupport;
    if (createSymlink) {
        appsupport = [[NSFileManager defaultManager] applicationSupportDirectoryWithoutSpaces];
    } else {
        appsupport = [[NSFileManager defaultManager] applicationSupportDirectoryWithoutSpacesWithoutCreatingSymlink];
    }
    return [appsupport stringByAppendingPathComponent:@"iterm2env"];
}

- (NSURL *)pathToMetadata {
    NSString *path = [self pathToStandardPyenvCreatingSymlinkIfNeeded:NO];
    path = [path stringByAppendingPathComponent:@"iterm2env-metadata.json"];
    return [NSURL fileURLWithPath:path];
}

- (NSString *)pathToZIP {
    return [[[NSFileManager defaultManager] applicationSupportDirectory] stringByAppendingPathComponent:@"iterm2env-current.zip"];
}

// Parent directory of standard pyenv folder
- (NSURL *)urlOfStandardEnvironmentContainerCreatingSymlink {
    NSString *path = [self pathToStandardPyenvCreatingSymlinkIfNeeded:YES];
    path = [path stringByDeletingLastPathComponent];
    return [NSURL fileURLWithPath:path];
}

- (BOOL)shouldDownloadEnvironment {
    return (self.installedVersion < iTermMinimumPythonEnvironmentVersion);
}

- (BOOL)isPythonRuntimeInstalled {
    return ![self shouldDownloadEnvironment];
}

// Returns 0 if no version is installed, otherwise returns the installed version of the python runtime.
- (int)installedVersion {
    NSData *data = [NSData dataWithContentsOfURL:[self pathToMetadata]];
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
    const int installedVersion = [self installedVersion];
    if (installedVersion == 0) {
        return;
    }

    [self checkForNewerVersionThan:installedVersion silently:YES confirm:YES requiredToContinue:NO];
}

- (void)userRequestedCheckForUpdate {
    [self checkForNewerVersionThan:self.installedVersion silently:NO confirm:YES requiredToContinue:NO];
}

- (void)downloadOptionalComponentsIfNeededWithConfirmation:(BOOL)confirm withCompletion:(void (^)(BOOL))completion {
    if (![self shouldDownloadEnvironment]) {
        completion(YES);
        return;
    }

    [self checkForNewerVersionThan:self.installedVersion silently:YES confirm:confirm requiredToContinue:YES];
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
              requiredToContinue:(BOOL)requiredToContinue {
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
        NSURL *url = [NSURL URLWithString:@"https://iterm2.com/downloads/pyenv/manifest.json"];
        __weak __typeof(self) weakSelf = self;
        __block BOOL stillNeedsConfirmation = confirm;
        iTermManifestDownloadPhase *manifestPhase = [[iTermManifestDownloadPhase alloc] initWithURL:url nextPhaseFactory:^iTermOptionalComponentDownloadPhase *(iTermOptionalComponentDownloadPhase *currentPhase) {
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
                                                expectedSignature:mphase.signature];
        }];
        _downloadController.completion = ^(iTermOptionalComponentDownloadPhase *lastPhase) {
            if (lastPhase.error) {
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
        NSString *zip = [self pathToZIP];
        [[NSFileManager defaultManager] removeItemAtPath:zip error:nil];
        [[NSFileManager defaultManager] moveItemAtPath:tempfile toPath:zip error:nil];
        NSURL *container = [self urlOfStandardEnvironmentContainerCreatingSymlink];
        [self installPythonEnvironmentTo:container dependencies:nil completion:^(BOOL ok) {
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

- (void)writeSetupPyToFile:(NSString *)file name:(NSString *)name dependencies:(NSArray<NSString *> *)dependencies {
    NSArray<NSString *> *quotedDependencies = [dependencies mapWithBlock:^id(NSString *anObject) {
        return [NSString stringWithFormat:@"'%@'", anObject];
    }];
    NSString *contents = [NSString stringWithFormat:
                          @"from setuptools import setup\n"
                          @"# WARNING: install_requires must be on one line and contain only quoted strings.\n"
                          @"#          This protects the security of users installing the script.\n"
                          @"#          The script import feature will fail if you try to get fancy.\n"
                          @"setup(name='%@',\n"
                          @"      version='1.0',\n"
                          @"      scripts=['%@/%@.py'],\n"
                          @"      install_requires=['iterm2',%@]\n"
                          @"      )",
                          name,
                          name,
                          name,
                          [quotedDependencies componentsJoinedByString:@", "]];
    [contents writeToFile:file atomically:NO encoding:NSUTF8StringEncoding error:nil];
}

- (void)installPythonEnvironmentTo:(NSURL *)container dependencies:(NSArray<NSString *> *)dependencies completion:(void (^)(BOOL))completion {
    NSString *zip = [self pathToZIP];
    [self unzip:[NSURL fileURLWithPath:zip] to:container completion:^(BOOL unzipOk) {
        if (unzipOk) {
            NSURL *pyenv = [container URLByAppendingPathComponent:@"iterm2env"];
            NSDictionary<NSString *, NSString *> *subs = @{ @"__ITERM2_ENV__": pyenv.path,
                                                            @"__ITERM2_PYENV__": [pyenv.path stringByAppendingPathComponent:@"pyenv"] };
            [self performSubstitutions:subs inFilesUnderFolder:pyenv];
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
                [self writeSetupPyToFile:[container.path stringByAppendingPathComponent:@"setup.py"]
                                    name:container.path.lastPathComponent
                            dependencies:dependencies];
                completion(YES);
            }];
        } else {
            completion(NO);
        }
    }];
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
