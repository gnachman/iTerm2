//
// Created by George Nachman on 4/2/14.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermRemotePreferences : NSObject

// These properties are backed to user defaults.
@property(nonatomic) BOOL shouldLoadRemotePrefs;
@property(nonatomic, readonly, nullable) NSString *customFolderOrURL;
@property(nonatomic) BOOL customFolderChanged;  // Path has changed since startup?
@property(nonatomic, readonly) BOOL remoteLocationIsURL;
@property(nonatomic, readonly) NSDictionary *userDefaultsDictionary;

+ (instancetype)sharedInstance;

// Indicates if the given location (either a path to a folder or a URL) is valid.
- (BOOL)remoteLocationIsValid;

// Copies the local user defaults to the remote prefs location. If it is a URL or the file is not
// writable, a modal alert is shown and nothing happens.
- (void)saveLocalUserDefaultsToRemotePrefs;

// Save prefs to remote and maybe ask the user what to do.
- (void)applicationWillTerminate;

// If remote prefs are in use load a fresh copy of them (perhaps downloading from the network) and
// overwrite local user defaults. If something goes wrong a modal alert will be presented.
- (void)copyRemotePrefsToLocalUserDefaultsPreserving:(NSArray<NSString *> *)preservedKeys;

- (BOOL)localPrefsDifferFromSavedRemotePrefsRespectingDefaults;
- (BOOL)shouldSaveAutomatically;

// Returns remotePrefs as it would be had the migration described by before and after (see
// iTermUserDefaultsDidMigrateKeysNotification) run on it too. A key whose remote value is the one
// the migration started from takes the migrated value; any other key is left alone, so a value the
// user had already changed locally still counts as a difference. Exposed for testing.
+ (NSDictionary *)remotePrefs:(NSDictionary *)remotePrefs
    byApplyingMigrationFromValues:(NSDictionary<NSString *, id> *)before
                         toValues:(NSDictionary<NSString *, id> *)after;

// Whether any syncable key has a different value in localPrefs than in remotePrefs. Keys in
// preservedKeys are not synced and are ignored. Exposed for testing.
+ (BOOL)localPrefs:(NSDictionary *)localPrefs
    differFromRemotePrefs:(NSDictionary *)remotePrefs
            preservedKeys:(NSArray<NSString *> *)preservedKeys
       respectingDefaults:(BOOL)respectDefaults;

@end

NS_ASSUME_NONNULL_END
