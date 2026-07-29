//
// Created by George Nachman on 4/2/14.
//

#import "iTermRemotePreferences.h"

#import "DebugLogging.h"
#import "NSDictionary+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSStringITerm.h"
#import "NSURL+iTerm.h"
#import "PreferencePanel.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermDynamicProfileManager.h"
#import "iTermGraphicSource.h"
#import "iTermPreferences.h"
#import "iTermProfilePreferences.h"
#import "iTermSnippetsModel.h"
#import "iTermUserDefaults.h"
#import "iTermUserDefaultsObserver.h"
#import "iTermWarning.h"
#import "iTerm2SharedARC-Swift.h"
#import "ToolNotes.h"

static NSString *iTermRemotePreferencesPromptBeforeLoadingPrefsFromURL = @"NoSyncPromptBeforeLoadingPrefsFromURL";
// Maps each custom folder path to the content signature of the data files that the local copy and
// that folder last agreed on. Persisted so un-pushed local edits (e.g. after a crash) are detected
// across launches instead of being silently overwritten by the remote copy on load.
static NSString *const iTermRemoteDataFileSyncBaselineSignaturesKey = @"NoSyncRemoteDataFileSyncBaselineSignatures";
// Per-machine, per-folder consent for syncing data files (snippets/notes/icon customizations):
// a dictionary mapping folder path to @YES/@NO (a folder absent from the dict has not been asked).
// Per-machine (NoSync) because it is a privacy decision about publishing this machine's content;
// per-folder because consenting to one destination must not silently publish to a different one.
static NSString *const iTermRemoteDataFileSyncConsentKey = @"NoSyncSyncDataFilesWithCustomFolder";
// Per-folder marker (folder path -> @YES) set when a "Lose Changes" discard could not fully delete
// the local data files (a disk error mid-delete). Persisted (NoSync, local-only) so the next launch's
// reconcile RETRIES the deletion instead of taking the "only remote moved" re-publish branch, which
// would push the surviving items the user chose to lose. Discard is only reachable from the quit
// prompts, so without this the partial-failure state would silently invert into a publish one launch
// later.
static NSString *const iTermRemoteDataFileSyncDiscardPendingKey = @"NoSyncRemoteDataFileSyncDiscardPending";
// Per-folder record (folder path -> local signature) of the local data-file signature at the moment
// of the last successful push. The baseline records the FOLDER's signature (for the divergence
// guard); when the folder holds an allowlisted item the local copy lacks (a locally-deleted file the
// union push can't delete), the baseline can never equal the local signature, so a baseline-only
// "did anything change" check would re-push (and re-hash the whole remote subtree on the main thread)
// on every autosave forever. Comparing the local signature to this instead short-circuits once local
// is unchanged since the last push, while still pushing a genuine later edit.
static NSString *const iTermRemoteDataFileSyncLastPushedLocalKey = @"NoSyncRemoteDataFileSyncLastPushedLocal";
// Upper bound on the FIRST synchronous remote-folder read on the load-reconcile, push, and discard
// paths, so an offline/slow SMB/NFS/iCloud mount degrades to "sync later" instead of hanging the main
// thread (a beachballed quit). A responsive mount returns in well under this; the read is the first
// remote access on each path, so a timeout defers before any mirror read/write is attempted.
static const NSTimeInterval iTermRemoteDataFileSyncRemoteReadTimeout = 5.0;

@interface iTermRemotePreferences ()
@property(atomic, copy) NSDictionary *savedRemotePrefs;
@property(nonatomic, copy) NSArray<NSString *> *preservedKeys;
// interactive is YES only for genuinely user-driven saves (a settings button, the unsaved-changes
// controller). The quit path passes NO so the consent-undecided reconcile (which shows a modal)
// never runs during termination, where it might never be answered; it defers to the next launch.
- (void)saveLocalUserDefaultsToRemotePrefsInteractive:(BOOL)interactive;
@end

@implementation iTermRemotePreferences {
    BOOL _haveTriedToLoadRemotePrefs;
    iTermUserDefaultsObserver *_userDefaultsObserver;
    BOOL _needsSave;
    // Like _needsSave but for a data-file-only push (snippet edits) that must NOT rewrite the whole
    // prefs plist and clobber another machine's plist changes.
    BOOL _needsDataFileSave;
    // Coalesces deferReconcileThenArmPushForFolder: so repeated triggers (e.g. a debounced global-notes
    // save posting while a reconcile modal is open) don't each stack an independent re-arm chain. Set
    // when a deferred reconcile is armed, cleared when its block runs. Without this (and the 0.5s delay)
    // the re-arm busy-spun the main thread while a modal drained the main queue.
    BOOL _deferredReconcilePending;
    dispatch_queue_t _queue;
    // > 0 while we are applying remote data files to the local copy, so the resulting change
    // notifications don't trigger an immediate write back. A depth counter (not a BOOL) so a nested
    // apply can't clear an outer one's suppression mid-import, matching _reconcilingDataFilesDepth.
    NSInteger _applyingRemoteDataFilesDepth;
    // > 0 while a data-file reconcile or a quit-time data-file confirm is in progress, including its
    // consent/conflict modals. A modal's runloop drains the debounced-save main-queue block, so
    // without this a background push could write local data to the folder while the user is still
    // choosing, defeating their choice. A counter (not a bool) because a snippet-change observer can
    // schedule a nested reconcile that runs inside an outer modal; an unconditional reset would clear
    // the flag while the outer modal is still open. writeDataFilesToRemoteFolder: checks this.
    NSInteger _reconcilingDataFilesDepth;
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
    if ([base.pathExtension isEqualToString:@"plist"] &&
        [[NSFileManager defaultManager] fileExistsAtPath:base]) {
        return base;
    }
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
                             @"MetalCaptureEnabledDate",
                             // Snippets sync through their own snippets.plist channel. This key is only
                             // ever set as a crash-recovery fallback (a failed snippets.plist write),
                             // never a real setting; syncing it through the prefs plist would let a
                             // machine in the fallback state publish a stale array that then clobbers
                             // the freshly-synced snippets.plist on every machine.
                             kPreferenceKeySnippets];
    return ![exemptKeys containsObject:key] &&
            ![key hasPrefix:@"NS"] &&
            ![key hasPrefix:@"SU"] &&
            ![key hasPrefix:@"NoSync"] &&
            ![key hasPrefix:@"UK"];
}

- (BOOL)preferenceKeyIsSyncable:(NSString *)key {
    return iTermRemotePreferencesKeyIsSyncable(key, self.preservedKeys);
}

- (NSData *)loadFromURL:(NSURL *)url
respectingTimeoutSetting:(BOOL)respectingTimeoutSetting
                  error:(out NSError **)errorPtr {
    const NSTimeInterval timeout = respectingTimeoutSetting ? [iTermAdvancedSettingsModel noSyncDownloadPrefsTimeout] : INFINITY;
    NSURLRequest *req = [NSURLRequest requestWithURL:url
                                         cachePolicy:NSURLRequestUseProtocolCachePolicy
                                     timeoutInterval:timeout];
    __block NSError *error = nil;
    __block NSData *data = nil;

    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    RLog(@"Create task for %@", url);
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData * _Nullable taskData,
                                                                             NSURLResponse * _Nullable taskResponse,
                                                                             NSError * _Nullable taskError) {
        RLog(@"Task progressing with %@ bytes", @(taskData.length));
        data = taskData;
        error = taskError;
        dispatch_semaphore_signal(sema);
    }];
    DLog(@"Resume task");
    [task resume];
    DLog(@"Wait for completion");
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    DLog(@"Download completed");

    if (errorPtr) {
        *errorPtr = error;
    }
    return data;
}

- (NSData *)didFailToLoadFromURL:(NSURL *)url withError:(NSError *)error {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Failed to load settings from URL. Falling back to local copy.";
    alert.informativeText = [NSString stringWithFormat:@"HTTP request failed: %@",
                             [error localizedDescription] ?: @"unknown error"];
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Reveal in Settings"];
    if ([error.domain isEqual:NSURLErrorDomain] && error.code == NSURLErrorTimedOut) {
        [alert addButtonWithTitle:@"Try Again Without Timeout"];
    }

    const NSModalResponse response = [alert runModal];
    if (response == NSAlertSecondButtonReturn) {
        [[PreferencePanel sharedInstance] openToPreferenceWithKey:kPreferenceKeyLoadPrefsFromCustomFolder];
    } else if (response == NSAlertThirdButtonReturn) {
        NSError *innerError = nil;
        NSData *data = [self loadFromURL:url respectingTimeoutSetting:NO error:&innerError];
        if (!data || innerError) {
            return [self didFailToLoadFromURL:url withError:innerError];
        }
        return data;
    }
    return nil;
}

