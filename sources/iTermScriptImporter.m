//
//  iTermScriptImporter.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/24/18.
//

#import "iTermScriptImporter.h"

#import "DebugLogging.h"
#import "iTermBuildingScriptWindowController.h"
#import "iTermCommandRunner.h"
#import "iTermScriptArchive.h"
#import "iTermScriptHistory.h"
#import "iTermWarning.h"
#import "NSFileManager+iTerm.h"
#import "NSWorkspace+iTerm.h"
#import "SIGArchiveVerifier.h"
#import "SIGCertificate.h"

static BOOL sInstallingScript;

@implementation iTermScriptImporter

+ (void)importScriptFromURL:(NSURL *)downloadedURL
              userInitiated:(BOOL)userInitiated
            offerAutoLaunch:(BOOL)offerAutoLaunch
              callbackQueue:(dispatch_queue_t)callbackQueue
                    avoidUI:(BOOL)avoidUI
                 completion:(void (^)(NSString *errorMessage, BOOL quiet, NSURL *location))completion {
    DLog(@"dowloadedURL=%@ userInitiated=%@ offerAutoLaunch=%@", downloadedURL, @(userInitiated), @(offerAutoLaunch));
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.iterm2.install-script", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_async(queue, ^{
        dispatch_group_t group = dispatch_group_create();
        dispatch_group_enter(group);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reallyImportScriptFromURL:downloadedURL
                              userInitiated:userInitiated
                            offerAutoLaunch:offerAutoLaunch
                              callbackQueue:callbackQueue
                                    avoidUI:avoidUI
                                 completion:^(NSString *errorMessage, BOOL quiet, NSURL *location) {
                DLog(@"errorMessage=%@ quiet=%@ location=%@", errorMessage, @(quiet), location);
                dispatch_group_leave(group);
                completion(errorMessage, quiet, location);
            }];
        });
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    });
}

+ (void)reallyImportScriptFromURL:(NSURL *)downloadedURL
                    userInitiated:(BOOL)userInitiated
                  offerAutoLaunch:(BOOL)offerAutoLaunch
                    callbackQueue:(dispatch_queue_t)callbackQueue
                          avoidUI:(BOOL)avoidUI                       completion:(void (^)(NSString *errorMessage, BOOL quiet, NSURL *location))completion {
    DLog(@"downloadedURL=%@ userInitiated=%@ offerAutoLauch=%@", downloadedURL, @(userInitiated), @(offerAutoLaunch));
    if (sInstallingScript) {
        DLog(@"already installing");
        completion(@"Another import is in progress. Please try again after it completes.", NO, nil);
        return;
    }

    if ([downloadedURL.pathExtension isEqualToString:@"py"]) {
        NSString *to = [[[NSFileManager defaultManager] scriptsPathWithoutSpaces] stringByAppendingPathComponent:downloadedURL.lastPathComponent];
        DLog(@"ends in .py, just copy it to %@", to);
        NSError *error;
        [[NSFileManager defaultManager] copyItemAtURL:downloadedURL
                                                toURL:[NSURL fileURLWithPath:to]
                                                error:&error];
        DLog(@"%@", error);
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(error.localizedDescription, NO, error ? nil : [NSURL fileURLWithPath:to]);
        });
        return;
    }
    sInstallingScript = YES;
    DLog(@"Will verify and unwrap");
    [self verifyAndUnwrapArchive:downloadedURL requireSignature:!userInitiated completion:^(NSURL *url, NSString *errorMessage, BOOL trusted, BOOL reveal, BOOL quiet) {
        DLog(@"Verify and unwrap done with errorMessage=%@", errorMessage);
        if (errorMessage) {
            completion(errorMessage, quiet, nil);
            sInstallingScript = NO;
            return;
        }

        iTermBuildingScriptWindowController *pleaseWait;
        if (!reveal) {
            DLog(@"Open please wait window");
            pleaseWait = [iTermBuildingScriptWindowController newPleaseWaitWindowController];
            [pleaseWait.window makeKeyAndOrderFront:nil];
        }
        NSString *tempDir = [[NSFileManager defaultManager] it_temporaryDirectory];

        DLog(@"Unzip %@", url);
        [iTermCommandRunner unzipURL:url
                       withArguments:@[ @"-q" ]
                         destination:tempDir
                       callbackQueue:callbackQueue
                          completion:^(NSError *error) {
            DLog(@"Unzip finished with %@", error);
            if (error) {
                [pleaseWait.window close];
                completion([NSString stringWithFormat: @"Could not unzip archive: %@", error.localizedDescription], NO, nil);
                sInstallingScript = NO;
                return;
            }
            [self didUnzipSuccessfullyTo:tempDir
                                 trusted:trusted
                         offerAutoLaunch:offerAutoLaunch
                                  reveal:reveal
                                 avoidUI:avoidUI
                          withCompletion:
             ^(NSString *errorMessage, BOOL quiet, NSURL *location) {
                DLog(@"All done! errorMessage=%@", errorMessage);
                sInstallingScript = NO;
                if (reveal) {
                    completion(errorMessage, errorMessage == nil || quiet, nil);
                    return;
                }
                [self eraseTempDir:tempDir];
                [pleaseWait.window close];
                completion(errorMessage, quiet, location);
            }];
        }];
    }];
}

