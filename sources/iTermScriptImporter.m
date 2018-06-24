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
#import "NSFileManager+iTerm.h"

static BOOL sInstallingScript;

@implementation iTermScriptImporter

+ (void)importScriptFromURL:(NSURL *)url
                 completion:(void (^)(NSString *errorMessage))completion {
    if (sInstallingScript) {
        completion(@"Another import is in progress. Please try again after it completes.");
        return;
    }

    sInstallingScript = YES;
    NSString *tempDir = [[NSFileManager defaultManager] temporaryDirectory];
    iTermBuildingScriptWindowController *pleaseWait = [iTermBuildingScriptWindowController newPleaseWaitWindowController];
    [pleaseWait.window makeKeyAndOrderFront:nil];
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
                          [self didUnzipSuccessfullyTo:tempDir withCompletion:^(NSString *errorMessage) {
                              [self eraseTempDir:tempDir];
                              [pleaseWait.window close];
                              sInstallingScript = NO;
                              completion(errorMessage);
                          }];
                      }];

}

+ (void)didUnzipSuccessfullyTo:(NSString *)tempDir
                withCompletion:(void (^)(NSString *errorMessage))completion {
    iTermScriptArchive *archive = [iTermScriptArchive archiveFromContainer:tempDir];
    if (!archive) {
        completion(@"Archive does not contain a valid iTerm2 script");
    }

    if ([self haveScriptNamed:archive.name]) {
        completion([NSString stringWithFormat:@"A script named “%@” is already installed", archive.name]);
        return;
    }

    [archive installWithCompletion:^(NSError *error) {
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