- (NSDictionary *)freshCopyOfRemotePreferences {
    if (!self.shouldLoadRemotePrefs) {
        return nil;
    }

    NSString *filename = [self remotePrefsLocation];
    NSDictionary *remotePrefs;
    if ([filename stringIsUrlLike]) {
        DLog(@"Is URL");
        NSString *promptURL = [[iTermUserDefaults userDefaults] objectForKey:iTermRemotePreferencesPromptBeforeLoadingPrefsFromURL];
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
                    RLog(@"Keep local changes");
                    return nil;
                case kiTermWarningSelection1:
                    RLog(@"Disable url");
                    [iTermPreferences setBool:NO forKey:kPreferenceKeyLoadPrefsFromCustomFolder];
                    [[iTermUserDefaults userDefaults] setObject:nil
                                                              forKey:iTermRemotePreferencesPromptBeforeLoadingPrefsFromURL];
                    return nil;
                case kiTermWarningSelection2:
                    RLog(@"Discard local");
                    [[iTermUserDefaults userDefaults] setObject:nil
                                                              forKey:iTermRemotePreferencesPromptBeforeLoadingPrefsFromURL];
                    break;
                default:
                    break;
            }
        }
        // Download the URL's contents.
        NSURL *url = [NSURL URLWithUserSuppliedString:filename];
        NSError *error = nil;
        NSData *data = [self loadFromURL:url respectingTimeoutSetting:YES error:&error];
        if (!data || error) {
            data = [self didFailToLoadFromURL:url withError:error];
            if (!data) {
                return nil;
            }
        }

        remotePrefs = [NSDictionary it_dictionaryWithContentsOfData:data];
    } else {
        RLog(@"Will load dictionary from %@", filename);
        remotePrefs = [NSDictionary dictionaryWithContentsOfFile:filename];
        DLog(@"Did load dictionary from %@", filename);
    }
    if (!remotePrefs.count) {
        RLog(@"It's empty");
        if ([[self customFolderOrURL] length] == 0) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Error Loading Settings";
            alert.informativeText = @"You have enabled “Load settings from a custom folder or URL” in settings but the location is not set.";
            [alert addButtonWithTitle:@"Don’t Load Remote Settings"];
            [alert addButtonWithTitle:@"Cancel"];
            if ([alert runModal] == NSAlertFirstButtonReturn) {
                [iTermPreferences setBool:NO forKey:kPreferenceKeyLoadPrefsFromCustomFolder];
            }
        } else {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Failed to load settings from custom directory. Falling back to local copy.";
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

- (void)saveLocalUserDefaultsToRemotePrefs {
    // Public entry points (settings buttons, the unsaved-changes controller) are user-driven.
    [self saveLocalUserDefaultsToRemotePrefsInteractive:YES];
}

- (void)saveLocalUserDefaultsToRemotePrefsInteractive:(BOOL)interactive
{
    DLog(@"saveLocalUserDefaultsToRemotePrefs interactive=%@\n%@", @(interactive), [NSThread callStackSymbols]);
    if ([self remotePrefsHaveChanged]) {
        NSString *theTitle =
            [NSString stringWithFormat:@"Settings at %@ changed since iTerm2 started. "
                                       @"Overwrite it?",
                                       [self customFolderOrURL]];
        if ([iTermWarning showWarningWithTitle:theTitle actions:@[ @"Overwrite",
                                                                   @"Discard Local Changes" ]
                                    identifier:nil
                                   silenceable:kiTermWarningTypePersistent
                                        window:nil] == kiTermWarningSelection1) {
            // The user declined to overwrite the remote PREFS PLIST (it changed since launch). That
            // decision is about the plist only; the data files are independent, so still push them
            // rather than swallowing the caller's intent to copy them. Push NON-interactively even on an
            // interactive save: the user just dismissed one modal, so stacking a second, unrelated
            // data-file consent/conflict modal on top of that decline would be surprising. A non-
            // interactive push is a silent no-op if consent/baseline aren't established yet; that just
            // defers first-time data-file setup to the next launch. (This branch is non-URL:
            // remotePrefsHaveChanged returns NO for URL destinations.)
            [self pushDataFilesToFolder:[self expandedCustomFolderOrURL] interactive:NO];
            return;
        }
    }

    [[iTermUserDefaults userDefaults] synchronize];

    NSString *folder = [self expandedCustomFolderOrURL];
    if ([folder stringIsUrlLike]) {
        NSString *informativeText =
            @"To make it available, first quit iTerm2 and then manually "
            @"copy ~/Library/Preferences/com.googlecode.iterm2.plist to "
            @"your hosting provider.";
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Settings cannot be copied to a URL.";
        alert.informativeText = informativeText;
        [alert runModal];
        return;
    }

    NSString *filename = [self prefsFilenameWithBaseDir:folder];
    NSDictionary *myDict = iTermRemotePreferencesSave(iTermUserDefaultsDictionary(self.preservedKeys), filename);
    if (!myDict) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Failed to copy settings to custom directory.";
        alert.informativeText = [NSString stringWithFormat:@"Tried to copy %@ to %@",
                                 [self remotePrefsLocation], filename];
        [alert runModal];
    } else {
        self.savedRemotePrefs = myDict;
    }
    [self pushDataFilesToFolder:folder interactive:interactive];
}

// Push the synced data files to the folder. A user-driven save ("Save Now") runs the FULL three-way
// reconcile first; a silent/quit save (interactive == NO) skips it and only pushes (it must never show a
// modal). The fall-through push then publishes the only-local / first-enable case the reconcile
// intentionally defers, and is a no-op otherwise.
- (void)pushDataFilesToFolder:(NSString *)folder interactive:(BOOL)interactive {
    if (!self.shouldLoadRemotePrefs || self.remoteLocationIsURL || !folder.length) {
        return;
    }
    if (interactive) {
        // Run the full reconcile, not just first-time consent/baseline setup. This is the ONLY
        // interactive entry point for data files, so it must be where a genuine both-sides conflict
        // surfaces the "keep this Mac's / the folder's" prompt (resolveDataFileConflictWithRemoteFolder).
        // Without this, an established-folder Save Now fell straight into the silent
        // writeDataFilesToRemoteFolder: push, which DEFERS on any remote divergence - so a real conflict
        // produced no push and no prompt, just a silent no-op until the next launch. The reconcile also
        // handles the other cases coherently: in-agreement no-ops; only-remote pulls the newer copy (so
        // Save Now doubles as a sync); only-local adopts the baseline and relies on the push below to
        // publish (the reconcile defers the only-local push to "next save" because at LOAD time the
        // models haven't read their files yet). It also still covers the first-time and the persisted
        // consent=YES/baseline=nil states the old narrow condition targeted, since the stored consent
        // answer short-circuits the prompt and it just establishes the baseline. Reentrancy-safe: the
        // reconcile fully completes and drops _reconcilingDataFilesDepth before the push runs.
        [self reconcileDataFilesWithRemoteFolder:folder];
    }
    [self writeDataFilesToRemoteFolder:folder];
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

// Debounced push of just the data files (used for snippet edits). Unlike setNeedsSave, this does NOT
// rewrite the prefs plist, so a snippet edit can't clobber prefs another machine wrote to the folder
// since this machine launched.
- (void)setNeedsDataFileSave {
    if (_needsDataFileSave) {
        return;
    }
    _needsDataFileSave = YES;
    __weak __typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (strongSelf->_reconcilingDataFilesDepth > 0 || strongSelf->_applyingRemoteDataFilesDepth > 0) {
            // A reconcile/conflict/quit modal is up (or a remote->local apply is in flight).
            // writeDataFilesToRemoteFolder: would no-op right now, so clearing _needsDataFileSave and
            // pushing here would silently drop this pending save. Re-arm instead so the push happens
            // once the modal closes. (Clear first because setNeedsDataFileSave early-returns when the
            // flag is already set.)
            strongSelf->_needsDataFileSave = NO;
            [strongSelf setNeedsDataFileSave];
            return;
        }
        strongSelf->_needsDataFileSave = NO;
        if (!strongSelf.remoteLocationIsURL) {
            [strongSelf writeDataFilesToRemoteFolder:[strongSelf expandedCustomFolderOrURL]];
        }
    });
}

