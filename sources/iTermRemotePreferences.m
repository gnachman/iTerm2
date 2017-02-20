//
// Created by George Nachman on 4/2/14.
//

#import "iTermRemotePreferences.h"
#import "iTermPreferences.h"
#import "iTermWarning.h"
#import "NSFileManager+iTerm.h"
#import "NSStringITerm.h"
#import "NSURL+iTerm.h"

@interface iTermRemotePreferences ()
@property(nonatomic, copy) NSDictionary *savedRemotePrefs;
@end

@implementation iTermRemotePreferences {
    BOOL _haveTriedToLoadRemotePrefs;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (void)dealloc {
    [_savedRemotePrefs release];
    [super dealloc]; 
}

- (BOOL)shouldLoadRemotePrefs {
    return [iTermPreferences boolForKey:kPreferenceKeyLoadPrefsFromCustomFolder];
}

- (void)setShouldLoadRemotePrefs:(BOOL)value {
    [iTermPreferences setBool:value forKey:kPreferenceKeyLoadPrefsFromCustomFolder];
}

// Returns a URL or containing folder
- (NSString *)customFolderOrURL {
    return [iTermPreferences stringForKey:kPreferenceKeyCustomFolder];
}

- (NSString *)expandedCustomFolderOrURL {
    NSString *theString = [self customFolderOrURL];
    if ([theString stringIsUrlLike]) {
        return theString;
    }
    return theString ? [theString stringByExpandingTildeInPath] : @"";
}

// Returns a URL or expanded filename
- (NSString *)remotePrefsLocation
{
    NSString *folder = [self expandedCustomFolderOrURL];
    NSString *filename = [self prefsFilenameWithBaseDir:folder];
    if (self.remoteLocationIsURL) {
        filename = folder;
    } else {
        filename = [filename stringByExpandingTildeInPath];
    }
    return filename;
}

- (NSString *)prefsFilenameWithBaseDir:(NSString *)base
{
    return [NSString stringWithFormat:@"%@/%@.plist",
           base, [[NSBundle mainBundle] bundleIdentifier]];
}

- (BOOL)preferenceKeyIsSyncable:(NSString *)key
{
    NSArray *exemptKeys = @[ kPreferenceKeyLoadPrefsFromCustomFolder,
                             kPreferenceKeyCustomFolder,
                             @"Secure Input",
                             @"moveToApplicationsFolderAlertSuppress",
                             @"iTerm Version" ];
    return ![exemptKeys containsObject:key] &&
            ![key hasPrefix:@"NS"] &&
            ![key hasPrefix:@"SU"] &&
            ![key hasPrefix:@"NoSync"] &&
            ![key hasPrefix:@"UK"];
}

- (NSDictionary *)freshCopyOfRemotePreferences {
    if (!self.shouldLoadRemotePrefs) {
        return nil;
    }

    NSString *filename = [self remotePrefsLocation];
    NSDictionary *remotePrefs;
    if ([filename stringIsUrlLike]) {
        // Download the URL's contents.
        NSURL *url = [NSURL URLWithUserSuppliedString:filename];
        const NSTimeInterval kFetchTimeout = 5.0;
        NSURLRequest *req = [NSURLRequest requestWithURL:url
                                             cachePolicy:NSURLRequestUseProtocolCachePolicy
                                         timeoutInterval:kFetchTimeout];
        NSURLResponse *response = nil;
        NSError *error = nil;

        NSData *data = [NSURLConnection sendSynchronousRequest:req
                                             returningResponse:&response
                                                         error:&error];
        if (!data || error) {
            NSAlert *alert = [[[NSAlert alloc] init] autorelease];
            alert.messageText = @"Failed to load preferences from URL. Falling back to local copy.";
            alert.informativeText = [NSString stringWithFormat:@"HTTP request failed: %@",
                                     [error localizedDescription] ?: @"unknown error"];
            [alert runModal];
            return NO;
        }

        // Write it to disk
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *tempDir = [fileManager temporaryDirectory];
        NSString *tempFile = [tempDir stringByAppendingPathComponent:@"temp.plist"];
        error = nil;
        if (![data writeToFile:tempFile options:0 error:&error]) {
            NSAlert *alert = [[[NSAlert alloc] init] autorelease];
            alert.messageText = @"Failed to write to temp file while getting remote prefs. Falling back to local copy.";
            alert.informativeText = [NSString stringWithFormat:@"Error on file %@: %@", tempFile,
                                     [error localizedDescription]];
            [alert runModal];
            return NO;
        }

        remotePrefs = [NSDictionary dictionaryWithContentsOfFile:tempFile];

        [fileManager removeItemAtPath:tempFile error:nil];
        [fileManager removeItemAtPath:tempDir error:nil];
    } else {
        remotePrefs = [NSDictionary dictionaryWithContentsOfFile:filename];
    }
    return remotePrefs;
}

- (NSString *)localPrefsFilename {
    NSString *prefDir = [[NSHomeDirectory()
                          stringByAppendingPathComponent:@"Library"]
                         stringByAppendingPathComponent:@"Preferences"];
    return [prefDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist",
                                                    [[NSBundle mainBundle] bundleIdentifier]]];
}

