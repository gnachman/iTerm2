//
// Created by George Nachman on 4/2/14.
//

#import <Cocoa/Cocoa.h>


@interface iTermRemotePreferences : NSObject

// These properties are backed to user defaults.
@property(nonatomic) BOOL shouldLoadRemotePrefs;
@property(nonatomic, readonly) NSString *customFolderOrURL;
@property(nonatomic) BOOL customFolderChanged;  // Path has changed since startup?
@property(nonatomic, readonly) BOOL remoteLocationIsURL;

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
- (void)copyRemotePrefsToLocalUserDefaults;

@end