static NSDictionary *iTermUserDefaultsDictionary(NSArray<NSString *> *preservedKeys) {
    NSUserDefaults *userDefaults = [iTermUserDefaults userDefaults];
    NSDictionary *myDict =
        [userDefaults persistentDomainForName:[iTermUserDefaults customSuiteName] ?: [[NSBundle mainBundle] bundleIdentifier]];
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
        RLog(@"Failed to save to %@: %@", filename, error);
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
    // Sync data files on the main thread (small files, and the first-run guard may show a warning).
    [self writeDataFilesToRemoteFolder:folder];
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

// Pushes the synced data files (snippets, notes, icon customizations) to <folder>/Data. Always runs
// silently (consent and first-contact/conflict modals all live in the reconcile, not here). Must run
// on the main thread because it reads _applyingRemoteDataFilesDepth/_reconcilingDataFilesDepth, which are
// only mutated on the main thread. No-ops for an empty folder, an un-reconciled folder, during a
// remote->local load, or when nothing has changed since the last sync.
- (void)writeDataFilesToRemoteFolder:(NSString *)folder {
    [self writeDataFilesToRemoteFolder:folder localSignature:nil];
}

// localSignature is an optional precomputed local signature so a caller that already hashed the
// local data files this turn (e.g. the quit path, to choose the prompt) doesn't pay to hash the
// possibly-large notes.rtfd twice. Pass nil to compute it here (after the cheap guards).
//
// Perf note: the LOCAL-signature guard below short-circuits before touching the remote whenever the
// local copy matches the baseline (the common autosave case), so the remote is not read at all then.
// Only an actual push (local diverged) reads the remote subtree, and it reads it twice: once for
// copyLocalToRemote's divergence guard and once for mirror's per-item skip-identical pass. (The
// post-push baseline is composed from the LOCAL copy via remoteBaselineAfterUnionPush, so it adds no
// third full remote read except for any folder-only extras.) On a multi-MB notes.rtfd over
// Dropbox/iCloud/NFS these two reads are a synchronous main-thread stall; folding the divergence
// check into mirror's per-item digest pass (one read) or comparing a persisted per-item stat
// fingerprint before hashing bytes is a future optimization, deferred here to avoid the added
// persistence/invalidation complexity in this pass.
- (void)writeDataFilesToRemoteFolder:(NSString *)folder localSignature:(NSString *)localSignature {
    if (!folder.length || _applyingRemoteDataFilesDepth > 0 || _reconcilingDataFilesDepth > 0) {
        return;
    }
    // Data-file sync rides on loading from a custom folder, and consent plus first-contact handling
    // (foreign files, conflicts) all happen in the load-time reconcile. This path runs from the
    // debounced autosave and on quit, so it only ever pushes silently and never shows a modal: if
    // the folder has not been reconciled yet (no baseline), defer to the next launch's reconcile
    // rather than overwriting whatever is there.
    if (!self.shouldLoadRemotePrefs ||
        ![self dataFileSyncConsentGrantedForFolder:folder] ||
        ![self dataFileSyncInitializedForFolder:folder]) {
        return;
    }
    if (!localSignature) {
        localSignature = [self readyLocalDataFileSignature];
    }
    if (!localSignature ||
        [localSignature isEqualToString:[self baselineSignatureForFolder:folder]] ||
        [localSignature isEqualToString:[self lastPushedLocalSignatureForFolder:folder]]) {
        // Nil: a local file is currently unreadable (a not-yet-downloaded placeholder); defer rather
        // than push a phantom. Equal to baseline: nothing changed. Equal to the last-pushed local
        // signature: local is unchanged since we last pushed it, so pushing again is pointless. That
        // last check matters when the folder holds an allowlisted item the local copy lacks (a
        // locally-deleted file a union push can't delete): the baseline then permanently differs from
        // localSignature, so without it every autosave would re-hash the whole remote subtree on the
        // main thread forever.
        return;
    }
    // Union push (never deletes the folder's items): we can't prove the folder still matches what we
    // last saw, so deleting folder-only items here could destroy another machine's data. Deletion
    // propagation is the pull's job, not the push's.
    //
    // Do the divergence guard HERE (rather than passing expectedRemoteSignature into copyLocalToRemote)
    // so we can tell a "folder moved under us" defer apart from a partial-write failure. mirrorAll is
    // not atomic across items: a copy that fails partway (disk full / EIO / a later item evicted) may
    // have already committed earlier items, so a false return can mean the folder was left partially
    // written. If we treated that like a foreign divergence and left the baseline alone, THIS machine
    // would read its own partial push as a foreign edit next launch and fire a spurious conflict.
    NSString *baseline = [self baselineSignatureForFolder:folder];
    NSString *folderBeforePush = [iTermRemoteDataFileSync remoteContentSignatureWithRemoteFolder:folder
                                                                                  timeoutSeconds:iTermRemoteDataFileSyncRemoteReadTimeout];
    if (folderBeforePush.length == 0) {
        // Folder momentarily unreadable (or a read timeout on an offline mount); defer rather than push.
        return;
    }
    if (![folderBeforePush isEqualToString:baseline]) {
        // The folder moved since our launch (another machine wrote it). Defer to the next launch's
        // reconcile conflict prompt rather than overwriting its newer items.
        return;
    }
    // Folder == baseline: safe to push. Force it (nil guard) since we just verified no divergence.
    if ([iTermRemoteDataFileSync copyLocalToRemoteWithRemoteFolder:folder]) {
        // Adopt the folder's ACTUAL post-push signature, not localSignature. A union push never
        // deletes the folder's items, so if the folder held an item local lacks (e.g. the user
        // deleted a file locally, which does not propagate), the post-push folder is local UNION those
        // items and its signature differs from localSignature; recording localSignature would leave
        // baseline != folder and stall every later push. remoteBaselineAfterUnionPush composes that
        // signature from the local copy (race-free for the pushed items), reading the folder only for
        // any extras.
        NSString *postPushSignature = [iTermRemoteDataFileSync remoteBaselineAfterUnionPushWithRemoteFolder:folder];
        if (postPushSignature.length == 0) {
            // A folder-only extra became unreadable between the guard and this compose. The push already
            // mutated the folder, so leaving the stale baseline would defer every later push this
            // session and fire a spurious next-launch conflict. Fall back to a direct (bounded) re-hash
            // of the folder (also a retry; a placeholder may have materialized).
            postPushSignature = [iTermRemoteDataFileSync remoteContentSignatureWithRemoteFolder:folder
                                                                                timeoutSeconds:iTermRemoteDataFileSyncRemoteReadTimeout];
        }
        if (postPushSignature.length > 0) {
            [self adoptDataFileSignature:postPushSignature forFolder:folder];
            // Record the local signature we just pushed, so this session does not re-push (and re-hash
            // the whole remote subtree) until local actually changes again. Only when the baseline was
            // actually recorded: if BOTH reads returned "" the baseline stayed stale, and advancing
            // lastPushedLocal against a stale baseline would suppress the corrective re-push AND fire a
            // spurious next-launch conflict. Leaving lastPushedLocal too keeps them consistent so the
            // next launch's reconcile repairs both.
            [self setLastPushedLocalSignature:localSignature forFolder:folder];
        } else {
            DLog(@"Post-push folder signature unreadable; leaving baseline and lastPushedLocal for next launch to reconcile");
        }
    } else {
        // The push failed, possibly PARTWAY (some items committed to the folder before the failure).
        // The folder == baseline check above ran before the push, so a folder != baseline now is ALMOST
        // ALWAYS our own partial write, not a foreign edit. Record the folder's ACTUAL signature as the
        // baseline so the next launch reads "only local moved" and retries the rest, rather than a
        // spurious self-conflict. (adoptDataFileSignature keeps lastPushedLocal only when the baseline is
        // unchanged; here a real partial write advances it, correctly clearing lastPushedLocal so the
        // retry isn't short-circuited.)
        //
        // Caveat: it is NOT guaranteed to be our own write. If another machine rewrote a SHARED item in
        // the narrow window between the guard and the failure, adopting the folder's signature bakes that
        // foreign edit into our baseline, so the next push overwrites it with no "which copy?" prompt.
        // That is the accepted last-writer-wins limitation documented atop copyLocalToRemote (the loser's
        // edit survives in the mirror backup); deferring instead would fire a spurious self-conflict on
        // every ordinary partial-push failure, which is the far more common case.
        //
        // Bounded read: the push just returned NO, strongly correlated with the mount going unresponsive.
        NSString *folderAfterFailedPush = [iTermRemoteDataFileSync remoteContentSignatureWithRemoteFolder:folder
                                                                                          timeoutSeconds:iTermRemoteDataFileSyncRemoteReadTimeout];
        if (folderAfterFailedPush.length > 0 && ![folderAfterFailedPush isEqualToString:baseline]) {
            DLog(@"Push failed partway; adopting the folder's actual signature so the partial write isn't misread as a foreign edit");
            [self adoptDataFileSignature:folderAfterFailedPush forFolder:folder];
        }
    }
}

// The local data-file signature, or nil if it can't be computed right now (a present file is
// unreadable, e.g. a not-yet-downloaded placeholder), in which case callers should defer rather than
// act on a phantom signature.
- (NSString *)readyLocalDataFileSignature {
    NSString *signature = [iTermRemoteDataFileSync localContentSignature];
    return signature.length == 0 ? nil : signature;
}

// A folder is "initialized" once we have a recorded baseline for it.
- (BOOL)dataFileSyncInitializedForFolder:(NSString *)folder {
    return [self baselineSignatureForFolder:folder] != nil;
}

// Read/write one folder's entry in a persisted per-folder NoSync dictionary (folder path -> value).
// Centralizes the read-modify-write so a future change to how these dicts are persisted (key
// migration, nil-pruning) is made once instead of at every call site. A nil value removes the entry.
- (id)dataFileValueForFolder:(NSString *)folder key:(NSString *)key {
    NSDictionary *dict = [NSDictionary castFrom:[[iTermUserDefaults userDefaults] objectForKey:key]];
    return dict[folder];
}

- (void)setDataFileValue:(id)value forFolder:(NSString *)folder key:(NSString *)key {
    NSDictionary *existing = [NSDictionary castFrom:[[iTermUserDefaults userDefaults] objectForKey:key]];
    NSMutableDictionary *updated = [(existing ?: @{}) mutableCopy];
    updated[folder] = value;
    [[iTermUserDefaults userDefaults] setObject:updated forKey:key];
}

// The single source of truth for "what the local copy and this folder last agreed on", persisted per
// folder so the next launch can tell a local un-pushed edit from newer folder data.
- (NSString *)baselineSignatureForFolder:(NSString *)folder {
    return [NSString castFrom:[self dataFileValueForFolder:folder key:iTermRemoteDataFileSyncBaselineSignaturesKey]];
}

- (void)adoptDataFileSignature:(NSString *)signature forFolder:(NSString *)folder {
    NSString *existing = [self baselineSignatureForFolder:folder];
    [self setDataFileValue:signature forFolder:folder key:iTermRemoteDataFileSyncBaselineSignaturesKey];
    // Invalidate the "local unchanged since last push" short-circuit only when the baseline VALUE
    // actually changes. lastPushedLocal is meaningful relative to the baseline it was paired with; a
    // pull/reconcile that adopts a DIFFERENT baseline (e.g. after another machine's edit) must not let a
    // stale lastPushedLocal suppress re-pushing content that has since diverged and been locally
    // reverted. But RE-adopting the SAME baseline must NOT clear it: the launch-time "only local moved"
    // branch re-writes the unchanged remote signature every launch, and clearing lastPushedLocal there
    // would re-fire a spurious quit prompt (and, on "Lose Changes", resurrect a locally-deleted file) in
    // the steady state where a locally-deleted synced file keeps local permanently != baseline.
    if (![signature isEqualToString:existing]) {
        [self setLastPushedLocalSignature:nil forFolder:folder];
    }
}

- (NSString *)lastPushedLocalSignatureForFolder:(NSString *)folder {
    return [NSString castFrom:[self dataFileValueForFolder:folder key:iTermRemoteDataFileSyncLastPushedLocalKey]];
}

- (void)setLastPushedLocalSignature:(NSString *)signature forFolder:(NSString *)folder {
    [self setDataFileValue:signature forFolder:folder key:iTermRemoteDataFileSyncLastPushedLocalKey];
}

- (BOOL)dataFileDiscardPendingForFolder:(NSString *)folder {
    return [[NSNumber castFrom:[self dataFileValueForFolder:folder key:iTermRemoteDataFileSyncDiscardPendingKey]] boolValue];
}

- (void)setDataFileDiscardPending:(BOOL)pending forFolder:(NSString *)folder {
    [self setDataFileValue:(pending ? @YES : nil) forFolder:folder key:iTermRemoteDataFileSyncDiscardPendingKey];
}

// Cheap, signature-independent gate: is data-file sync active for the current folder (load enabled,
// non-URL, consented, and already reconciled)? Callers use this to avoid paying an expensive local
// signature hash when the answer is trivially no (the common case: no folder sync configured).
- (BOOL)dataFileSyncActiveForCurrentFolder {
    NSString *folder = [self expandedCustomFolderOrURL];
    return (self.shouldLoadRemotePrefs &&
            !self.remoteLocationIsURL &&
            [self dataFileSyncConsentGrantedForFolder:folder] &&
            [self baselineSignatureForFolder:folder] != nil);
}

// localSignature is the precomputed local signature (or nil if unreadable), so the quit path can
// hash the data files once and reuse the result for both the prompt wording and the push.
- (BOOL)localDataFilesDifferFromSavedGivenSignature:(NSString *)localSignature {
    // A nil signature means a local file is currently unreadable (a placeholder); defer rather than
    // report a phantom difference.
    if (!localSignature || ![self dataFileSyncActiveForCurrentFolder]) {
        return NO;
    }
    NSString *folder = [self expandedCustomFolderOrURL];
    // Mirror the push path's guard exactly: local counts as "not differing" when it equals the
    // baseline OR the last-pushed local signature. Without the lastPushedLocal check, a folder that
    // holds an allowlisted item the local copy lacks (a locally-deleted file the union push can't
    // propagate) makes baseline permanently differ from localSignature, so every quit would show a
    // spurious "copy them?" prompt, and picking "Lose Changes" would pull the folder and RESURRECT the
    // deleted file.
    if ([localSignature isEqualToString:[self baselineSignatureForFolder:folder]] ||
        [localSignature isEqualToString:[self lastPushedLocalSignatureForFolder:folder]]) {
        return NO;
    }
    return YES;
}

// Pure check: has the user already opted in to data-file sync for this folder? No prompt and no
// side effects, so it is safe to call from predicates and from the debounced save/quit paths.
// Consent is per-folder because publishing this machine's notes/snippets to a new destination is a
// fresh privacy decision: consenting to folder A must not silently push to a different folder B.
- (BOOL)dataFileSyncConsentGrantedForFolder:(NSString *)folder {
    if (!folder.length) {
        return NO;
    }
    return [[NSNumber castFrom:[self dataFileValueForFolder:folder key:iTermRemoteDataFileSyncConsentKey]] boolValue];
}

// Whether the user has already answered the consent question for this folder (yes or no), so callers
// can tell "declined" from "not yet asked" without prompting.
- (BOOL)dataFileSyncConsentDecidedForFolder:(NSString *)folder {
    if (!folder.length) {
        return NO;
    }
    return [self dataFileValueForFolder:folder key:iTermRemoteDataFileSyncConsentKey] != nil;
}

// Whether the user has agreed to sync data files (snippets/notes/icon customizations) with this
// folder, asking once per folder if they haven't been asked. This widens what leaves the machine
// beyond the preferences plist, so it requires a fresh, explicit opt-in rather than riding on the
// existing "load settings from a custom folder" choice. Interactive: only call from the load-time
// reconcile, never from a background save.
- (BOOL)ensureDataFileSyncConsentForFolder:(NSString *)folder {
    if (!folder.length) {
        return NO;
    }
    NSNumber *stored = [NSNumber castFrom:[self dataFileValueForFolder:folder key:iTermRemoteDataFileSyncConsentKey]];
    if (stored != nil) {
        return stored.boolValue;
    }
    if (![iTermRemoteDataFileSync localHasAnyTarget] &&
        ![iTermRemoteDataFileSync remoteHasAnyTargetWithRemoteFolder:folder
                                                      timeoutSeconds:iTermRemoteDataFileSyncRemoteReadTimeout]) {
        // Nothing to sync yet; don't prompt and don't record a choice, so we ask later if data files
        // appear. Bounded: this can be the first remote access on a first-launch reconcile, so an
        // offline mount must not beachball startup (a timeout reads as "no remote target": defer).
        return NO;
    }
    NSString *title =
        [NSString stringWithFormat:@"iTerm2 can also keep your snippets, global notes, and session "
                                   @"icon customizations in the settings folder “%@” so they sync "
                                   @"across machines. Notes and snippets can contain sensitive text "
                                   @"such as passwords or tokens. Sync them too?",
                                   [self customFolderOrURL]];
    const iTermWarningSelection selection =
        [iTermWarning showWarningWithTitle:title
                                   actions:@[ @"Sync These Too", @"Just Settings" ]
                                identifier:nil
                               silenceable:kiTermWarningTypePersistent
                                    window:nil];
    const BOOL consented = (selection == kiTermWarningSelection0);
    [self setDataFileValue:@(consented) forFolder:folder key:iTermRemoteDataFileSyncConsentKey];
    return consented;
}

// Imports the folder's data files into the local copy and refreshes their in-memory owners.
// Guarded so the resulting change notifications don't trigger a write back. deleteMissing must only
// be YES when the caller has confirmed (via the baseline) that the local copy matched the folder's
// last-synced set, so that an item missing from the folder is a real deletion rather than something
// the folder simply never had.
// Returns YES if the folder had a readable Data subtree and the mirror completed (NOT "something was
// actually copied" - it returns YES even when every item was already identical; use changedItems, via
// applyImportedRemoteDataFilesForItems:, to see what actually changed). NO means a real failure or "the
// folder has no Data subtree to pull", which copyRemoteToLocal cannot tell apart.
- (BOOL)pullRemoteDataFilesFromFolder:(NSString *)folder deleteMissing:(BOOL)deleteMissing {
    // Collect exactly which items the pull replaced/deleted so we refresh ONLY those owners. Reloading
    // an unchanged owner is not harmless: telling the notes view to re-read on a snippets-only import
    // would drop a large note's unsaved edits (which only autosave at dealloc). On a partial failure
    // (copied==NO) changedItems still holds whatever was applied before the failure, so those stale
    // in-memory owners are still refreshed.
    NSMutableSet<NSString *> *changedItems = [NSMutableSet set];
    __block BOOL copied = NO;
    [self withApplyingRemoteDataFiles:^{
        copied = [iTermRemoteDataFileSync copyRemoteToLocalWithRemoteFolder:folder
                                                             deleteMissing:deleteMissing
                                                              changedItems:changedItems];
        if (changedItems.count > 0) {
            [self applyImportedRemoteDataFilesForItems:changedItems];
        }
    }];
    return copied;
}

// Discard local data-file edits/additions by replacing them with the folder's copy exactly (mirror
// pull: edited shared items revert, brand-new local-only items are removed, each backed up first so
// it stays recoverable). This is what quit-time "Lose Changes" means for data files, which (unlike
// prefs) have no load-time overwrite to discard them.
- (void)discardLocalDataFileChangesTakingFolder:(NSString *)folder {
    NSString *remoteSignature = [iTermRemoteDataFileSync remoteContentSignatureWithRemoteFolder:folder
                                                                                 timeoutSeconds:iTermRemoteDataFileSyncRemoteReadTimeout];
    if (remoteSignature.length == 0) {
        // The remote is momentarily unreadable (e.g. an offline network mount / read timeout), so we
        // can't take its copy now. Baseline the current LOCAL signature so the next save doesn't push
        // (local == baseline), AND set the discard-pending marker so the next launch routes through
        // retryPendingDataFileDiscardForFolder:. Just baselining local is NOT enough: for LOCAL-ONLY
        // items (folder never held them, e.g. right after enabling sync against an empty folder), the
        // next launch's "only remote moved" branch adopts the all-absent signature but LEAVES the local
        // files, and the next save then PUBLISHES the very sensitive edits the user chose to lose. The
        // marker makes the next launch delete-local (empty folder) or folder-wins-pull (folder has
        // data) instead, honoring the discard in both cases.
        DLog(@"Discard requested but remote unreadable; baselining local and marking discard pending, discard deferred");
        [self setDataFileDiscardPending:YES forFolder:folder];
        [self adoptLocalDataFileSignatureForFolder:folder];
        return;
    }
    // We are committed to discarding (the remote is readable). Clear any un-flushed snippets fallback
    // (backing it up) so removing snippets.plist below isn't undone by the next launch's
    // ensurePersistedToDisk flush resurrecting the discarded snippets. Wrap in withApplyingRemoteDataFiles
    // (matching -retryPendingDataFileDiscardForFolder:) so the reloadFromDisk notification it posts
    // doesn't arm a background push of the just-discarded snippets if this is ever reached off the
    // terminating path.
    [self withApplyingRemoteDataFiles:^{
        [[iTermSnippetsModel sharedInstance] discardUnflushedFallbackBackingUp];
    }];
    if ([remoteSignature isEqualToString:[iTermRemoteDataFileSync allAbsentSignature]]) {
        // The folder's Data subtree is absent (remoteSignature is a non-empty all-ABSENT hash, so the
        // unreadable check above didn't fire). "Take the folder's copy" here means the local items
        // should be removed, but a deleteMissing pull can't mirror from a missing Data dir. Delete the
        // local items ourselves and adopt the remote's all-absent signature. We compare the
        // already-read signature to the all-absent hash rather than doing a second (unbounded)
        // remoteHasAnyTarget probe, which could hang the main thread if the mount dropped in the window
        // since the read above.
        [self discardByDeletingLocalTargetsForFolder:folder allAbsentSignature:remoteSignature];
        return;
    }
    const BOOL pulled = [self pullRemoteDataFilesFromFolder:folder deleteMissing:YES];
    if (pulled) {
        [self adoptDataFileSignature:remoteSignature forFolder:folder];
        return;
    }
    // The pull returned NO even though the folder had data at entry. If the folder's Data subtree was
    // removed by another machine in the window between entry and the pull, the discard still means
    // "remove local": fall into the delete-local path instead of baselining the un-discarded local edits
    // (which the next save would re-publish, inverting the discard). Use a BOUNDED re-read + all-absent
    // comparison to decide, never the unbounded remoteHasAnyTarget probe (which would hang quit if the
    // mount dropped after the pull failed).
    NSString *currentRemote = [iTermRemoteDataFileSync remoteContentSignatureWithRemoteFolder:folder
                                                                              timeoutSeconds:iTermRemoteDataFileSyncRemoteReadTimeout];
    if (currentRemote.length == 0) {
        // Folder momentarily unreadable/timed out: can't confirm it's gone, so don't delete local now.
        // Keep the discard-pending marker and baseline local; the next launch retries the discard.
        [self setDataFileDiscardPending:YES forFolder:folder];
        [self adoptLocalDataFileSignatureForFolder:folder];
        return;
    }
    if ([currentRemote isEqualToString:[iTermRemoteDataFileSync allAbsentSignature]]) {
        [self discardByDeletingLocalTargetsForFolder:folder allAbsentSignature:currentRemote];
        return;
    }
    // Data still present: a genuine partial pull failure. Baseline the actual local state so the next
    // launch re-reconciles.
    [self adoptLocalDataFileSignatureForFolder:folder];
}

// Honor a "Lose Changes" discard when the folder's Data subtree is (or just went) absent: a deleteMissing
// pull can't mirror from a missing dir, so delete the local items ourselves (each backed up) and adopt
// the folder's all-absent signature. On a partial deletion, keep the actual local state and mark a
// discard-pending marker so the next launch retries the deletion rather than the "only remote moved"
// re-publish branch (which would re-invert the discard). Without this the discard inverts into a publish.
- (void)discardByDeletingLocalTargetsForFolder:(NSString *)folder allAbsentSignature:(NSString *)allAbsentSignature {
    DLog(@"Discard: folder Data subtree absent; deleting local data files to match");
    __block BOOL fullyDeleted = NO;
    [self withApplyingRemoteDataFiles:^{
        fullyDeleted = [iTermRemoteDataFileSync deleteLocalTargets];
        // Refresh the owners regardless of whether every item was deleted, so the UI reflects
        // whatever actually got removed.
        [self applyImportedRemoteDataFiles];
    }];
    if (fullyDeleted) {
        [self setDataFileDiscardPending:NO forFolder:folder];
        [self adoptDataFileSignature:allAbsentSignature forFolder:folder];
    } else {
        DLog(@"Discard: deleteLocalTargets did not fully complete; baselining actual local state and marking discard pending");
        [self setDataFileDiscardPending:YES forFolder:folder];
        [self adoptLocalDataFileSignatureForFolder:folder];
    }
}

// Retry a discard whose local deletion previously failed partway (see the discard-pending marker).
// Returns YES if it handled this launch's reconcile (fully deleted, or re-deferred with the marker
// kept), NO if the pending discard no longer applies and the caller should run the normal reconcile.
- (BOOL)retryPendingDataFileDiscardForFolder:(NSString *)folder {
    // Bounded read FIRST, so an offline mount at launch defers rather than hanging (this runs before the
    // normal reconcile's own bounded read). Its result is also reused as the all-absent baseline below.
    NSString *remoteSignature = [iTermRemoteDataFileSync remoteContentSignatureWithRemoteFolder:folder
                                                                                 timeoutSeconds:iTermRemoteDataFileSyncRemoteReadTimeout];
    if (remoteSignature.length == 0) {
        // Remote unreadable/timeout: can't safely retry the discard now. Keep the marker, baseline local
        // so nothing is pushed, and retry on a later launch.
        DLog(@"Pending discard for %@: remote unreadable; deferring retry", folder);
        [self adoptLocalDataFileSignatureForFolder:folder];
        return YES;
    }
    // Compare the already-read signature to the all-absent hash rather than a second (unbounded)
    // remoteHasAnyTarget probe, so a mount that drops right after the read above can't hang quit/launch.
    if (![remoteSignature isEqualToString:[iTermRemoteDataFileSync allAbsentSignature]]) {
        // The folder has data (repopulated elsewhere, or was never empty), so the delete-local discard
        // target no longer applies. Drop the marker and let the normal reconcile run (folder-wins pull).
        DLog(@"Pending discard for %@ obsolete (folder has data); clearing marker", folder);
        [self setDataFileDiscardPending:NO forFolder:folder];
        return NO;
    }
    DLog(@"Retrying pending data-file discard for %@", folder);
    __block BOOL fullyDeleted = NO;
    [self withApplyingRemoteDataFiles:^{
        [[iTermSnippetsModel sharedInstance] discardUnflushedFallbackBackingUp];
        fullyDeleted = [iTermRemoteDataFileSync deleteLocalTargets];
        [self applyImportedRemoteDataFiles];
    }];
    if (fullyDeleted) {
        [self setDataFileDiscardPending:NO forFolder:folder];
        [self adoptDataFileSignature:remoteSignature forFolder:folder];
    } else {
        // Still couldn't fully delete; keep the marker and baseline the actual local state so nothing
        // is pushed. A later launch retries again.
        [self adoptLocalDataFileSignatureForFolder:folder];
    }
    return YES;
}

// Adopt the current local signature as the baseline. If it's currently uncomputable (an unreadable
// placeholder), do NOT record an empty baseline: leave the folder un-initialized so the next launch
// retries, rather than persisting "" which would read as initialized and later fire a false conflict.
- (void)adoptLocalDataFileSignatureForFolder:(NSString *)folder {
    NSString *signature = [self readyLocalDataFileSignature];
    if (signature) {
        [self adoptDataFileSignature:signature forFolder:folder];
    }
}

// Runs `block` with background data-file pushes suppressed. Any data-file modal (consent, conflict,
// or a quit "Copy/Lose Changes" prompt) spins a runloop that drains queued main-queue blocks,
// including a pending debounced save; without this, that save's writeDataFilesToRemoteFolder: could
// push local data to the folder while the user is still choosing, defeating their choice. Balanced
// in @finally so an early return can't leave it stuck, and a counter (not a bool) so a nested use
// doesn't clear an outer one. Every site that shows a data-file modal must go through here.
- (void)withDataFileReconcileSuppressed:(void (^)(void))block {
    [self withDepthCounter:&_reconcilingDataFilesDepth block:block];
}

// Runs `block` with _applyingRemoteDataFilesDepth raised, so the change notifications it provokes (via
// reloadFromDisk / ToolNotes / iTermGraphicSource observers) don't trigger an immediate write-back.
// Cleared in @finally: an ObjC exception escaping an observer must not leave the flag stuck YES,
// which would silently disable every future push, permanently suppress both change observers, and
// (via setNeedsDataFileSave's re-arm branch) spin a 0.5s reschedule loop for the life of the process.
- (void)withApplyingRemoteDataFiles:(void (^)(void))block {
    [self withDepthCounter:&_applyingRemoteDataFilesDepth block:block];
}

// Raise a depth counter for the duration of `block`, balanced in @finally so an early return or a
// thrown exception can't leave it stuck, and a counter (not a bool) so a nested use doesn't clear an
// outer one. Shared by the two suppression guards above so they can't drift apart.
- (void)withDepthCounter:(NSInteger *)counter block:(void (^)(void))block {
    *counter += 1;
    @try {
        block();
    } @finally {
        *counter -= 1;
    }
}

// Shared by the snippet observer's consent-undecided and consent-granted-but-uninitialized branches:
// on the next runloop turn (reconcile can show modals and must not run inside the notification
// dispatch: reentrancy, and a surprising mid-edit modal), establish the baseline via a reconcile and
// then arm the data-file push.
- (void)deferReconcileThenArmPushForFolder:(NSString *)folder {
    if (_deferredReconcilePending) {
        // Already armed for this session's current folder; coalesce. A second trigger (another synced
        // owner changing, or a debounced write firing) must not stack an independent re-arm chain: that
        // is what let the modal-open re-arm below busy-spin the main thread.
        return;
    }
    _deferredReconcilePending = YES;
    __weak __typeof(self) weakSelf = self;
    // Re-arm on a 0.5s delay (NOT a bare dispatch_async), mirroring setNeedsDataFileSave. A modal's
    // runModal drains main-queue blocks, so a zero-delay re-dispatch would run immediately, see the depth
    // still raised, and re-dispatch in a tight loop - pegging the main thread until the user answers. The
    // delay turns that into a 0.5s poll; the coalescing flag keeps it to a single chain.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong __typeof(weakSelf) innerSelf = weakSelf;
        if (!innerSelf) {
            return;
        }
        innerSelf->_deferredReconcilePending = NO;
        if (innerSelf->_applyingRemoteDataFilesDepth > 0 ||
            innerSelf->_reconcilingDataFilesDepth > 0) {
            // A remote->local import is still in flight, OR a reconcile/consent/conflict modal is open.
            // Don't drop the reconcile (consent would never be asked and this session's first snippet
            // wouldn't sync): reconcileDataFilesWithRemoteFolder: is dropped re-entrantly while
            // _reconcilingDataFilesDepth > 0, so running it now would silently lose it and the follow-up
            // push would never arm. Re-arm (delayed + coalesced) so it runs once the import completes /
            // the modal closes, mirroring setNeedsDataFileSave's re-arm discipline (both depths gated).
            [innerSelf deferReconcileThenArmPushForFolder:folder];
            return;
        }
        [innerSelf reconcileDataFilesWithRemoteFolder:folder];
        if ([innerSelf dataFileSyncConsentGrantedForFolder:folder] &&
            [innerSelf shouldSaveAutomatically]) {
            [innerSelf setNeedsDataFileSave];
        }
    });
}

