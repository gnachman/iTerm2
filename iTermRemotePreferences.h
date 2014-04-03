//
// Created by George Nachman on 4/2/14.
//

#import <Cocoa/Cocoa.h>


@interface iTermRemotePreferences : NSObject

// If remote prefs are in use load a fresh copy of them (perhaps downloading from the network) and
// overwrite local user defaults. If something goes wrong a modal alert will be presented.
- (BOOL)copyRemotePrefsToLocalUserDefaults;

// Indicates if local user defaults differ from the saved copy of the remote preferences loaded with
// -copyRemotePrefsToLocalUserDefaults.
- (BOOL)localPrefsDifferFromSavedRemotePrefs;

// Indicates if the remote prefs have changed since -copyRemotePrefsToLocalUserDefaults was called.
// Remote prefs must be enabled and must have loaded, or else this will return NO.
- (BOOL)remotePrefsHaveChanged;

// Copies the local user defaults to the remote prefs location. If it is a URL or the file is not
// writable, a modal alert is shown and nothing happens.
- (void)saveLocalUserDefaultsToRemotePrefs;

// Indicates if the given location (either a path to a folder or a URL) is valid.
- (BOOL)remoteLocationIsValid:(NSString *)remoteLocation

@end
