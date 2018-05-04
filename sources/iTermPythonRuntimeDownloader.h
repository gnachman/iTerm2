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

// Returns the path of the standard pyenv folder.
@property (nonatomic, readonly) NSString *pathToStandardPyenv;

+ (instancetype)sharedInstance;

// This downloads if any version is already installed and there's a newer version available.
- (void)upgradeIfPossible;

// This downloads only if the minimum version is not installed.
- (void)downloadOptionalComponentsIfNeededWithCompletion:(void (^)(void))completion;

// Returns the path of the python binary given a root directory having a pyenv.
- (NSString *)pyenvAt:(NSString *)root;

// Install a copy of the current environment somewhere.
- (void)installPythonEnvironmentTo:(NSURL *)container completion:(void (^)(BOOL))completion;

@end