// Arm a data-file push for a local owner change on the main thread. The single home for the delicate
// main-thread-hop discipline both owner-change observers (snippet edits, global-notes saves) depend on,
// so a future change to that contract can't be applied to one and forgotten in the other.
//
// Run SYNCHRONOUSLY when posted on the main thread: a data-file IMPORT posts these (via reloadFromDisk /
// ToolNotes) while _applyingRemoteDataFilesDepth is raised, and that depth is main-thread-only, so it
// must be read on the SAME runloop turn to actually suppress the import-provoked write-back. A deferred
// check would run a turn later, by which point the depth is back to 0 (the bug this replaced).
// armDataFileSyncPushForLocalOwnerChange only ARMS deferred/debounced work, never shows a modal
// synchronously, so running it inline here is safe. Off-main posts (a future background mutator, not an
// import) hop to main for the depth counter's thread-safety.
- (void)armDataFileSyncPushFromOwnerNotification {
    __weak __typeof(self) weakSelf = self;
    void (^body)(void) = ^{
        [weakSelf armDataFileSyncPushForLocalOwnerChange];
    };
    if ([NSThread isMainThread]) {
        body();
    } else {
        dispatch_async(dispatch_get_main_queue(), body);
    }
}

// A synced data file (a snippet, or the global note) changed locally, so arm a data-file-only push of
// it. Shared by the snippet-change and global-notes-save observers (via the main-thread hop in
// -armDataFileSyncPushFromOwnerNotification). Must run on the main thread: it reads
// _applyingRemoteDataFilesDepth (main-thread-only) so an import-provoked change (depth raised) is
// suppressed rather than pushed back. No-op unless data-file sync is enabled, non-URL, and automatic.
// If consent hasn't been decided, or was granted but the baseline was never established, it defers a
// reconcile (which may prompt) and arms the push after; otherwise it arms the debounced push directly.
- (void)armDataFileSyncPushForLocalOwnerChange {
    if (_applyingRemoteDataFilesDepth > 0 || !self.shouldLoadRemotePrefs) {
        return;
    }
    NSString *folder = [self expandedCustomFolderOrURL];
    if (self.remoteLocationIsURL || !folder.length) {
        return;
    }
    if (![self dataFileSyncConsentDecidedForFolder:folder]) {
        // The launch-time reconcile didn't ask because there was nothing to sync yet. Now that a data
        // file exists, reconcile (which prompts for consent and establishes a baseline) so it can sync
        // this session instead of only after the next relaunch.
        [self deferReconcileThenArmPushForFolder:folder];
        return;
    }
    if ([self dataFileSyncConsentGrantedForFolder:folder] &&
        [self shouldSaveAutomatically]) {
        if (![self dataFileSyncInitializedForFolder:folder]) {
            // Consent granted but the baseline was never established (a reconcile recorded consent then
            // deferred, e.g. on a momentarily-unreadable signature). setNeedsDataFileSave would no-op on
            // the uninitialized guard with no re-arm, so establish the baseline now (deferred, same as
            // the consent-undecided branch above) and then arm the push.
            [self deferReconcileThenArmPushForFolder:folder];
            return;
        }
        // Push ONLY the data files (not setNeedsSave, which would rewrite the whole prefs plist and
        // clobber another machine's plist changes in the folder).
        [self setNeedsDataFileSave];
    }
}

