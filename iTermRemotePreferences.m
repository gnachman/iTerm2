//
// Created by George Nachman on 4/2/14.
//

#import "iTermRemotePreferences.h"
#import "NSStringITerm.h"

static NSString *const kLoadPrefsFromCustomFolderKey = @"LoadPrefsFromCustomFolder";
static NSString *const kPrefsCustomFolderKey = @"PrefsCustomFolder";

@interface iTermRemotePreferences ()
@property(nonatomic, copy) NSDictionary *savedRemotePrefs;
@end

@implementation iTermRemotePreferences {
    BOOL _haveTriedToLoadRemotePrefs;
}

+ (BOOL)loadingPrefsFromCustomFolder
{
    NSNumber *n =
        [[NSUserDefaults standardUserDefaults] objectForKey:kLoadPrefsFromCustomFolderKey];
    return n ? [n boolValue] : NO;
}

// Returns a URL or containing folder
+ (NSString *)customFolderOrURL {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSString *theString = [userDefaults objectForKey:kPrefsCustomFolderKey];
    return theString ? [theString stringByExpandingTildeInPath] : @"";
}

// Returns a URL or filename
+ (NSString *)remotePrefsLocation
{
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSString *folder = [self customFolderOrURL];
    NSString *filename = [[self class] prefsFilenameWithBaseDir:folder];
    if ([folder stringIsUrlLike]) {
        filename = folder;
    } else {
        filename = [filename stringByExpandingTildeInPath];
    }
    return filename;
}

+ (NSString *)prefsFilenameWithBaseDir:(NSString *)base
{
    return [NSString stringWithFormat:@"%@/%@.plist",
           base, [[NSBundle mainBundle] bundleIdentifier]];
}

+ (BOOL)preferenceKeyIsSyncable:(NSString *)key
{
    NSArray *exemptKeys = @[ @"LoadPrefsFromCustomFolder",
                             kPrefsCustomFolderKey,
                             @"iTerm Version" ];
    return ![exemptKeys containsObject:key] &&
            ![key hasPrefix:@"NS"] &&
            ![key hasPrefix:@"SU"] &&
            ![key hasPrefix:@"NoSync"] &&
            ![key hasPrefix:@"UK"];
}

