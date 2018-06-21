//
//  iTermPythonRuntimeDownloader.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/28/18.
//

#import <Foundation/Foundation.h>

extern NSString *const iTermPythonRuntimeDownloaderDidInstallRuntimeNotification;

@interface iTermPythonRuntimeDownloader : NSObject

@property (nonatomic, readonly) BOOL isPythonRuntimeInstalled;

// Returns the path of the standard python binary.
@property (nonatomic, readonly) NSString *pathToStandardPyenvPython;

- (NSString *)pathToStandardPyenvCreatingSymlinkIfNeeded:(BOOL)createSymlink;

+ (instancetype)sharedInstance;

// This downloads if any version is already installed and there's a newer version available.
- (void)upgradeIfPossible;

// Like upgradeIfPossible but shows the window immediately.
- (void)userRequestedCheckForUpdate;

// This downloads only if the minimum version is not installed.
- (void)downloadOptionalComponentsIfNeededWithConfirmation:(BOOL)confirm withCompletion:(void (^)(BOOL))completion;

// Returns the path of the python binary given a root directory having a pyenv.
- (NSString *)pyenvAt:(NSString *)root;

// Install a copy of the current environment somewhere.
- (void)installPythonEnvironmentTo:(NSURL *)container dependencies:(NSArray<NSString *> *)dependencies completion:(void (^)(BOOL))completion;

@end