+ (void)verifyAndUnwrapArchive:(NSURL *)url
              requireSignature:(BOOL)requireSignature
                    completion:(void (^)(NSURL *url, NSString *, BOOL trusted, BOOL reveal, BOOL quiet))completion {
    DLog(@"url=%@ requireSignature=%@", url, @(requireSignature));
    SIGArchiveVerifier *verifier = [[SIGArchiveVerifier alloc] initWithURL:url];
    if ([[url pathExtension] isEqualToString:@"its"]) {
        DLog(@"Is .its");
        if (![verifier smellsLikeSignedArchive:NULL]) {
            DLog(@"Doesn't smell like signed archive");
            completion(nil, @"This script archive is corrupt and cannot be installed.", NO, NO, NO);
            return;
        }
        
        NSURL *zipURL = [NSURL fileURLWithPath:[[NSWorkspace sharedWorkspace] temporaryFileNameWithPrefix:@"script" suffix:@".zip"]];
        DLog(@"Will verify");
        [verifier verifyWithCompletion:^(BOOL ok, NSError * _Nullable error) {
            DLog(@"verify done ok=%@ error=%@", @(ok), error);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self verifierDidComplete:verifier
                              withSuccess:ok
                               payloadURL:zipURL
                         requireSignature:requireSignature
                                    error:error
                               completion:completion];
            });
        }];
        return;
    }
    if (requireSignature) {
        completion(nil, @"This is not a valid iTerm2 script archive.", NO, NO, NO);
        return;
    }
    completion(url, nil, NO, NO, NO);
}

+ (void)verifierDidComplete:(SIGArchiveVerifier *)verifier
                withSuccess:(BOOL)ok
                 payloadURL:(NSURL *)zipURL
           requireSignature:(BOOL)requireSignature
                      error:(NSError *)error
                 completion:(void (^)(NSURL *url, NSString *, BOOL trusted, BOOL reveal, BOOL quiet))completion {
    DLog(@"ok=%@ zipURL=%@ requireSignature=%@", @(ok), zipURL, @(requireSignature));
    if (!ok) {
        DLog(@"Not OK");
        completion(nil, error.localizedDescription ?: @"Unknown error", NO, NO, NO);
        return;
    }
    
    if (requireSignature) {
        NSData *data = [[verifier.reader signingCertificates:nil] firstObject];
        if (!data) {
            DLog(@"No cert data");
            completion(nil, @"Could not find certificate after verficiation (nil data)", NO, NO, NO);
            return;
        }
        SIGCertificate *cert = [[SIGCertificate alloc] initWithData:data];
        if (!cert) {
            DLog(@"Bad data");
            completion(nil, @"Could not find certificate after verficiation (bad data)", NO, NO, NO);
            return;
        }
        [self confirmInstallationOfVerifiedArchive:verifier.reader
                                   withCertificate:cert
                                        completion:^(BOOL ok, BOOL reveal) {
            DLog(@"Confirmation ok=%@ reveal=%@", @(ok), @(reveal));
            if (!ok) {
                DLog(@"Canceled");
                completion(nil, @"Installation canceled by user request.", NO, NO, YES);
                return;
            }
            DLog(@"Will copy payload");
            [self copyPayloadFromVerifier:verifier
                                    toURL:zipURL
                               completion:^(NSURL *URL, NSString *errorString) {
                DLog(@"Done copying payload url=%@ errorString=%@", URL, errorString);
                completion(URL, errorString, YES, reveal, NO);
            }];
        }];
        return;
    }
    [self copyPayloadFromVerifier:verifier
                            toURL:zipURL
                       completion:^(NSURL *URL, NSString *errorString) {
                           completion(URL, errorString, YES, NO, NO);
                       }];
}