- (BOOL)folderIsWritable:(NSString *)path {
    NSString *fullPath = [path stringByExpandingTildeInPath];
    return [[NSFileManager defaultManager] directoryIsWritable:fullPath];
}

- (BOOL)remoteLocationIsValid {
    NSString *remoteLocation = [self customFolderOrURL];
    if ([remoteLocation stringIsUrlLike]) {
        // URLs are too expensive to check, so just make sure it's reasonably
        // well formed.
        return [NSURL URLWithUserSuppliedString:remoteLocation] != nil;
    }
    return [self folderIsWritable:remoteLocation];
}

- (void)saveLocalUserDefaultsToRemotePrefs
{
    if ([self remotePrefsHaveChanged]) {
        NSString *theTitle =
            [NSString stringWithFormat:@"Preferences at %@ changed since iTerm2 started. "
                                       @"Overwrite it?",
                                       [self customFolderOrURL]];
        if ([iTermWarning showWarningWithTitle:theTitle actions:@[ @"Overwrite",
                                                                   @"Discard Local Changes" ]
                                    identifier:nil
                                   silenceable:kiTermWarningTypePersistent] == kiTermWarningSelection1) {
            return;
        }
    }
    
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    NSString *folder = [self expandedCustomFolderOrURL];
    if ([folder stringIsUrlLike]) {
        NSString *informativeText =
            @"To make it available, first quit iTerm2 and then manually "
            @"copy ~/Library/Preferences/com.googlecode.iterm2.plist to "
            @"your hosting provider.";
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        alert.messageText = @"Preferences cannot be copied to a URL.";
        alert.informativeText = informativeText;
        [alert runModal];
        return;
    }
    
    NSString *filename = [self prefsFilenameWithBaseDir:folder];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // Copy fails if the destination exists.
    [fileManager removeItemAtPath:filename error:nil];
    
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *myDict =
    [userDefaults persistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
    BOOL isOk;
    isOk = [myDict writeToFile:filename atomically:YES];
    if (!isOk) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        alert.messageText = @"Failed to copy preferences to custom directory.";
        alert.informativeText = [NSString stringWithFormat:@"Tried to copy %@ to %@",
                                 [self remotePrefsLocation], filename];
        [alert runModal];
    } else {
        self.savedRemotePrefs = myDict;
    }
}

