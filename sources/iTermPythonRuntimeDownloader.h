//
//  iTermPythonRuntimeDownloader.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/28/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const iTermPythonRuntimeDownloaderDidInstallRuntimeNotification;

typedef NS_ENUM(NSUInteger, iTermPythonRuntimeDownloaderStatus) {
    // Internal only
    iTermPythonRuntimeDownloaderStatusUnknown,
    iTermPythonRuntimeDownloaderStatusWorking,

    // Current version satisfies requirements
    iTermPythonRuntimeDownloaderStatusNotNeeded,

    // New version was downloaded
    iTermPythonRuntimeDownloaderStatusDownloaded,

    // User canceled download
    iTermPythonRuntimeDownloaderStatusCanceledByUser,

    // Asked for a version that's not available
    iTermPythonRuntimeDownloaderStatusRequestedVersionNotFound,

    // Something else went wrong (e.g., download failed)
    iTermPythonRuntimeDownloaderStatusError,
};

@interface iTermPythonRuntimeDownloader : NSObject

@property (nonatomic, readonly) BOOL isPythonRuntimeInstalled;

// When busy, lots of filesystem operations are going and watching paths under the Scripts folder is
// a bad idea.
@property (nonatomic, readonly) BOOL busy;

// Returns the path of the standard python binary.
- (NSString * _Nullable)pathToStandardPyenvPythonWithPythonVersion:(NSString * _Nullable)pythonVersion;

+ (NSString * _Nullable)latestPythonVersion;

- (NSString * _Nullable)pathToStandardPyenvWithVersion:(NSString * _Nullable)pythonVersion
                               creatingSymlinkIfNeeded:(BOOL)createSymlink;

+ (instancetype)sharedInstance;
+ (NSArray<NSString *> *)pythonVersionsAt:(NSString *)path;
+ (NSString * _Nullable)bestPythonVersionAt:(NSString *)path;

// This downloads if any version is already installed and there's a newer version available.
- (void)upgradeIfPossible;

// Like upgradeIfPossible but shows the window immediately.
- (void)userRequestedCheckForUpdate;

// This downloads only if the minimum version is not installed.
- (void)downloadOptionalComponentsIfNeededWithConfirmation:(BOOL)confirm
                                             pythonVersion:(NSString * _Nullable)pythonVersion
                                 minimumEnvironmentVersion:(NSInteger)minimumEnvironmentVersion
                                        requiredToContinue:(BOOL)requiredToContinue
                                            withCompletion:(void (^)(iTermPythonRuntimeDownloaderStatus))completion;

// Returns the path of the python binary given a root directory having a pyenv.
- (NSString * _Nullable)pyenvAt:(NSString *)root pythonVersion:(NSString * _Nullable)pythonVersion;
- (NSString * _Nullable)pip3At:(NSString *)root pythonVersion:(NSString * _Nullable)pythonVersion;

typedef NS_ENUM(NSUInteger, iTermInstallPythonStatus) {
    iTermInstallPythonStatusOK,
    iTermInstallPythonStatusDependencyFailed,
    iTermInstallPythonStatusGeneralFailure
};

// Installs the environment somewhere and shows a please wait window. Higher level API.
- (void)installPythonEnvironmentTo:(NSURL *)folder
                      dependencies:(NSArray<NSString *> *)dependencies
                     pythonVersion:(NSString * _Nullable)pythonVersion
                        completion:(void (^)(BOOL ok))completion;

// Install a copy of the current environment somewhere. Lower level API. No UI.
- (void)installPythonEnvironmentTo:(NSURL *)container
                  eventualLocation:(NSURL *)eventualLocation
                     pythonVersion:(NSString * _Nullable)pythonVersion
                environmentVersion:(NSInteger)environmentVersion
                      dependencies:(NSArray<NSString *> * _Nullable)dependencies
                    createSetupCfg:(BOOL)createSetupCfg
                        completion:(void (^)(iTermInstallPythonStatus))completion;

- (void)runPip3InContainer:(NSURL *)container
             pythonVersion:(NSString * _Nullable)pythonVersion
             withArguments:(NSArray<NSString *> *)arguments
                completion:(void (^)(BOOL ok, NSData * _Nullableoutput))completion;

// Max environment version for the given optional pythonVersion.
- (int)installedVersionWithPythonVersion:(NSString * _Nullable)pythonVersion;

// Given a path to an iterm2env-metadata.json, what version number does it contain? Returns 0
// if something goes wrong.
- (int)versionInMetadataAtURL:(NSURL * _Nullable)metadataURL;

- (void)installPythonEnvironmentFromZip:(NSString *)zip completion:(void (^)(NSError *))completion;

@end

NS_ASSUME_NONNULL_END