- (void)reconcileDataFilesWithRemoteFolder:(NSString *)folder {
    // Drop a re-entrant reconcile. A reconcile's consent/conflict modal spins a runloop that drains
    // queued main-queue blocks, including the snippet observer's deferred reconcile; running that
    // nested reconcile would stack a second modal on top of the first and let the two adopt
    // conflicting baselines. The outer reconcile already handles this folder, so the next launch (or
    // the post-modal save) covers anything missed.
    if (_reconcilingDataFilesDepth > 0) {
        DLog(@"Dropping re-entrant data-file reconcile for %@", folder);
        return;
    }
    [self withDataFileReconcileSuppressed:^{
        [self reconcileDataFilesWithRemoteFolderImpl:folder];
    }];
}

// Three-way reconcile of the synced data files at load time. The per-folder baseline lets us tell
// "the local copy has un-pushed edits" apart from "the folder has newer data," so we never silently
// overwrite local edits (including edits made since a crash), and a genuine both-sides change
// prompts the user instead of picking a winner.
- (void)reconcileDataFilesWithRemoteFolderImpl:(NSString *)folder {
    // Flush any user-defaults snippet fallback to disk BEFORE the consent gate. The consent gate's
    // "nothing to sync yet" check reads on-disk presence (localHasAnyTarget), so if fallback-only
    // snippets (a prior plist-write failure) weren't flushed first, the gate would return NO without
    // asking and the snippets would never be offered for sync. Flushing writes only to local
    // Application Support, so there's no privacy concern doing it before consent. Wrap in
    // withApplyingRemoteDataFiles: because the "fallback superseded by an import" branch posts a
    // snippets change via reloadFromDisk; without the suppression the observer would arm a
    // setNeedsDataFileSave that then spins a 0.5s re-arm loop for the duration of this reconcile.
    [self withApplyingRemoteDataFiles:^{
        [[iTermSnippetsModel sharedInstance] ensurePersistedToDisk];
    }];
    if (![self ensureDataFileSyncConsentForFolder:folder]) {
        return;
    }
    if ([self dataFileDiscardPendingForFolder:folder] &&
        [self retryPendingDataFileDiscardForFolder:folder]) {
        // A prior quit-time discard couldn't fully delete the local data files; we just retried it
        // instead of running the normal three-way reconcile (which would re-publish the survivors).
        return;
    }
    NSString *localSignature = [self readyLocalDataFileSignature];
    // This hashes the remote Data subtree synchronously on the main thread at load. We accept the
    // startup cost (rather than going off-main, which would race the snippets model's first read of
    // its file): loading prefs already reads the remote plist here, and a present-but-unreadable
    // placeholder defers the whole reconcile below instead of stalling on it. The save/quit path does
    // NOT hash the remote here, but note it is not hash-free either: an actual push (only when the
    // local copy diverged from the baseline) still reads the remote subtree twice inside
    // copyLocalToRemote (the divergence guard, then mirror's per-item skip-identical pass). See the
    // perf note on -writeDataFilesToRemoteFolder:localSignature:.
    NSString *remoteSignature = [iTermRemoteDataFileSync remoteContentSignatureWithRemoteFolder:folder
                                                                                 timeoutSeconds:iTermRemoteDataFileSyncRemoteReadTimeout];
    if (!localSignature || remoteSignature.length == 0) {
        // A file on one side is currently unreadable (a not-yet-downloaded iCloud/Dropbox placeholder,
        // or a read timeout on an offline mount). Defer the whole reconcile to a later launch rather
        // than acting on a phantom
        // signature, which could otherwise fire a false conflict or adopt a wrong baseline.
        DLog(@"Data-file signature unavailable; deferring reconcile for %@", folder);
        return;
    }
    if ([localSignature isEqualToString:remoteSignature]) {
        // Already in agreement; nothing to copy.
        [self adoptDataFileSignature:remoteSignature forFolder:folder];
        return;
    }
    NSString *baseline = [self baselineSignatureForFolder:folder];
    if (baseline == nil) {
        // First time syncing this folder; there is no baseline to compare against.
        if (![iTermRemoteDataFileSync localHasAnyTarget]) {
            // Nothing to lose locally: adopt the folder's copy.
            [self useRemoteDataFilesForFolder:folder remoteSignature:remoteSignature];
        } else if ([remoteSignature isEqualToString:[iTermRemoteDataFileSync allAbsentSignature]]) {
            // The folder has no data files yet: keep the local copy and push it on the next save. We
            // compare the already-read signature to the all-absent hash rather than a second (unbounded)
            // remoteHasAnyTarget probe, so a mount dropping mid-reconcile can't hang startup.
            [self adoptDataFileSignature:remoteSignature forFolder:folder];
        } else {
            // Both sides have data and they differ: a genuine conflict.
            [self resolveDataFileConflictWithRemoteFolder:folder remoteSignature:remoteSignature];
        }
        return;
    }
    // "local unchanged" is local == baseline OR local == lastPushedLocal, mirroring the push guard
    // (writeDataFilesToRemoteFolder:) and localDataFilesDifferFromSavedGivenSignature:. Consulting
    // lastPushedLocal matters in the locally-deleted-file steady state: the user deleted a synced file
    // that a union push can't propagate, so the folder keeps it and baseline permanently differs from
    // local. Without this, every launch that follows any remote edit would classify local as changed
    // and fire a spurious "which copy?" conflict. Treating it as "only remote moved" instead pulls
    // silently (resurrecting the deleted file is the already-documented deletion-doesn't-propagate
    // outcome, and the remote edit is taken). Safe: this branch is only reached when local ==
    // lastPushedLocal, i.e. local is exactly the subset last pushed, so the deleteMissing:YES pull below
    // deletes nothing the folder doesn't already lack.
    const BOOL localChanged = (![localSignature isEqualToString:baseline] &&
                               ![localSignature isEqualToString:[self lastPushedLocalSignatureForFolder:folder]]);
    const BOOL remoteChanged = ![remoteSignature isEqualToString:baseline];
    if (localChanged && remoteChanged) {
        [self resolveDataFileConflictWithRemoteFolder:folder remoteSignature:remoteSignature];
    } else if (remoteChanged) {
        // Only the folder moved: it is authoritative. local == baseline (or == lastPushedLocal, a SUBSET
        // of it in the locally-deleted-file state), so the local copy holds no items beyond the folder's;
        // mirror the folder (propagating any deletions it made) - deleteMissing:YES deletes nothing the
        // folder doesn't already lack.
        //
        // Known limitation: deleting a whole synced *file* locally (e.g. removing notes.rtfd
        // outright) does not propagate. The push is always a union (it can't prove the folder didn't
        // change under it, so it won't delete folder items), so the folder keeps the file; this
        // branch then pulls it back, "resurrecting" it. This is the deliberate trade-off that
        // prevents a concurrent-edit on another machine from being destroyed. Editing or clearing a
        // file's *contents* does propagate normally (it's an overwrite, not a deletion).
        //
        // Conversely, a *folder* item that an iCloud/Dropbox eviction makes wholesale-absent reads
        // as a remote deletion here and is removed locally. That is recoverable (the mirror backs the
        // file up before removing it), but surprising; distinguishing eviction from a real deletion
        // at the filesystem level isn't possible, so we accept it and rely on the backup. (A
        // present-but-unreadable placeholder is already handled: it defers the whole reconcile.)
        if ([self pullRemoteDataFilesFromFolder:folder deleteMissing:YES]) {
            // local == folder now.
            [self adoptDataFileSignature:remoteSignature forFolder:folder];
        } else {
            // The pull couldn't run. Decide via a BOUNDED re-read + all-absent comparison (never the
            // unbounded remoteHasAnyTarget probe, which would hang startup if the mount dropped
            // mid-reconcile).
            NSString *currentRemote = [iTermRemoteDataFileSync remoteContentSignatureWithRemoteFolder:folder
                                                                                      timeoutSeconds:iTermRemoteDataFileSyncRemoteReadTimeout];
            if (currentRemote.length > 0 &&
                [currentRemote isEqualToString:[iTermRemoteDataFileSync allAbsentSignature]]) {
                // The folder's whole Data dir is gone (cleared/deleted elsewhere). Adopt its actual
                // (all-absent) signature, NOT the local one: that makes the next reconcile see "only
                // local moved" so the next save re-publishes local and repopulates the folder, instead of
                // recording local as the baseline (which would falsely assert agreement and leave the
                // empty folder and populated local diverged forever).
                [self adoptDataFileSignature:currentRemote forFolder:folder];
            } else {
                // A partial pull failure with remote items still present (or the folder momentarily
                // unreadable): record the actual local state so the baseline is truthful and the next
                // launch re-reconciles.
                [self adoptLocalDataFileSignatureForFolder:folder];
            }
        }
    } else {
        // Only the local copy moved (un-pushed edits): keep it and push on the next save.
        [self adoptDataFileSignature:remoteSignature forFolder:folder];
    }
}

