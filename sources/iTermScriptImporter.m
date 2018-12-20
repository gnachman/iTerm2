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
#import "iTermWarning.h"
#import "NSFileManager+iTerm.h"
#import "NSWorkspace+iTerm.h"
#import "SIGArchiveVerifier.h"
#import "SIGCertificate.h"

static BOOL sInstallingScript;

@implementation iTermScriptImporter

+ (void)importScriptFromURL:(NSURL *)downloadedURL
              userInitiated:(BOOL)userInitiated
                 completion:(void (^)(NSString *errorMessage))completion {
    if (sInstallingScript) {
        completion(@"Another import is in progress. Please try again after it completes.");
        return;
    }

    sInstallingScript = YES;
    [self verifyAndUnwrapArchive:downloadedURL requireSignature:!userInitiated completion:^(NSURL *url, NSString *errorMessage, BOOL trusted) {
        if (errorMessage) {
            completion(errorMessage);
            sInstallingScript = NO;
            return;
        }

        iTermBuildingScriptWindowController *pleaseWait = [iTermBuildingScriptWindowController newPleaseWaitWindowController];
        [pleaseWait.window makeKeyAndOrderFront:nil];
        NSString *tempDir = [[NSFileManager defaultManager] temporaryDirectory];

        [iTermCommandRunner unzipURL:url
                       withArguments:@[ @"-q" ]
                         destination:tempDir
                          completion:^(BOOL ok) {
                              if (!ok) {
                                  [pleaseWait.window close];
                                  completion(@"Could not unzip archive");
                                  sInstallingScript = NO;
                                  return;
                              }
                              [self didUnzipSuccessfullyTo:tempDir trusted:trusted withCompletion:^(NSString *errorMessage) {
                                  [self eraseTempDir:tempDir];
                                  [pleaseWait.window close];
                                  sInstallingScript = NO;
                                  completion(errorMessage);
                              }];
                          }];
    }];
}

+ (void)verifyAndUnwrapArchive:(NSURL *)url
              requireSignature:(BOOL)requireSignature
                    completion:(void (^)(NSURL *url, NSString *, BOOL trusted))completion {
    SIGArchiveVerifier *verifier = [[SIGArchiveVerifier alloc] initWithURL:url];
    if ([[url pathExtension] isEqualToString:@"itermscript"]) {
        if (![verifier smellsLikeSignedArchive:NULL]) {
            completion(nil, @"This script archive is corrupt and cannot be installed.", NO);
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
        completion(nil, @"This is not a valid iTerm2 script archive.", NO);
        return;
    }
    completion(url, nil, NO);
}

+ (void)verifierDidComplete:(SIGArchiveVerifier *)verifier
                withSuccess:(BOOL)ok
                 payloadURL:(NSURL *)zipURL
           requireSignature:(BOOL)requireSignature
                      error:(NSError *)error
                 completion:(void (^)(NSURL *url, NSString *, BOOL trusted))completion {
    if (!ok) {
        completion(nil, error.localizedDescription ?: @"Unknown error", NO);
        return;
    }
    
    if (requireSignature) {
        [self confirmInstallationOfVerifiedArchive:verifier.reader
                                        completion:^(BOOL ok) {
                                            if (!ok) {
                                                completion(nil, @"Installation canceled by user request.", NO);
                                                return;
                                            }
                                            [self copyPayloadFromVerifier:verifier
                                                                    toURL:zipURL
                                                               completion:^(NSURL *URL, NSString *errorString) {
                                                                   completion(URL, errorString, YES);
                                                               }];
                                        }];
        return;
    }
    [self copyPayloadFromVerifier:verifier
                            toURL:zipURL
                       completion:^(NSURL *URL, NSString *errorString) {
                           completion(URL, errorString, YES);
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

+ (void)confirmInstallationOfVerifiedArchive:(SIGArchiveReader *)reader
                                  completion:(void (^)(BOOL ok))completion {
    SIGCertificate *cert = [[SIGCertificate alloc] initWithData:[reader signingCertificate:nil]];
    NSString *body = [NSString stringWithFormat:@"The signature of ”%@” has been verified. The author is:\n\n%@\n\nWould you like to install it?", reader.url.lastPathComponent, ((cert.name ?: cert.longDescription) ?: @"Unknown")];
    iTermWarningSelection selection = [iTermWarning showWarningWithTitle:body
                                                                 actions:@[ @"OK", @"Cancel" ]
                                                               accessory:nil
                                                              identifier:nil
                                                             silenceable:kiTermWarningTypePersistent
                                                                 heading:@"Confirm Installation"
                                                                  window:nil];
    completion(selection == kiTermWarningSelection0);
}

+ (void)didUnzipSuccessfullyTo:(NSString *)tempDir
                       trusted:(BOOL)trusted
                withCompletion:(void (^)(NSString *errorMessage))completion {
    iTermScriptArchive *archive = [iTermScriptArchive archiveFromContainer:tempDir];
    if (!archive) {
        completion(@"Archive does not contain a valid iTerm2 script");
        return;
    }

    if ([self haveScriptNamed:archive.name]) {
        completion([NSString stringWithFormat:@"A script named “%@” is already installed", archive.name]);
        return;
    }

    [archive installTrusted:trusted withCompletion:^(NSError *error) {
        completion(error.localizedDescription);
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

@end
