//
//  iTermScriptImporter.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/24/18.
//

#import "iTermScriptImporter.h"

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
                 completion:(void (^)(NSString *errorMessage, BOOL quiet, NSURL *location))completion {
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
                                 completion:^(NSString *errorMessage, BOOL quiet, NSURL *location) {
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
                       completion:(void (^)(NSString *errorMessage, BOOL quiet, NSURL *location))completion {
    if (sInstallingScript) {
        completion(@"Another import is in progress. Please try again after it completes.", NO, nil);
        return;
    }

    if ([downloadedURL.pathExtension isEqualToString:@"py"]) {
        NSString *to = [[[NSFileManager defaultManager] scriptsPath] stringByAppendingPathComponent:downloadedURL.lastPathComponent];
        NSError *error;
        [[NSFileManager defaultManager] copyItemAtURL:downloadedURL
                                                toURL:[NSURL fileURLWithPath:to]
                                                error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(error.localizedDescription, NO, error ? nil : [NSURL fileURLWithPath:to]);
        });
        return;
    }
    sInstallingScript = YES;
    [self verifyAndUnwrapArchive:downloadedURL requireSignature:!userInitiated completion:^(NSURL *url, NSString *errorMessage, BOOL trusted, BOOL reveal, BOOL quiet) {
        if (errorMessage) {
            completion(errorMessage, quiet, nil);
            sInstallingScript = NO;
            return;
        }

        iTermBuildingScriptWindowController *pleaseWait;
        if (!reveal) {
            pleaseWait = [iTermBuildingScriptWindowController newPleaseWaitWindowController];
            [pleaseWait.window makeKeyAndOrderFront:nil];
        }
        NSString *tempDir = [[NSFileManager defaultManager] temporaryDirectory];

        [iTermCommandRunner unzipURL:url
                       withArguments:@[ @"-q" ]
                         destination:tempDir
                          completion:^(BOOL ok) {
                              if (!ok) {
                                  [pleaseWait.window close];
                                  completion(@"Could not unzip archive", NO, nil);
                                  sInstallingScript = NO;
                                  return;
                              }
                              [self didUnzipSuccessfullyTo:tempDir
                                                   trusted:trusted
                                           offerAutoLaunch:offerAutoLaunch
                                                    reveal:reveal
                                            withCompletion:
                               ^(NSString *errorMessage, BOOL quiet, NSURL *location) {
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
    SIGArchiveVerifier *verifier = [[SIGArchiveVerifier alloc] initWithURL:url];
    if ([[url pathExtension] isEqualToString:@"its"]) {
        if (![verifier smellsLikeSignedArchive:NULL]) {
            completion(nil, @"This script archive is corrupt and cannot be installed.", NO, NO, NO);
            return;
        }
        
        NSURL *zipURL = [NSURL fileURLWithPath:[[NSWorkspace sharedWorkspace] temporaryFileNameWithPrefix:@"script" suffix:@".zip"]];
        [verifier verifyWithCompletion:^(BOOL ok, NSError * _Nullable error) {
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
    if (!ok) {
        completion(nil, error.localizedDescription ?: @"Unknown error", NO, NO, NO);
        return;
    }
    
    if (requireSignature) {
        NSData *data = [[verifier.reader signingCertificates:nil] firstObject];
        if (!data) {
            completion(nil, @"Could not find certificate after verficiation (nil data)", NO, NO, NO);
            return;
        }
        SIGCertificate *cert = [[SIGCertificate alloc] initWithData:data];
        if (!cert) {
            completion(nil, @"Could not find certificate after verficiation (bad data)", NO, NO, NO);
            return;
        }
        [self confirmInstallationOfVerifiedArchive:verifier.reader
                                   withCertificate:cert
                                        completion:^(BOOL ok, BOOL reveal) {
                                            if (!ok) {
                                                completion(nil, @"Installation canceled by user request.", NO, NO, YES);
                                                return;
                                            }
                                            [self copyPayloadFromVerifier:verifier
                                                                    toURL:zipURL
                                                               completion:^(NSURL *URL, NSString *errorString) {
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
                withCompletion:(void (^)(NSString *errorMessage, BOOL, NSURL *location))completion {
    if (reveal) {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:tempDir]];
        completion(nil, NO, nil);
        return;
    }

    BOOL deprecated = NO;
    iTermScriptArchive *archive = [iTermScriptArchive archiveFromContainer:tempDir
                                                                deprecated:&deprecated];
    if (!archive) {
        if (deprecated) {
            completion(@"This archive was created by an older version of iTerm2. This kind of archive is no longer supported and cannot be installed.", NO, nil);
        } else {
            completion(@"Archive does not contain a valid iTerm2 script", NO, nil);
        }
        return;
    }

    if ([self haveScriptNamed:archive.name]) {
        iTermWarningSelection selection = [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"A script named “%@” is already installed", archive.name]
                                                                     actions:@[ @"Replace Script", @"Cancel" ]
                                                                   accessory:nil
                                                                  identifier:nil
                                                                 silenceable:kiTermWarningTypePersistent
                                                                     heading:@"Script Already Exists"
                                                                      window:nil];
        if (selection == kiTermWarningSelection0) {
            [self removeScriptNamed:archive.name];
            [self didUnzipSuccessfullyTo:tempDir
                                 trusted:trusted
                         offerAutoLaunch:offerAutoLaunch
                                  reveal:reveal
                          withCompletion:completion];
            return;
        }
        completion(nil, YES, nil);
        return;
    }

    [archive installTrusted:trusted offerAutoLaunch:offerAutoLaunch withCompletion:^(NSError *error, NSURL *location) {
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