// After a forced conflict-resolution push returned NO, the push may still have committed SOME items
// (mirrorAll isn't atomic across items), leaving the folder at a signature different from both the
// pre-push value and local. Adopt the folder's ACTUAL signature so the partial write isn't re-read as a
// both-changed conflict next launch (re-prompting the user with the question they just answered) -
// mirroring the steady-state writeDataFilesToRemoteFolder failure handling. Bounded read; fall back to
// the pre-push signature only if the folder is momentarily unreadable.
- (NSString *)baselineAfterFailedForcedPushToFolder:(NSString *)folder prePushSignature:(NSString *)prePushSignature {
    NSString *actual = [iTermRemoteDataFileSync remoteContentSignatureWithRemoteFolder:folder
                                                                        timeoutSeconds:iTermRemoteDataFileSyncRemoteReadTimeout];
    return actual.length > 0 ? actual : prePushSignature;
}

// Resolve in favor of the folder: pull its items (union, keeping local-only extras), then push the
// merged result back so both sides converge to the union (folder wins shared items). Shared by
// first-adoption and the "use the folder's copy" conflict choice.
- (void)useRemoteDataFilesForFolder:(NSString *)folder remoteSignature:(NSString *)remoteSignature {
    if (![self pullRemoteDataFilesFromFolder:folder deleteMissing:NO]) {
        // Nothing was pulled (folder's Data missing or unreadable); the local copy is unchanged.
        [self adoptLocalDataFileSignatureForFolder:folder];
        return;
    }
    // After a union pull the local copy is the folder's items plus any local-only extras. Push it
    // back so the folder gains those extras and the two sides converge now. Otherwise the baseline
    // (the folder's signature) would differ from the merged local copy and trigger a spurious "save
    // settings?" prompt at quit even though the user made no edits.
    NSString *mergedLocalSignature = [self readyLocalDataFileSignature];
    if (!mergedLocalSignature) {
        // A local file became momentarily unreadable right after the pull (e.g. a just-written
        // placeholder). The import already ran, so do NOT leave the baseline nil: that would make the
        // next launch see baseline==nil with both sides populated and re-prompt a phantom conflict even
        // though the user made no edits. Adopt the folder's signature as a provisional baseline; if the
        // merged copy has local-only extras, local != baseline next launch takes "only local moved" and
        // the save path pushes the extras.
        [self adoptDataFileSignature:remoteSignature forFolder:folder];
        return;
    }
    if ([mergedLocalSignature isEqualToString:remoteSignature]) {
        // No local-only extras; already converged.
        [self adoptDataFileSignature:remoteSignature forFolder:folder];
    } else if ([iTermRemoteDataFileSync copyLocalToRemoteWithRemoteFolder:folder]) {
        // Forced push: we just pulled from this folder during the reconcile, so pushing the merged
        // extras back is intended, not a blind overwrite.
        [self adoptDataFileSignature:mergedLocalSignature forFolder:folder];
    } else {
        // Pushing the extras failed (possibly partway). Adopt the folder's actual signature so a partial
        // write isn't misread as a fresh conflict next launch; the extras stay a pending local change
        // for the save path to retry.
        [self adoptDataFileSignature:[self baselineAfterFailedForcedPushToFolder:folder prePushSignature:remoteSignature]
                           forFolder:folder];
    }
}

