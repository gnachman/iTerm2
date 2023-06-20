//
// Created by George Nachman on 4/2/14.
//

#import "iTermRemotePreferences.h"

#import "DebugLogging.h"
#import "iTermDynamicProfileManager.h"
#import "iTermPreferences.h"
#import "iTermUserDefaultsObserver.h"
#import "iTermWarning.h"
#import "NSDictionary+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSStringITerm.h"
#import "NSURL+iTerm.h"
#import "PreferencePanel.h"

static NSString *iTermRemotePreferencesPromptBeforeLoadingPrefsFromURL = @"NoSyncPromptBeforeLoadingPrefsFromURL";

@interface iTermRemotePreferences ()
@property(atomic, copy) NSDictionary *savedRemotePrefs;
@property(nonatomic, copy) NSArray<NSString *> *preservedKeys;
@end

@implementation iTermRemotePreferences {
    BOOL _haveTriedToLoadRemotePrefs;
    iTermUserDefaultsObserver *_userDefaultsObserver;
    BOOL _needsSave;
    dispatch_queue_t _queue;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
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

static BOOL iTermRemotePreferencesKeyIsSyncable(NSString *key,
                                                NSArray<NSString *> *preservedKeys) {
    if ([preservedKeys containsObject:key]) {
        return NO;
    }
    NSArray *exemptKeys = @[ kPreferenceKeyLoadPrefsFromCustomFolder,
                             kPreferenceKeyCustomFolder,
                             @"Secure Input",
                             @"moveToApplicationsFolderAlertSuppress",
                             kPreferenceKeyAppVersion,
                             @"CGFontRenderingFontSmoothingDisabled",
                             @"PreventEscapeSequenceFromChangingProfile",
                             @"PreventEscapeSequenceFromClearingHistory",
                             @"Coprocess MRU",
                             @"MetalCaptureEnabled",
                             @"MetalCaptureEnabledDate"];
    return ![exemptKeys containsObject:key] &&
            ![key hasPrefix:@"NS"] &&
            ![key hasPrefix:@"SU"] &&
            ![key hasPrefix:@"NoSync"] &&
            ![key hasPrefix:@"UK"];
}

- (BOOL)preferenceKeyIsSyncable:(NSString *)key {
    return iTermRemotePreferencesKeyIsSyncable(key, self.preservedKeys);
}

- (NSDictionary *)freshCopyOfRemotePreferences {
    if (!self.shouldLoadRemotePrefs) {
        return nil;
    }

    NSString *filename = [self remotePrefsLocation];
    NSDictionary *remotePrefs;
    if ([filename stringIsUrlLike]) {
        DLog(@"Is URL");
        NSString *promptURL = [[NSUserDefaults standardUserDefaults] objectForKey:iTermRemotePreferencesPromptBeforeLoadingPrefsFromURL];
        if ([promptURL isEqual:filename]) {
            DLog(@"Prompting");
            NSString *theTitle = [NSString stringWithFormat:
                                  @"Load settings from URL? Some changes were made to the local copy that will be lost."];
            const iTermWarningSelection selection =
            [iTermWarning showWarningWithTitle:theTitle
                                       actions:@[ @"Keep Local Changes",
                                                  @"Disable Loading from URL",
                                                  @"Discard Local Changes" ]
                                    identifier:@"NoSyncPromptBeforeLoadingPrefsFromURL"
                                   silenceable:kiTermWarningTypePersistent
                                        window:nil];
            switch (selection) {
                case kiTermWarningSelection0:
                    DLog(@"Keep local changes");
                    return nil;
                case kiTermWarningSelection1:
                    DLog(@"Disable url");
                    [iTermPreferences setBool:NO forKey:kPreferenceKeyLoadPrefsFromCustomFolder];
                    [[NSUserDefaults standardUserDefaults] setObject:nil
                                                              forKey:iTermRemotePreferencesPromptBeforeLoadingPrefsFromURL];
                    return nil;
                case kiTermWarningSelection2:
                    DLog(@"Discard local");
                    [[NSUserDefaults standardUserDefaults] setObject:nil
                                                              forKey:iTermRemotePreferencesPromptBeforeLoadingPrefsFromURL];
                    break;
                default:
                    break;
            }
        }
        // Download the URL's contents.
        NSURL *url = [NSURL URLWithUserSuppliedString:filename];
        const NSTimeInterval kFetchTimeout = 5.0;
        NSURLRequest *req = [NSURLRequest requestWithURL:url
                                             cachePolicy:NSURLRequestUseProtocolCachePolicy
                                         timeoutInterval:kFetchTimeout];
        __block NSError *error = nil;
        __block NSData *data = nil;

        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        DLog(@"Create task for %@", url);
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData * _Nullable taskData,
                                                                                 NSURLResponse * _Nullable taskResponse,
                                                                                 NSError * _Nullable taskError) {
            DLog(@"Task progressing with %@ bytes", @(taskData.length));
            data = taskData;
            error = taskError;
            dispatch_semaphore_signal(sema);
        }];
        DLog(@"Resume task");
        [task resume];
        DLog(@"Wait for completion");
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
        DLog(@"Download completed");

        if (!data || error) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Failed to load preferences from URL. Falling back to local copy.";
            alert.informativeText = [NSString stringWithFormat:@"HTTP request failed: %@",
                                     [error localizedDescription] ?: @"unknown error"];
            [alert addButtonWithTitle:@"OK"];
            [alert addButtonWithTitle:@"Reveal Setting in Preferences"];
            const NSModalResponse response = [alert runModal];
            if (response == NSAlertSecondButtonReturn) {
                [[PreferencePanel sharedInstance] openToPreferenceWithKey:kPreferenceKeyLoadPrefsFromCustomFolder];
            }
            return nil;
        }

        // Write it to disk
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *tempDir = [fileManager temporaryDirectory];
        NSString *tempFile = [tempDir stringByAppendingPathComponent:@"temp.plist"];
        error = nil;
        if (![data writeToFile:tempFile options:0 error:&error]) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Failed to write to temp file while getting remote prefs. Falling back to local copy.";
            alert.informativeText = [NSString stringWithFormat:@"Error on file %@: %@", tempFile,
                                     [error localizedDescription]];
            [alert runModal];
            return nil;
        }

        remotePrefs = [NSDictionary dictionaryWithContentsOfFile:tempFile];

        [fileManager removeItemAtPath:tempFile error:nil];
        [fileManager removeItemAtPath:tempDir error:nil];
    } else {
        DLog(@"Will load dictionary from %@", filename);
        remotePrefs = [NSDictionary dictionaryWithContentsOfFile:filename];
        DLog(@"Did load dictionary from %@", filename);
    }
    if (!remotePrefs.count) {
        DLog(@"It's empty");
        if ([[self customFolderOrURL] length] == 0) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Error Loading Settings";
            alert.informativeText = @"You have enabled “Load preferences from a custom folder or URL” in settings but the location is not set.";
            [alert addButtonWithTitle:@"Don’t Load Remote Settings"];
            [alert addButtonWithTitle:@"Cancel"];
            if ([alert runModal] == NSAlertFirstButtonReturn) {
                [iTermPreferences setBool:NO forKey:kPreferenceKeyLoadPrefsFromCustomFolder];
            }
        } else {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Failed to load preferences from custom directory. Falling back to local copy.";
            alert.informativeText = [NSString stringWithFormat:@"Missing or malformed file at \"%@\"",
                                     [self customFolderOrURL]];
            [alert runModal];
        }
    }
    DLog(@"Done");
    return remotePrefs;
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
                                   silenceable:kiTermWarningTypePersistent
                                        window:nil] == kiTermWarningSelection1) {
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
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Preferences cannot be copied to a URL.";
        alert.informativeText = informativeText;
        [alert runModal];
        return;
    }

    NSString *filename = [self prefsFilenameWithBaseDir:folder];
    NSDictionary *myDict = iTermRemotePreferencesSave(iTermUserDefaultsDictionary(self.preservedKeys), filename);
    if (!myDict) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Failed to copy preferences to custom directory.";
        alert.informativeText = [NSString stringWithFormat:@"Tried to copy %@ to %@",
                                 [self remotePrefsLocation], filename];
        [alert runModal];
    } else {
        self.savedRemotePrefs = myDict;
    }
}