+ (void)copyPayloadFromVerifier:(SIGArchiveVerifier *)verifier
                          toURL:(NSURL *)zipURL
                     completion:(void (^)(NSURL *, NSString *))completion {
    NSError *innerError = nil;
    const BOOL ok = [verifier copyPayloadToURL:zipURL error:&innerError];
    if (!ok) {
        completion(nil, innerError.localizedDescription ?: @"Unknown error");
        return;
    }
    completion(zipURL, nil);
}

+ (void)revealPayloadFromVerifier:(SIGArchiveVerifier *)verifier
                           zipURL:(NSURL *)zipURL {

}

+ (void)confirmInstallationOfVerifiedArchive:(SIGArchiveReader *)reader
                             withCertificate:(SIGCertificate *)cert
                                  completion:(void (^)(BOOL ok, BOOL toTemp))completion {
    DLog(@"Confirming");
    NSString *body = [NSString stringWithFormat:@"The signature of ”%@” has been verified. The author is:\n\n%@\n\nWould you like to install it?",
                      reader.url.lastPathComponent,
                      ((cert.name ?: cert.longDescription) ?: @"Unknown")];
    iTermWarningSelection selection = [iTermWarning showWarningWithTitle:body
                                                                 actions:@[ @"OK", @"Cancel", @"Reveal Contents" ]
                                                               accessory:nil
                                                              identifier:nil
                                                             silenceable:kiTermWarningTypePersistent
                                                                 heading:@"Confirm Installation"
                                                                  window:nil];
    completion(selection != kiTermWarningSelection1, selection == kiTermWarningSelection2);
}

+ (void)didUnzipSuccessfullyTo:(NSString *)tempDir
                       trusted:(BOOL)trusted
               offerAutoLaunch:(BOOL)offerAutoLaunch
                        reveal:(BOOL)reveal
                       avoidUI:(BOOL)avoidUI
                withCompletion:(void (^)(NSString *errorMessage, BOOL, NSURL *location))completion {
    if (reveal) {
        DLog(@"Reveal in finder");
        [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:tempDir]];
        completion(nil, NO, nil);
        return;
    }

    BOOL deprecated = NO;
    iTermScriptArchive *archive = [iTermScriptArchive archiveFromContainer:tempDir
                                                                deprecated:&deprecated];
    if (!archive) {
        DLog(@"Failed to extract archive from container");
        if (deprecated) {
            DLog(@"deprecated");
            completion(@"This archive was created by an older version of iTerm2. This kind of archive is no longer supported and cannot be installed.", NO, nil);
        } else {
            DLog(@"invalid");
            completion(@"Archive does not contain a valid iTerm2 script", NO, nil);
        }
        return;
    }

    if ([self haveScriptNamed:archive.name]) {
        DLog(@"Already have a script named %@", archive.name);
        iTermWarningSelection selection = kiTermWarningSelection0;
        if (!avoidUI) {
            selection = [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"A script named “%@” is already installed", archive.name]
                                                   actions:@[ @"Replace Script", @"Cancel" ]
                                                 accessory:nil
                                                identifier:nil
                                               silenceable:kiTermWarningTypePersistent
                                                   heading:@"Script Already Exists"
                                                    window:nil];
        }
        if (selection == kiTermWarningSelection0) {
            DLog(@"Remove and retry");
            [self removeScriptNamed:archive.name];
            [self didUnzipSuccessfullyTo:tempDir
                                 trusted:trusted
                         offerAutoLaunch:offerAutoLaunch
                                  reveal:reveal
                                 avoidUI:avoidUI
                          withCompletion:completion];
            return;
        }
        DLog(@"Give up");
        completion(nil, YES, nil);
        return;
    }

    [archive installTrusted:trusted
            offerAutoLaunch:offerAutoLaunch
                    avoidUI:avoidUI
             withCompletion:^(NSError *error, NSURL *location) {
        DLog(@"Install finished with %@", error);
        completion(error.localizedDescription, NO, location);
    }];
}

+ (void)eraseTempDir:(NSString *)tempDir {
    [[NSFileManager defaultManager] removeItemAtPath:tempDir
                                               error:nil];
}

+ (BOOL)haveScriptNamed:(NSString *)name {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    return [fileManager fileExistsAtPath:[[fileManager scriptsPath] stringByAppendingPathComponent:name]];
}

+ (void)removeScriptNamed:(NSString *)name {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *path = [[fileManager scriptsPath] stringByAppendingPathComponent:name];
    iTermScriptHistoryEntry *entry = [[iTermScriptHistory sharedInstance] runningEntryWithFullPath:path];
    if (entry) {
        [entry kill];
    }
    [fileManager removeItemAtPath:path error:nil];
}

@end