// Resolve in favor of this Mac: push local (union; local wins shared items, the folder keeps its
// disjoint items), then pull the folder's disjoint items back down so local == folder == union. The
// shared items already equal local's version from the push, so the pull preserves the user's choice.
// Pulling is essential: otherwise the local copy is left missing the folder's disjoint items while
// the baseline claims local is fully synced, and a later steady-state push would treat those items
// as locally deleted.
//
// DELIBERATE LIMITATION: this is a merge favoring this Mac for SHARED items, NOT a wholesale replace.
// The push is a union (deleteMissing:NO), so a file the user DELETED locally that still exists in the
// folder is not removed, and the pull then brings it back down (resurrecting the local deletion). This
// is the same "deleting a whole synced file locally does not propagate" trade-off the reconcile
// documents, kept because a whole-set mirror (deleteMissing:YES) here cannot tell "local deleted this"
// from "local never had this" (no per-item deletion baseline) and would destroy another machine's
// disjoint items that this Mac simply never had (the disjoint-first-sync data loss that
// testFirstSyncDisjointSetsDoNotLoseRemoteOnlyItems guards against). Content edits/clears DO propagate.
- (void)useLocalDataFilesForFolder:(NSString *)folder remoteSignature:(NSString *)remoteSignature {
    // Forced push: the user explicitly chose "use this Mac's copy", so overwriting the folder is the
    // point.
    if (![iTermRemoteDataFileSync copyLocalToRemoteWithRemoteFolder:folder]) {
        // Push failed (read-only/full/unreachable folder), possibly PARTWAY. Record the folder's ACTUAL
        // signature (not the stale pre-push one) so a partial write isn't re-classified as a both-changed
        // conflict next launch and re-prompt the user; the local copy reads as a pending change to retry.
        [self adoptDataFileSignature:[self baselineAfterFailedForcedPushToFolder:folder prePushSignature:remoteSignature]
                           forFolder:folder];
        return;
    }
    if ([self pullRemoteDataFilesFromFolder:folder deleteMissing:NO]) {
        // Pull succeeded: local == folder == union now, so local's signature is the truthful baseline.
        [self adoptLocalDataFileSignatureForFolder:folder];
    } else {
        // The pull that brings the folder's disjoint items down failed (folder momentarily unreadable /
        // Data dir transiently gone), so local is still MISSING those items. No single baseline value is
        // ideal here (local is a SUBSET of the folder): adopting local's subset signature would let the
        // next launch pull the disjoint items (remote != baseline -> "only remote moved" pull), but a
        // data-file edit before then would read as a both-sides change and fire a spurious "which copy?"
        // conflict. We instead adopt the folder's ACTUAL (union) signature (re-read, bounded; falls back
        // to the pre-push value if unreadable), which keeps this session's pushes working and never
        // prompts a spurious conflict. The trade-off: the folder's disjoint items (another machine's, and
        // safe in the folder) are not pulled down to THIS Mac until the next genuine remote change flips
        // remoteChanged true - not on the very next launch. No data is lost either way; we prefer the
        // no-spurious-prompt worst case. Matches baselineAfterFailedForcedPushToFolder: (sibling paths).
        [self adoptDataFileSignature:[self baselineAfterFailedForcedPushToFolder:folder prePushSignature:remoteSignature]
                           forFolder:folder];
    }
}

- (void)resolveDataFileConflictWithRemoteFolder:(NSString *)folder
                                remoteSignature:(NSString *)remoteSignature {
    NSString *title =
        [NSString stringWithFormat:@"Snippets, notes, or icon customizations changed both on this Mac "
                                   @"and in the settings folder “%@” since they were last in sync. "
                                   @"Which copy would you like to keep?",
                                   [self customFolderOrURL]];
    const iTermWarningSelection selection =
        [iTermWarning showWarningWithTitle:title
                                   actions:@[ @"Use This Mac’s", @"Use Settings Folder’s" ]
                                identifier:nil
                               silenceable:kiTermWarningTypePersistent
                                    window:nil];
    // The conflict modal is unbounded; another machine may have written the folder while it sat open,
    // so remoteSignature (hashed BEFORE the prompt) may be stale. Re-hash and apply the user's chosen
    // DIRECTION against the folder's CURRENT signature. We deliberately do NOT re-run the whole
    // reconcile on a change: that could silently take the "only the local copy moved" branch (if the
    // folder happened to revert to the baseline while the modal sat open) and KEEP the very edits the
    // user just chose to discard. Re-applying the choice against the fresh signature honors the user's
    // decision and updates the adopted baseline to the folder's real state. (A tiny non-modal TOCTOU
    // window remains between here and the push; that's the same exposure any local edit already has.)
    // Bounded: the modal can sit open for minutes, during which the mount may go offline; the earlier
    // reconcile read was bounded, so this re-hash must be too.
    NSString *currentRemoteSignature = [iTermRemoteDataFileSync remoteContentSignatureWithRemoteFolder:folder
                                                                                       timeoutSeconds:iTermRemoteDataFileSyncRemoteReadTimeout];
    if (currentRemoteSignature.length == 0) {
        // The folder became unreadable while the modal was open; we can't act on the user's choice now.
        // Do NOT adopt the local signature as the baseline: if the user chose "Use This Mac's", that
        // would make the next launch see local==baseline / remoteChanged and silently PULL the folder's
        // version, inverting the "keep this Mac's copy" intent. Leave the baseline untouched so the next
        // launch re-runs the full three-way reconcile and re-prompts. Nothing is pushed meanwhile: the
        // push guard defers while the folder != baseline (both-changed conflict) and the save path
        // no-ops while the folder is un-initialized (first conflict).
        DLog(@"Folder became unreadable while the conflict modal was open; leaving baseline for next launch to re-reconcile");
        return;
    }
    if (![currentRemoteSignature isEqualToString:remoteSignature]) {
        DLog(@"Folder changed while the conflict modal was open; applying the user's choice to its current state");
    }
    if (selection == kiTermWarningSelection1) {
        [self useRemoteDataFilesForFolder:folder remoteSignature:currentRemoteSignature];
    } else {
        [self useLocalDataFilesForFolder:folder remoteSignature:currentRemoteSignature];
    }
}

// Maps each allowlisted data file to the block that reloads its in-memory owner after a remote->local
// import. Single source of truth for -applyImportedRemoteDataFilesForItems:, which ASSERTS this covers
// the whole allowlist (asserts are on in release), so adding a synced file without a reloader fails
// loudly instead of letting a stale in-memory owner overwrite the fresh import on the next autosave
// (silent data loss). graphic_colors and graphic_icons share ONE reloader object so a change to both
// only reloads the maps once.
- (NSDictionary<NSString *, void (^)(void)> *)dataFileOwnerReloaders {
    void (^reloadGraphics)(void) = ^{ [iTermGraphicSource reloadGraphicMaps]; };
    return @{
        iTermRemoteDataFileSync.snippetsPlistName: ^{ [[iTermSnippetsModel sharedInstance] reloadFromDisk]; },
        iTermRemoteDataFileSync.notesPackageName: ^{ [ToolNotes reloadGlobalNotesFromDisk]; },
        iTermRemoteDataFileSync.graphicColorsName: reloadGraphics,
        iTermRemoteDataFileSync.graphicIconsName: reloadGraphics,
    };
}

// Refreshes the in-memory owners of every allowlisted data file after a remote->local import, so a
// live session reflects the imported copy and doesn't overwrite it on the next autosave/relaunch.
- (void)applyImportedRemoteDataFiles {
    [self applyImportedRemoteDataFilesForItems:[NSSet setWithArray:[iTermRemoteDataFileSync allowlistNames]]];
}