- (BOOL)shouldSaveAutomatically {
    if (![iTermPreferences boolForKey:kPreferenceKeyNeverRemindPrefsChangesLostForFileHaveSelection]) {
        return NO;
    }
    return [iTermPreferences integerForKey:kPreferenceKeyNeverRemindPrefsChangesLostForFileSelection] == iTermPreferenceSavePrefsModeAlways;
}

- (void)setNeedsSave {
    if (_needsSave) {
        return;
    }
    DLog(@"setNeedsSave\n%@", [NSThread callStackSymbols]);
    _needsSave = YES;
    __weak __typeof(self) weakSelf = self;
    // Introduce a delay to avoid building up a big queue.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf saveIfNeeded];
    });
}

static NSDictionary *iTermUserDefaultsDictionary(NSArray<NSString *> *preservedKeys) {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *myDict =
        [userDefaults persistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
    return [myDict filteredWithBlock:^BOOL(id key, id value) {
        NSString *stringKey = [NSString castFrom:key];
        if (!stringKey) {
            return YES;
        }
        return iTermRemotePreferencesKeyIsSyncable(key, preservedKeys);
    }];
}

// Runs either on a background queue or on the main thread. Synchronous. Returns the saved values.
static NSDictionary *iTermRemotePreferencesSave(NSDictionary *myDict, NSString *filename) {
    NSData *data = [myDict it_xmlPropertyList];
    if (!data) {
        DLog(@"Failed to encode %@", myDict);
        return nil;
    }
    NSError *error = nil;
    const BOOL ok = [data writeToFile:[filename stringByResolvingSymlinksInPath] options:NSDataWritingAtomic error:&error];
    if (!ok) {
        DLog(@"Failed to save to %@: %@", filename, error);
        return nil;
    }
    return myDict;
}

- (NSDictionary *)userDefaultsDictionary {
    return iTermUserDefaultsDictionary([self preservedKeys]);
}

- (void)saveIfNeeded {
    if (!_needsSave) {
        return;
    }
    NSString *folder = [self expandedCustomFolderOrURL];
    if ([folder stringIsUrlLike]) {
        return;
    }
    if (!_queue) {
        _queue = dispatch_queue_create("com.iterm2.save-prefs", DISPATCH_QUEUE_SERIAL);
    }
    NSString *filename = [self prefsFilenameWithBaseDir:folder];
    NSArray<NSString *> *preservedKeys = [self.preservedKeys copy];
    _needsSave = NO;
    dispatch_async(_queue, ^{
        DLog(@"Save prefs to %@", filename);
        NSDictionary *dict = iTermRemotePreferencesSave(iTermUserDefaultsDictionary(preservedKeys), filename);
        DLog(@"Finished saving prefs to %@", filename);
        if (dict) {
            self.savedRemotePrefs = dict;
        }
    });
}

- (void)copyRemotePrefsToLocalUserDefaultsPreserving:(NSArray<NSString *> *)preservedKeys {
    DLog(@"Begin");
    if (_haveTriedToLoadRemotePrefs) {
        DLog(@"Return immediately");
        return;
    }

    DLog(@"Add observers");
    _haveTriedToLoadRemotePrefs = YES;
    _userDefaultsObserver = [[iTermUserDefaultsObserver alloc] init];
    __weak __typeof(self) weakSelf = self;
    [_userDefaultsObserver observeAllKeysWithBlock:^{
        if ([weakSelf shouldSaveAutomatically]) {
            [weakSelf setNeedsSave];
        }
    }];
    if (!self.shouldLoadRemotePrefs) {
        DLog(@"Disabled");
        return;
    }
    NSDictionary *remotePrefs = [self freshCopyOfRemotePreferences];
    self.savedRemotePrefs = remotePrefs;
    self.preservedKeys = preservedKeys;

    if (![remotePrefs count]) {
        return;
    }
    DLog(@"Load local prefs");
    NSDictionary *localPrefs = [[NSUserDefaults standardUserDefaults] persistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
    // Empty out the current prefs
    DLog(@"Remove non-syncable values");
    int count = 0;
    for (NSString *key in localPrefs) {
        if ([self preferenceKeyIsSyncable:key]) {
            count += 1;
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
        }
    }
    DLog(@"Removed %d keys", count);
    DLog(@"Copy remote values to user defaults");
    for (NSString *key in remotePrefs) {
        if ([self preferenceKeyIsSyncable:key]) {
            [[NSUserDefaults standardUserDefaults] setObject:[remotePrefs objectForKey:key]
                                                      forKey:key];
        }
    }
    DLog(@"Finished");
    return;
}

- (NSDictionary *)removeDynamicProfiles:(NSDictionary *)source {
    NSMutableDictionary *copy = [source mutableCopy];
    copy[KEY_NEW_BOOKMARKS] = [[iTermDynamicProfileManager sharedInstance] profilesByRemovingDynamicProfiles:source[KEY_NEW_BOOKMARKS]];
    return copy;
}

- (BOOL)localPrefsDifferFromSavedRemotePrefs
{
    if (!self.shouldLoadRemotePrefs) {
        return NO;
    }
    NSDictionary *saved = [self removeDynamicProfiles:self.savedRemotePrefs];
    if (saved && [saved count]) {
        // Grab all prefs from our bundle only (no globals, etc.).
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        NSDictionary *localPrefs =
            [userDefaults persistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        localPrefs = [self removeDynamicProfiles:localPrefs];

        // Iterate over each set of prefs and validate that the other has the same value for each
        // key.
        for (NSString *key in localPrefs) {
            if ([self preferenceKeyIsSyncable:key] &&
                ![[saved objectForKey:key] isEqual:[localPrefs objectForKey:key]]) {
                return YES;
            }
        }

        for (NSString *key in saved) {
            if ([self preferenceKeyIsSyncable:key] &&
                ![[saved objectForKey:key] isEqual:[localPrefs objectForKey:key]]) {
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
    NSDictionary *saved = self.savedRemotePrefs;
    if (!saved) {
        return NO;
    }
    if (self.remoteLocationIsURL) {
        return NO;
    }
    DLog(@"Begin equality comparison");
    const BOOL result = ![[self freshCopyOfRemotePreferences] isEqual:saved];
    DLog(@"result=%@", @(result));
    return result;
}

- (void)applicationWillTerminate {
    if ([self localPrefsDifferFromSavedRemotePrefs]) {
        if (self.remoteLocationIsURL) {
            // If the setting is always copy, then ask. Copying isn't an option.
            [[NSUserDefaults standardUserDefaults] setObject:[self remotePrefsLocation] forKey:iTermRemotePreferencesPromptBeforeLoadingPrefsFromURL];
        } else {
            // Not a URL
            NSString *theTitle = [NSString stringWithFormat:
                                  @"Preferences have changed. Copy them to %@?",
                                  [self customFolderOrURL]];

            iTermWarningSelection selection =
                [iTermWarning showWarningWithTitle:theTitle
                                           actions:@[ @"Copy", @"Lose Changes" ]
                                        identifier:@"NoSyncNeverRemindPrefsChangesLostForFile"
                                       silenceable:kiTermWarningTypePermanentlySilenceable
                                            window:nil];
            if (selection == kiTermWarningSelection0) {
                [self saveLocalUserDefaultsToRemotePrefs];
            }
        }
    } else if(self.savedRemotePrefs != nil) {
        [[NSUserDefaults standardUserDefaults] setObject:nil
                                                  forKey:iTermRemotePreferencesPromptBeforeLoadingPrefsFromURL];
    }
}

- (BOOL)remoteLocationIsURL {
    NSString *customFolderOrURL = [self expandedCustomFolderOrURL];
    return [customFolderOrURL stringIsUrlLike];
}

@end