+ (NSDictionary *)freshCopyOfRemotePreferences
{
    if (![self loadingPrefsFromCustomFolder]) {
        return nil;
    }

    NSString *filename = [self remotePrefsLocation];
    NSDictionary *remotePrefs;
    if ([filename stringIsUrlLike]) {
        // Download the URL's contents.
        NSURL *url = [NSURL URLWithString:filename];
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
            [[NSAlert alertWithMessageText:@"Failed to load preferences from URL. "
                                           @"Falling back to local copy."
                             defaultButton:@"OK"
                           alternateButton:nil
                               otherButton:nil
                 informativeTextWithFormat:@"HTTP request failed: %@",
                                           [error description] ? [error description]
                                                               : @"unknown error"] runModal];
            return NO;
        }

        // Write it to disk
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *tempDir = [fileManager temporaryDirectory];
        NSString *tempFile = [tempDir stringByAppendingPathComponent:@"temp.plist"];
        error = nil;
        if (![data writeToFile:tempFile options:0 error:&error]) {
            [[NSAlert alertWithMessageText:@"Failed to write to temp file while getting remote "
                                           @"prefs. Falling back to local copy."
                             defaultButton:@"OK"
                           alternateButton:nil
                               otherButton:nil
                 informativeTextWithFormat:@"Error on file %@: %@", tempFile,
                                           [error localizedFailureReason]] runModal];
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

+ (NSString *)localPrefsFilename {
    NSString *prefDir = [[NSHomeDirectory()
                          stringByAppendingPathComponent:@"Library"]
                         stringByAppendingPathComponent:@"Preferences"];
    return [prefDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist",
                                                    [[NSBundle mainBundle] bundleIdentifier]]];
}

+ (BOOL)folderIsWritable:(NSString *)path {
    NSString *fullPath = [path stringByExpandingTildeInPath];
    return [[NSFileManager defaultManager] directoryIsWritable:fullPath];
}

#pragma mark - Instance methods

- (void)dealloc {
    [_savedRemotePrefs release];
    [super dealloc];
}

- (void)copyRemotePrefsToLocalUserDefaults {
    if (_haveTriedToLoadRemotePrefs) {
        return;
    }
    _haveTriedToLoadRemotePrefs = YES;

    if (![[self class] loadingPrefsFromCustomFolder]) {
        return;
    }
    NSDictionary *remotePrefs = [self freshCopyOfRemotePreferences];
    self.savedRemotePrefs = remotePrefs;

    if (remotePrefs && [remotePrefs count]) {
        NSString *theFilename = [[self class] localPrefsFilename];
        NSDictionary *localPrefs = [NSDictionary dictionaryWithContentsOfFile:theFilename];
        // Empty out the current prefs
        for (NSString *key in localPrefs) {
            if ([[self class] preferenceKeyIsSyncable:key]) {
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
            }
        }

        for (NSString *key in remotePrefs) {
            if ([[self class] preferenceKeyIsSyncable:key]) {
                [[NSUserDefaults standardUserDefaults] setObject:[remotePrefs objectForKey:key]
                                                          forKey:key];
            }
        }
        return;
    } else {
        [[NSAlert alertWithMessageText:@"Failed to load preferences from custom directory. "
                                       @"Falling back to local copy."
                         defaultButton:@"OK"
                       alternateButton:nil
                           otherButton:nil
             informativeTextWithFormat:@"Missing or malformed file at \"%@\"",
                                       [[self class] remotePrefsLocation]] runModal];
    }
    return;
}

- (BOOL)localPrefsDifferFromSavedRemotePrefs
{
    if (![[self class] loadingPrefsFromCustomFolder]) {
        return NO;
    }
    if (_savedRemotePrefs && [_savedRemotePrefs count]) {
        // Grab all prefs from our bundle only (no globals, etc.).
        NSDictionary *localPrefs =
            [prefs persistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        // Iterate over each set of prefs and validate that the other has the same value for each
        // key.
        for (NSString *key in localPrefs) {
            if ([[self class] preferenceKeyIsSyncable:key] &&
                ![[_savedRemotePrefs objectForKey:key] isEqual:[localPrefs objectForKey:key]]) {
                return YES;
            }
        }

        for (NSString *key in _savedRemotePrefs) {
            if ([[self class] preferenceKeyIsSyncable:key] &&
                ![[_savedRemotePrefs objectForKey:key] isEqual:[localPrefs objectForKey:key]]) {
                return YES;
            }
        }
        return NO;
    }
}

- (BOOL)remotePrefsHaveChanged {
    if (![[self class] loadingPrefsFromCustomFolder]) {
        return NO;
    }
    if (!_savedRemotePrefs) {
        return NO;
    }
    return ![[[self class] freshCopyOfRemotePreferences] isEqual:_savedRemotePrefs];
}

- (void)saveLocalUserDefaultsToRemotePrefs
{
    [[NSUserDefaults standardUserDefaults] synchronize];

    NSString *folder = [[self class] customFolderOrURL];
    if ([folder stringIsUrlLike]) {
        NSString *informativeText = 
            @"To make it available, first quit iTerm2 and then manually "
            @"copy ~/Library/Preferences/com.googlecode.iterm2.plist to "
            @"your hosting provider.";
        [[NSAlert alertWithMessageText:@"Sorry, preferences cannot be copied to a URL by iTerm2."
                         defaultButton:@"OK"
                       alternateButton:nil
                           otherButton:nil
             informativeTextWithFormat:informativeText] runModal];
        return;
    }

    NSString *filename = [[self class] prefsFilenameWithBaseDir:folder];
    NSFileManager *fileManager = [NSFileManager defaultManager];

    // Copy fails if the destination exists.
    [fileManager removeItemAtPath:filename error:nil];

    [self savePreferences];
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *myDict =
        [userDefaults persistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
    BOOL isOk;
    isOk = [myDict writeToFile:filename atomically:YES];
    if (!isOk) {
        [[NSAlert alertWithMessageText:@"Failed to copy preferences to custom directory."
                         defaultButton:@"OK"
                       alternateButton:nil
                           otherButton:nil
             informativeTextWithFormat:@"Tried to copy %@ to %@: %s",
                                       [self _prefsFilename], filename, strerror(errno)] runModal];
    }
}

- (BOOL)remoteLocationIsValid:(NSString *)remoteLocation
{
    if ([remoteLocation stringIsUrlLike]) {
        // URLs are too expensive to check, so just make sure it's reasonably
        // well formed.
        return [NSURL URLWithString:remoteLocation] != nil;
    }
    return [[self class] folderIsWritable:remoteLocation];
}

@end