- (void)copyRemotePrefsToLocalUserDefaults {
    if (_haveTriedToLoadRemotePrefs) {
        return;
    }
    _haveTriedToLoadRemotePrefs = YES;

    if (!self.shouldLoadRemotePrefs) {
        return;
    }
    NSDictionary *remotePrefs = [self freshCopyOfRemotePreferences];
    self.savedRemotePrefs = remotePrefs;

    if (remotePrefs && [remotePrefs count]) {
        NSString *theFilename = [self localPrefsFilename];
        NSDictionary *localPrefs = [NSDictionary dictionaryWithContentsOfFile:theFilename];
        // Empty out the current prefs
        for (NSString *key in localPrefs) {
            if ([self preferenceKeyIsSyncable:key]) {
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
            }
        }

        for (NSString *key in remotePrefs) {
            if ([self preferenceKeyIsSyncable:key]) {
                [[NSUserDefaults standardUserDefaults] setObject:[remotePrefs objectForKey:key]
                                                          forKey:key];
            }
        }
        return;
    } else {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        alert.messageText = @"Failed to load preferences from custom directory. Falling back to local copy.";
        alert.informativeText = [NSString stringWithFormat:@"Missing or malformed file at \"%@\"",
                                 [self customFolderOrURL]];
        [alert runModal];
    }
    return;
}

- (BOOL)localPrefsDifferFromSavedRemotePrefs
{
    if (!self.shouldLoadRemotePrefs) {
        return NO;
    }
    if (_savedRemotePrefs && [_savedRemotePrefs count]) {
        // Grab all prefs from our bundle only (no globals, etc.).
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        NSDictionary *localPrefs =
            [userDefaults persistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        // Iterate over each set of prefs and validate that the other has the same value for each
        // key.
        for (NSString *key in localPrefs) {
            if ([self preferenceKeyIsSyncable:key] &&
                ![[_savedRemotePrefs objectForKey:key] isEqual:[localPrefs objectForKey:key]]) {
                return YES;
            }
        }

        for (NSString *key in _savedRemotePrefs) {
            if ([self preferenceKeyIsSyncable:key] &&
                ![[_savedRemotePrefs objectForKey:key] isEqual:[localPrefs objectForKey:key]]) {
                return YES;
            }
        }
    }
    return NO;
}

- (BOOL)remotePrefsHaveChanged {
    if (!self.shouldLoadRemotePrefs) {
        return NO;
    }
    if (!_savedRemotePrefs) {
        return NO;
    }
    if (self.remoteLocationIsURL) {
        return NO;
    }
    return ![[self freshCopyOfRemotePreferences] isEqual:_savedRemotePrefs];
}

- (void)applicationWillTerminate {
    if ([self localPrefsDifferFromSavedRemotePrefs]) {
        if (self.remoteLocationIsURL) {
            // If the setting is always copy, then ask. Copying isn't an option.
            NSString *theTitle = [NSString stringWithFormat:
                                  @"Changes made to preferences will be lost when iTerm2 is restarted "
                                  @"because they are loaded from a URL at startup."];
            [iTermWarning showWarningWithTitle:theTitle
                                       actions:@[ @"OK" ]
                                    identifier:@"NoSyncNeverRemindPrefsChangesLostForUrl"
                                   silenceable:kiTermWarningTypePermanentlySilenceable];
        } else {
            // Not a URL
            NSString *theTitle = [NSString stringWithFormat:
                                  @"Preferences have changed. Copy them to %@?",
                                  [self customFolderOrURL]];

            iTermWarningSelection selection =
                [iTermWarning showWarningWithTitle:theTitle
                                           actions:@[ @"Copy", @"Lose Changes" ]
                                        identifier:@"NoSyncNeverRemindPrefsChangesLostForFile"
                                       silenceable:kiTermWarningTypePermanentlySilenceable];
            if (selection == kiTermWarningSelection0) {
                [self saveLocalUserDefaultsToRemotePrefs];
            }
        }
    }
}

- (BOOL)remoteLocationIsURL {
    NSString *customFolderOrURL = [self expandedCustomFolderOrURL];
    return [customFolderOrURL stringIsUrlLike];
}

@end