// Reloads only the owners of the named items (each name is an allowlist entry). Refreshing an
// unchanged owner isn't harmless (see -pullRemoteDataFilesFromFolder:), so callers pass the set of
// items actually imported.
- (void)applyImportedRemoteDataFilesForItems:(NSSet<NSString *> *)items {
    NSDictionary<NSString *, void (^)(void)> *reloaders = [self dataFileOwnerReloaders];
    ITAssertWithMessage([[NSSet setWithArray:reloaders.allKeys] isEqualToSet:[NSSet setWithArray:[iTermRemoteDataFileSync allowlistNames]]],
                        @"Data-file owner reloaders do not cover the allowlist; a synced file would not be reloaded after import");
    // Call each affected owner's reloader exactly once (colors+icons share one block object, so a set
    // keyed on block identity de-dupes reloadGraphicMaps).
    NSMutableSet *alreadyReloaded = [NSMutableSet set];
    for (NSString *name in items) {
        void (^reload)(void) = reloaders[name];
        if (reload && ![alreadyReloaded containsObject:reload]) {
            [alreadyReloaded addObject:reload];
            reload();
        }
    }
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
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        // The synchronous self-triggered case (an import mutating user defaults) is skipped by the
        // depth guard. The COALESCED case is not (NSUserDefaultsDidChangeNotification fires on a later
        // runloop turn, by which point the depth is back to 0), so a data-file import that clears the
        // snippets fallback key would otherwise reach setNeedsSave -> saveIfNeeded and rewrite the WHOLE
        // prefs plist, which can clobber another machine's newer prefs. The syncable-difference gate
        // below defuses that: the fallback key is non-syncable, so clearing it leaves the syncable prefs
        // unchanged relative to what's in the folder, and no save fires.
        if (!strongSelf || strongSelf->_applyingRemoteDataFilesDepth > 0) {
            return;
        }
        if ([strongSelf shouldSaveAutomatically]) {
            // A save is already armed for this runloop turn, so nothing this change could decide would
            // add one. Skip the persistent-domain diff below (which rebuilds both prefs dictionaries
            // and walks their key union) on the common case of many coalesced defaults changes while a
            // save is pending; setNeedsSave would no-op on _needsSave anyway.
            if (strongSelf->_needsSave) {
                return;
            }
            // Only save when a SYNCABLE pref actually changed relative to the folder's plist. Skips a
            // save provoked purely by a non-syncable key (the snippets fallback), which would only risk
            // clobbering the folder's newer prefs with byte-identical content. When the folder plist is
            // empty/absent we still save, to populate it.
            NSDictionary *saved = strongSelf.savedRemotePrefs;
            if (saved.count > 0 && ![strongSelf localPrefsDifferFromSavedRemotePrefs]) {
                return;
            }
            [strongSelf setNeedsSave];
        }
    }];
    // Snippet edits don't flow through user defaults (snippets live in snippets.plist), so observe
    // them directly to trigger a save of the synced data files.
    [iTermSnippetsDidChangeNotification subscribe:self
                                            block:^(iTermSnippetsDidChangeNotification *notification) {
        // Snippet edits don't flow through user defaults, so observe the model directly. The delicate
        // main-thread-hop + import-suppression discipline lives in one place (see the helper).
        [weakSelf armDataFileSyncPushFromOwnerNotification];
    }];
    // Global-note edits also don't flow through user defaults; ToolNotes posts this after it actually
    // writes notes.rtfd, so observe it to push the note live rather than only at the next unrelated
    // autosave or at quit. Same import-suppression reasoning as the snippet observer above: an import
    // reloads through -globalTextDidChange: (a read), which never posts this, so it can only fire for a
    // genuine local edit; the depth guard inside the handler is belt-and-suspenders.
    [[NSNotificationCenter defaultCenter] addObserverForName:iTermToolNotesDidSaveGlobalNotesNotification
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        [weakSelf armDataFileSyncPushFromOwnerNotification];
    }];
    if (!self.shouldLoadRemotePrefs) {
        DLog(@"Disabled");
        return;
    }
    NSDictionary *remotePrefs = [self freshCopyOfRemotePreferences];
    self.savedRemotePrefs = remotePrefs;
    self.preservedKeys = preservedKeys;

    // Reconcile synced data files with the custom folder before the snippets model first reads its
    // file. Local-folder only; URLs can host a single plist but not a file tree.
    NSString *dataFolder = [self expandedCustomFolderOrURL];
    if (!self.remoteLocationIsURL && dataFolder.length) {
        [self reconcileDataFilesWithRemoteFolder:dataFolder];
    }

    if (![remotePrefs count]) {
        return;
    }
    DLog(@"Load local prefs");
    NSDictionary *localPrefs = [[iTermUserDefaults userDefaults] persistentDomainForName:[iTermUserDefaults customSuiteName] ?: [[NSBundle mainBundle] bundleIdentifier]];
    // Empty out the current prefs
    DLog(@"Remove non-syncable values");
    int count = 0;
    for (NSString *key in localPrefs) {
        if ([self preferenceKeyIsSyncable:key]) {
            count += 1;
            [[iTermUserDefaults userDefaults] removeObjectForKey:key];
        }
    }
    DLog(@"Removed %d keys", count);
    DLog(@"Copy remote values to user defaults");
    for (NSString *key in remotePrefs) {
        if ([self preferenceKeyIsSyncable:key]) {
            [[iTermUserDefaults userDefaults] setObject:[remotePrefs objectForKey:key]
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

- (BOOL)localPrefsDifferFromSavedRemotePrefsRespectingDefaults {
    return [self localPrefsDifferFromSavedRemotePrefsRespectingDefaults:YES];
}

- (BOOL)localPrefsDifferFromSavedRemotePrefs {
    return [self localPrefsDifferFromSavedRemotePrefsRespectingDefaults:NO];
}

- (BOOL)localPrefsDifferFromSavedRemotePrefsRespectingDefaults:(BOOL)respectDefaults {
    if (!self.shouldLoadRemotePrefs) {
        return NO;
    }
    NSDictionary *saved = [self removeDynamicProfiles:self.savedRemotePrefs];
    if (saved && [saved count]) {
        // Grab all prefs from our bundle only (no globals, etc.).
        NSUserDefaults *userDefaults = [iTermUserDefaults userDefaults];
        NSDictionary *localPrefs =
            [userDefaults persistentDomainForName:[iTermUserDefaults customSuiteName] ?: [[NSBundle mainBundle] bundleIdentifier]];
        localPrefs = [self removeDynamicProfiles:localPrefs];

        // Iterate over each set of prefs and validate that the other has the same value for each
        // key.
        NSSet<NSString *> *allKeys = [NSSet setWithArray:[localPrefs.allKeys arrayByAddingObjectsFromArray:saved.allKeys]];
        for (NSString *key in allKeys) {
            id savedValue = [self valueInDictionary:saved forKey:key respectingDefaults:respectDefaults];
            id localValue = [self valueInDictionary:localPrefs forKey:key respectingDefaults:respectDefaults];

            if ([self preferenceKeyIsSyncable:key] &&
                ![savedValue isEqual:localValue]) {
                return YES;
            }
        }
    }
    return NO;
}

- (id)valueInDictionary:(NSDictionary *)dict
                 forKey:(NSString *)key
     respectingDefaults:(BOOL)respectDefaults {
    if (!respectDefaults) {
        return dict[key];
    }

    if ([key isEqualToString:KEY_NEW_BOOKMARKS]) {
        return [self saturatedBookmarkValueInDictionary:dict];
    } else {
        id value = dict[key];
        if (value) {
            return value;
        }
        return [iTermPreferences defaultObjectForKey:key];
    }
}

- (NSArray<NSDictionary *> *)saturatedBookmarkValueInDictionary:(NSDictionary *)settings {
    NSDictionary *defaults = [iTermProfilePreferences defaultValueMap];
    NSMutableArray *bookmarks = [[NSArray castFrom:settings[KEY_NEW_BOOKMARKS]] ?: @[] mutableCopy];
    for (NSInteger i = 0; i < bookmarks.count; i++) {
        NSDictionary *bookmark = [NSDictionary castFrom:bookmarks[i]] ?: @{};
        bookmarks[i] = [defaults dictionaryByMergingDictionary:bookmark];
    }

    return bookmarks;
}

- (BOOL)remotePrefsHaveChanged {
    if (!self.shouldLoadRemotePrefs) {
        return NO;
    }
    if (self.remoteLocationIsURL) {
        return NO;
    }
    // This check itself does not hash the remote data-file subtree: it only compares the prefs plist.
    // (The subsequent push in writeDataFilesToRemoteFolder: still reads the remote subtree when the
    // local copy actually diverged; see the perf note there. Remote-vs-local data-file divergence,
    // however, is detected and resolved only by the next launch's reconcile, not here.)
    NSDictionary *saved = self.savedRemotePrefs;
    if (!saved) {
        return NO;
    }
    DLog(@"Begin equality comparison");
    const BOOL result = ![[self freshCopyOfRemotePreferences] isEqual:saved];
    DLog(@"result=%@", @(result));
    return result;
}

- (void)applicationWillTerminate {
    // Only hash the local data files when data-file sync is actually active for this folder. The hash
    // reads snippets.plist, the whole notes.rtfd package (possibly multi-MB), and both graphic JSONs;
    // the majority of users never enabled folder sync and must not pay that at every quit. When
    // active, hash once and reuse the result for both the prompt wording and the push.
    NSString *localDataSignature = nil;
    BOOL dataFilesDiffer = NO;
    if ([self dataFileSyncActiveForCurrentFolder]) {
        localDataSignature = [self readyLocalDataFileSignature];
        dataFilesDiffer = [self localDataFilesDifferFromSavedGivenSignature:localDataSignature];
    }
    if ([self localPrefsDifferFromSavedRemotePrefs]) {
        // Prefs changed (possibly along with data files). saveLocalUserDefaultsToRemotePrefs writes
        // the plist and also pushes the data files.
        if (self.remoteLocationIsURL) {
            // If the setting is always copy, then ask. Copying isn't an option.
            [[iTermUserDefaults userDefaults] setObject:[self remotePrefsLocation] forKey:iTermRemotePreferencesPromptBeforeLoadingPrefsFromURL];
        } else if ([self shouldSaveAutomatically]) {
            // The debounced setNeedsSave path can lose the race against app
            // exit, leaving a stale remote file that overwrites the local
            // copy on next launch. Flush synchronously instead. Issue 12844.
            RLog(@"Save changes on quit (Automatic)");
            [self saveLocalUserDefaultsToRemotePrefsInteractive:NO];
        } else {
            // Not a URL. saveLocalUserDefaultsToRemotePrefs pushes the data files too, so name them
            // in the prompt when they also changed; otherwise "Lose Changes" would silently drop the
            // data-file edits without the user realizing the prompt covered them.
            NSString *theTitle =
                dataFilesDiffer
                    ? [NSString stringWithFormat:
                       @"Settings and your snippets, notes, or icon customizations have changed. Copy them to %@?",
                       [self customFolderOrURL]]
                    : [NSString stringWithFormat:
                       @"Settings have changed. Copy them to %@?",
                       [self customFolderOrURL]];

            // "Lose Changes" is destructive and shouldn't be remembered.
            iTermWarning *warning = [[iTermWarning alloc] init];
            warning.title = theTitle;
            warning.actionLabels = @[ @"Copy", @"Lose Changes" ];
            warning.identifier = @"NoSyncNeverRemindPrefsChangesLostForFile";
            warning.warningType = kiTermWarningTypePermanentlySilenceable;
            warning.doNotRememberLabels = @[ @"Lose Changes" ];
            // Suppress background pushes while this modal is up: its runloop can drain a pending
            // debounced save, which would push the data files even though the user may pick "Lose
            // Changes". (The data-only branch below does the same; both must, or "Lose Changes" leaks.)
            __block iTermWarningSelection selection;
            [self withDataFileReconcileSuppressed:^{
                selection = [warning runModal];
            }];
            if (selection == kiTermWarningSelection0) {
                RLog(@"Save changes on quit");
                [self saveLocalUserDefaultsToRemotePrefsInteractive:NO];
            } else if (dataFilesDiffer) {
                // "Lose Changes": prefs are discarded by the next launch overwriting local
                // user-defaults from the remote plist, but data files have no such load-time
                // overwrite, so discard them explicitly here too (otherwise the next launch's
                // reconcile would push the supposedly-dropped edits to the folder).
                DLog(@"Discard local data-file changes on quit (combined prompt)");
                [self discardLocalDataFileChangesTakingFolder:[self expandedCustomFolderOrURL]];
            }
        }
    } else if (dataFilesDiffer) {
        // Only data files changed (prefs are unchanged). Push just the data files rather than
        // rewriting the whole prefs plist (which would needlessly clobber another machine's prefs),
        // and use a message that names what actually changed. (Always a local folder; data-file sync
        // is skipped for URL destinations.)
        NSString *folder = [self expandedCustomFolderOrURL];
        if ([self shouldSaveAutomatically]) {
            DLog(@"Save data files on quit (Automatic)");
            [self writeDataFilesToRemoteFolder:folder localSignature:localDataSignature];
        } else {
            NSString *theTitle = [NSString stringWithFormat:
                                  @"Your snippets, notes, or icon customizations changed. Copy them to %@?",
                                  [self customFolderOrURL]];
            iTermWarning *warning = [[iTermWarning alloc] init];
            warning.title = theTitle;
            warning.actionLabels = @[ @"Copy", @"Lose Changes" ];
            warning.identifier = @"NoSyncNeverRemindDataFileChangesLostForFile";
            warning.warningType = kiTermWarningTypePermanentlySilenceable;
            warning.doNotRememberLabels = @[ @"Lose Changes" ];
            // Suppress background pushes during the modal: its runloop can drain a pending debounced
            // save, which would push the data files even if the user picks "Lose Changes".
            __block iTermWarningSelection selection;
            [self withDataFileReconcileSuppressed:^{
                selection = [warning runModal];
            }];
            if (selection == kiTermWarningSelection0) {
                DLog(@"Save data files on quit");
                [self writeDataFilesToRemoteFolder:folder localSignature:localDataSignature];
            } else {
                DLog(@"Discard local data-file changes on quit by replacing them with the folder's copy");
                [self discardLocalDataFileChangesTakingFolder:folder];
            }
        }
    } else if(self.savedRemotePrefs != nil) {
        [[iTermUserDefaults userDefaults] setObject:nil
                                                  forKey:iTermRemotePreferencesPromptBeforeLoadingPrefsFromURL];
    }
}

- (BOOL)remoteLocationIsURL {
    NSString *customFolderOrURL = [self expandedCustomFolderOrURL];
    return [customFolderOrURL stringIsUrlLike];
}

@end
