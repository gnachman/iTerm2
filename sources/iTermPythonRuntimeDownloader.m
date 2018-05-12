//
//  iTermPythonRuntimeDownloader.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/28/18.
//

#import "iTermPythonRuntimeDownloader.h"

#import "iTermNotificationController.h"
#import "iTermOptionalComponentDownloadWindowController.h"
#import "iTermSignatureVerifier.h"
#import "NSFileManager+iTerm.h"
#import "NSMutableData+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSWorkspace+iTerm.h"

NSString *const iTermPythonRuntimeDownloaderDidInstallRuntimeNotification = @"iTermPythonRuntimeDownloaderDidInstallRuntimeNotification";

@implementation iTermPythonRuntimeDownloader {
    iTermOptionalComponentDownloadWindowController *_downloadController;
    dispatch_group_t _downloadGroup;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (NSString *)pyenvAt:(NSString *)root {
    NSString *path = [root stringByAppendingPathComponent:@"versions"];
    for (NSString *version in [[NSFileManager defaultManager] enumeratorAtPath:path]) {
        if ([version hasPrefix:@"3."]) {
            path = [path stringByAppendingPathComponent:version];
            path = [path stringByAppendingPathComponent:@"bin"];
            path = [path stringByAppendingPathComponent:@"python3"];
            return path;
        }
    }
    return nil;
}

- (NSString *)pathToStandardPyenvPython {
    return [self pyenvAt:[self pathToStandardPyenv]];
}

- (NSString *)pathToStandardPyenv {
    return [[[NSFileManager defaultManager] applicationSupportDirectoryWithoutSpaces] stringByAppendingPathComponent:@"iterm2env"];
}

- (NSURL *)pathToMetadata {
    NSString *path = [self pathToStandardPyenv];
    path = [path stringByAppendingPathComponent:@"iterm2env-metadata.json"];
    return [NSURL fileURLWithPath:path];
}

- (NSString *)pathToZIP {
    return [[[NSFileManager defaultManager] applicationSupportDirectory] stringByAppendingPathComponent:@"iterm2env-current.zip"];
}

// Parent directory of standard pyenv folder
- (NSURL *)urlOfStandardEnvironmentContainer {
    NSString *path = [self pathToStandardPyenv];
    path = [path stringByDeletingLastPathComponent];
    return [NSURL fileURLWithPath:path];
}

- (BOOL)shouldDownloadEnvironment {
    static const NSInteger minimumVersion = 11;
    return (self.installedVersion < minimumVersion);
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

    [self createDownloadControllerIfNeededRequestingVersionGreaterThan:installedVersion];
}

- (void)downloadOptionalComponentsIfNeededWithCompletion:(void (^)(void))completion {
    if (![self shouldDownloadEnvironment]) {
        completion();
        return;
    }

    [self createDownloadControllerIfNeededRequestingVersionGreaterThan:0];

    dispatch_group_notify(_downloadGroup, dispatch_get_main_queue(), ^{
        completion();
    });
}

- (void)unzip:(NSURL *)zipFileURL to:(NSURL *)destination completion:(void (^)(BOOL))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [[NSFileManager defaultManager] createDirectoryAtPath:destination.path
                                  withIntermediateDirectories:NO
                                                   attributes:nil
                                                        error:NULL];


        NSTask *unzipTask = [[NSTask alloc] init];
        NSPipe *pipe = [[NSPipe alloc] init];
        [unzipTask setStandardOutput:pipe];
        [unzipTask setStandardError:pipe];
        unzipTask.launchPath = @"/usr/bin/unzip";
        unzipTask.currentDirectoryPath = destination.path;
        unzipTask.arguments = @[ @"-x", @"-o", @"-q", zipFileURL.path ];
        [unzipTask launch];

        NSFileHandle *readHandle = [pipe fileHandleForReading];
        NSData *inData = [readHandle availableData];
        while (inData.length) {
            NSLog(@"unzip: %@", [[NSString alloc] initWithData:inData encoding:NSUTF8StringEncoding]);
            inData = [readHandle availableData];
        }

        [unzipTask waitUntilExit];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(unzipTask.terminationStatus == 0);
        });
    });
}

- (void)createDownloadControllerIfNeededRequestingVersionGreaterThan:(int)installedVersion {
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
        NSURL *url = [NSURL URLWithString:@"https://iterm2.com/downloads/pyenv/manifest.json"];
        iTermManifestDownloadPhase *manifestPhase = [[iTermManifestDownloadPhase alloc] initWithURL:url
                                                                                   nextPhaseFactory:^iTermOptionalComponentDownloadPhase *(iTermOptionalComponentDownloadPhase *currentPhase) {
                                                                                       iTermManifestDownloadPhase *mphase = [iTermManifestDownloadPhase castFrom:currentPhase];
                                                                                       if (mphase.version > installedVersion) {
                                                                                           return [[iTermPayloadDownloadPhase alloc] initWithURL:mphase.nextURL
                                                                                                                               expectedSignature:mphase.signature];
                                                                                       } else {
                                                                                           return nil;
                                                                                       }
                                                                                   }];
        __weak __typeof(self) weakSelf = self;
        _downloadController.completion = ^(iTermOptionalComponentDownloadPhase *lastPhase) {
            if (lastPhase == manifestPhase) {
                iTermPythonRuntimeDownloader *strongSelf = weakSelf;
                if (strongSelf) {
                    [strongSelf->_downloadController showMessage:@"✅ The Python runtime is up to date."];
                }
            } else {
                [weakSelf downloadDidCompleteWithFinalPhase:lastPhase];
            }
        };
        [_downloadController.window makeKeyAndOrderFront:nil];
        [_downloadController beginPhase:manifestPhase];
        [[iTermNotificationController sharedInstance] notify:@"Downloading Python runtime…"];
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
        NSURL *container = [self urlOfStandardEnvironmentContainer];
        [self installPythonEnvironmentTo:container completion:^(BOOL ok) {
            if (ok) {
                [[NSNotificationCenter defaultCenter] postNotificationName:iTermPythonRuntimeDownloaderDidInstallRuntimeNotification object:nil];
                [[iTermNotificationController sharedInstance] notify:@"Download finished!"];
                [self->_downloadController.window close];
                self->_downloadController = nil;
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

- (void)installPythonEnvironmentTo:(NSURL *)container completion:(void (^)(BOOL))completion {
    NSString *zip = [self pathToZIP];
    [self unzip:[NSURL fileURLWithPath:zip] to:container completion:^(BOOL unzipOk) {
        if (unzipOk) {
            NSURL *pyenv = [container URLByAppendingPathComponent:@"iterm2env"];
            NSDictionary<NSString *, NSString *> *subs = @{ @"__ITERM2_ENV__": pyenv.path,
                                                            @"__ITERM2_PYENV__": [pyenv.path stringByAppendingPathComponent:@"pyenv"] };
            [self performSubstitutions:subs inFilesUnderFolder:pyenv];
            completion(YES);
        } else {
            completion(NO);
        }
    }];
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
