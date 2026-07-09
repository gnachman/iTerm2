//
//  iTermSnippetsModel.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/14/20.
//

#import "iTermSnippetsModel.h"

#import "NSArray+iTerm.h"
#import "NSData+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSIndexSet+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermNotificationCenter+Protected.h"
#import "iTermPreferences.h"
#import "iTermUserDefaults.h"
#import "iTermWarning.h"

NSString *iTermSnippetHelpMarkdown = @"Terms in the search query are used to prefix search snippet titles, content, and tags.\n\nYou can use the following operators to restrict what attributes of snippets a term searches:\n * `tag:` to search only tags.\n * `title:` to search only snippet titles.\n * `text:` to search only the text of a snippet.\nFor example, `tag:linux`.\n\nTo search only for snippets that do *not* match a term, use the `-` operator. For example, `-linux` or `-tag:linux`.\n\nYou can use `|` as logical OR. For example, `linux|bsd` or `tag:linux|tag:bsd`.";

@implementation iTermSnippet {
    NSDictionary *_dictionary;
}

+ (int)currentVersion {
    return 2;
}

- (instancetype)initWithTitle:(NSString *)title
                        value:(NSString *)value
                         guid:(NSString *)guid
                         tags:(NSArray<NSString *> *)tags
                     escaping:(iTermSendTextEscaping)escaping
                      version:(int)version {
    if (self) {
        _title = [title copy];
        _value = [value copy];
        _guid = guid;
        _escaping = escaping;
        _tags = [tags copy];
        _version = version;
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    if (!dictionary[@"guid"]) {
        return nil;
    }
    return [self initWithDictionary:dictionary index:0];
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary index:(NSInteger)i {
    NSString *title = dictionary[@"title"] ?: @"";
    NSString *value = dictionary[@"value"] ?: @"";
    // The fallback GUID is a migration path for pre-3.4.5 versions which did not serialize an
    // identifier. That was a bad idea because actions need a way to refer to an item since titles
    // could be ambiguous. The key thing about it is that it's stable. You can create new actions,
    // and they'll have GUIDs, even if your snippet table doesn't get re-written. If you edit your
    // snippets then they will all be assigned GUIDs. The only problem is if you downgrade your
    // actions will be broken since they'll continue to have GUIDs but older versions expect them to
    // have titles (and it'll probably crash. Don't downgrade).
    iTermSendTextEscaping escaping;
    const int version = [dictionary[@"version"] intValue];
    if (version == 0) {
        escaping = iTermSendTextEscapingCompatibility;  // v0 migration path
    } else if (version == 1) {
        escaping = iTermSendTextEscapingCommon;  // v1 migration path
    } else {
        // v2+
        escaping = [dictionary[@"escaping"] unsignedIntegerValue];  // newest format
    }
    self = [self initWithTitle:title
                         value:value
                          guid:dictionary[@"guid"] ?: [[@[ [@(i) stringValue], title, value ] hashWithSHA256] it_hexEncoded]
                          tags:dictionary[@"tags"] ?: @[]
                      escaping:escaping
                       version:version];
    if (self) {
        self->_dictionary = [dictionary copy];
    }
    return self;
}

- (NSDictionary *)dictionaryValue {
    if (_dictionary) {
        return _dictionary;
    }
    return @{ @"title": _title ?: @"",
              @"value": _value ?: @"",
              @"guid": _guid,
              @"tags": _tags ?: @[],
              @"version": @(_version),
              @"escaping": @(_escaping)
    };
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }
    iTermSnippet *other = [iTermSnippet castFrom:object];
    if (!other) {
        return NO;
    }
    return [self.guid isEqual:other.guid];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p title=%@ value=%@ guid=%@ version=%@ escaping=%@>",
            NSStringFromClass([self class]),
            self,
            _title,
            _value,
            _guid,
            @(_version),
            @(_escaping)];
}

- (NSString *)trimmedValue:(NSInteger)maxLength {
    return [self.value ellipsizedDescriptionNoLongerThan:maxLength];
}

- (NSString *)trimmedValue:(NSInteger)maxLength includingRange:(NSRange)range {
    NSRange proposed = range;
    if (proposed.length > maxLength) {
        proposed.length = maxLength;
    } else {
        NSInteger midpoint = range.location + range.length / 2;
        NSInteger radius = maxLength / 2;
        NSInteger start = MAX(0, midpoint - radius);
        NSInteger limit = MIN(self.value.length, start + maxLength);
        NSInteger underage = maxLength - (limit - start);
        if (underage > 0) {
            start = MAX(0, start - underage);
            limit = MIN(start + maxLength, self.value.length);
        }
        proposed = NSMakeRange(start, limit - start);
    }
    NSString *end = [[self.value substringFromIndex:proposed.location] ellipsizedDescriptionNoLongerThan:proposed.length];
    if (proposed.location > 0) {
        return [@"…" stringByAppendingString:end];
    }
    return end;
}

- (NSString *)trimmedTitle:(NSInteger)maxLength {
    return [self.title ellipsizedDescriptionNoLongerThan:maxLength];
}

- (BOOL)titleEqualsValueUpToLength:(NSInteger)maxLength {
    return [[self trimmedTitle:maxLength] isEqualToString:[self trimmedValue:maxLength]];
}

- (id)actionKey {
    return @{ @"guid": _guid };
}

- (BOOL)matchesActionKey:(id)actionKey {
    if ([actionKey isEqual:self.actionKey]) {
        return YES;
    }
    if ([actionKey isEqual:self.title]) {
        return YES;
    }
    return NO;
}

- (NSString *)displayTitle {
    if (self.title.length == 0) {
        return [self.value ellipsizedDescriptionNoLongerThan:30];
    }
    return self.title;
}

- (BOOL)hasTags:(NSArray<NSString *> *)tags {
    for (NSString *tag in tags) {
        if (![self.tags containsObject:tag]) {
            return NO;
        }
    }
    return YES;
}

- (NSComparisonResult)compareTitle:(iTermSnippet *)other {
    return [self.title compare:other.title];
}

- (iTermSnippet *)copyWithSearchMatches:(NSDictionary<NSString *, NSIndexSet *> *)searchMatches {
    iTermSnippet *copy = [[iTermSnippet alloc] initWithTitle:self.title
                                                       value:self.value
                                                        guid:self.guid
                                                        tags:self.tags
                                                    escaping:self.escaping
                                                     version:[iTermSnippet currentVersion]];
    copy->_searchMatches = [searchMatches copy];
    return copy;

}

- (iTermSnippet *)clone {
    return [[iTermSnippet alloc] initWithTitle:self.title
                                         value:self.value
                                          guid:[[NSUUID UUID] UUIDString]
                                          tags:self.tags
                                      escaping:self.escaping
                                       version:[iTermSnippet currentVersion]];
}

@end

// Local-only (NoSync) record of the on-disk snippets.plist digest at the moment a fallback was
// created by a failed write. Lets ensurePersistedToDisk tell "disk is still the predecessor my write
// meant to replace" (safe to flush the fallback over it) from "disk changed under me since" (a fresh
// import; flushing would clobber it).
static NSString *const kSnippetsFallbackPredecessorDigestKey = @"NoSyncSnippetsFallbackPredecessorDigest";
// Recovery lists (local-only) for a fallback we back up before clearing: one for a fallback superseded
// by an on-disk import/deletion, one for a fallback explicitly discarded by "Lose Changes".
static NSString *const kSnippetsSupersededFallbackBackupKey = @"NoSyncSnippetsSupersededFallbackBackup";
static NSString *const kSnippetsDiscardedFallbackBackupKey = @"NoSyncSnippetsDiscardedFallbackBackup";

@implementation iTermSnippetsModel {
    NSMutableArray<iTermSnippet *> *_snippets;
    // Set at init when snippets.plist exists on disk but cannot be parsed (and no user-defaults
    // fallback shadows it), so the shared loader mapped it to an empty set. While this is set and the
    // in-memory set is still empty, -save refuses to overwrite the corrupt file with a valid empty
    // plist that the settings-sync layer would publish fleet-wide. Cleared once a definitive on-disk
    // state is adopted (a good reload, a propagated deletion) or the user repopulates the set.
    BOOL _loadedFromUnparseableFile;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

+ (NSString *)plistPathCreatingFolderIfNeeded:(BOOL)create {
    NSString *appSupport;
    if (create) {
        appSupport = [[NSFileManager defaultManager] applicationSupportDirectory];
    } else {
        appSupport = [[NSFileManager defaultManager] applicationSupportDirectoryWithoutCreating];
        if (!appSupport) {
            return nil;
        }
    }
    // Reference the sync allowlist's constant rather than a bare literal so this on-disk name and the
    // synced allowlist can never drift apart silently (a rename is a single edit that moves both).
    return [appSupport stringByAppendingPathComponent:iTermRemoteDataFileSync.snippetsPlistName];
}

+ (NSArray<NSDictionary *> *)freshlyLoadedValues {
    id obj = [[iTermUserDefaults userDefaults] objectForKey:kPreferenceKeySnippets];
    if (obj) {
        return [NSArray castFrom:obj];
    }
    NSString *path = [self plistPathCreatingFolderIfNeeded:NO];
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
    return plist[@"snippets"];
}

// Append a superseded/discarded user-defaults fallback (snippets that may exist nowhere else after a
// failed plist write) to a recovery list, keeping the most recent few. A single fixed key would let a
// second supersession or discard clobber the earlier backup, defeating the "always recoverable"
// guarantee; an unbounded list would grow without limit.
+ (void)appendFallbackBackup:(id)fallback underKey:(NSString *)key {
    if (fallback == nil) {
        return;
    }
    NSArray *existing = [NSArray castFrom:[[iTermUserDefaults userDefaults] objectForKey:key]] ?: @[];
    NSMutableArray *updated = [existing mutableCopy];
    [updated addObject:fallback];
    const NSInteger maxBackups = 10;
    while (updated.count > maxBackups) {
        [updated removeObjectAtIndex:0];
    }
    [[iTermUserDefaults userDefaults] setObject:updated forKey:key];
}

// Back the current user-defaults fallback up (under `key`, recoverable) and then clear BOTH the
// fallback key and its predecessor-digest companion. Centralized so no call site can drift (e.g.
// forget to clear the predecessor digest). No-op if there is no fallback.
+ (void)backUpAndClearFallbackUnderKey:(NSString *)key {
    id fallback = [[iTermUserDefaults userDefaults] objectForKey:kPreferenceKeySnippets];
    if (fallback == nil) {
        return;
    }
    [self appendFallbackBackup:fallback underKey:key];
    [[iTermUserDefaults userDefaults] removeObjectForKey:kPreferenceKeySnippets];
    [[iTermUserDefaults userDefaults] removeObjectForKey:kSnippetsFallbackPredecessorDigestKey];
}

// Hex SHA-256 of the on-disk snippets.plist bytes, or nil if it is absent/unreadable. Used to record
// and later recognize the predecessor a failed write meant to replace.
+ (NSString *)onDiskDigest {
    NSString *path = [self plistPathCreatingFolderIfNeeded:NO];
    if (path == nil) {
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data == nil) {
        return nil;
    }
    return [[data it_sha256] it_hexEncoded];
}

+ (void)writeDictionaries:(NSArray<NSDictionary *> *)arrayOfDictionaries {
    NSString *path = [self plistPathCreatingFolderIfNeeded:YES];
    NSDictionary *plist = @{ @"snippets": arrayOfDictionaries };
    NSError *error = nil;
    [plist writeToURL:[NSURL fileURLWithPath:path] error:&error];
    if (error) {
        // Fall back to user defaults to avoid losing data but then we are subject to a potentially
        // catastrophic size limit on user defaults. The write is atomic, so the OLD snippets.plist (if
        // any) survived intact; record its digest as the predecessor so ensurePersistedToDisk can
        // later tell it apart from a fresh import that lands after this failure.
        NSString *predecessorDigest = [self onDiskDigest];
        [[iTermUserDefaults userDefaults] setObject:arrayOfDictionaries
                                                  forKey:kPreferenceKeySnippets];
        if (predecessorDigest) {
            [[iTermUserDefaults userDefaults] setObject:predecessorDigest
                                                 forKey:kSnippetsFallbackPredecessorDigestKey];
        } else {
            [[iTermUserDefaults userDefaults] removeObjectForKey:kSnippetsFallbackPredecessorDigestKey];
        }
        [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"There was a problem saving snippets to “%@”.\n\nThe error was:\n%@", path, error.localizedDescription]
                                   actions:@[ @"OK" ]
                                 accessory:nil
                                identifier:@"NoSyncWriteSnippetsFailed"
                               silenceable:kiTermWarningTypePersistent
                                   heading:@"Problem Saving Snippets"
                                    window:nil];
    } else {
        [[iTermUserDefaults userDefaults] removeObjectForKey:kPreferenceKeySnippets];
        [[iTermUserDefaults userDefaults] removeObjectForKey:kSnippetsFallbackPredecessorDigestKey];
    }
}

+ (NSMutableArray<iTermSnippet *> *)loadSnippetsFromDisk {
    __block NSInteger i = 0;
    return [[[iTermSnippetsModel freshlyLoadedValues] mapWithBlock:^id(id anObject) {
        NSDictionary *dict = [NSDictionary castFrom:anObject];
        if (!dict) {
            return nil;
        }
        return [[iTermSnippet alloc] initWithDictionary:dict index:i++];
    }] mutableCopy] ?: [NSMutableArray array];
}

// YES when snippets.plist exists on disk but does not parse into a snippets array, AND no user-defaults
// fallback shadows it. In that state the shared loader (+loadSnippetsFromDisk) maps the missing array to
// an empty set, so -init would come up with zero snippets. Now that snippets.plist is a synced file, a
// corrupt copy (a truncated/partial write, or bad bytes synced from another Mac) must not be treated as
// a legitimate empty set: the next -save would replace the corrupt file with a valid empty plist and the
// sync push would wipe every other machine's snippets. -init records this so -save can refuse that write.
// When there IS a fallback it is authoritative and the disk file is not consulted, so this returns NO.
// Pure classification, split out so it is unit-testable without touching the fixed app-support path or
// user defaults. A fallback shadows the disk file and is authoritative, so any disk corruption is moot
// (returns NO). An absent file is a legitimate empty/first-run state (NO). A present file that does not
// parse into a snippets array (bad bytes, a truncated write, a non-dict root, or a dict lacking the
// array) is the present-but-unparseable case (YES).
+ (BOOL)fileIsPresentButUnparseableWithFallbackPresent:(BOOL)fallbackPresent
                                            fileExists:(BOOL)fileExists
                                              fileData:(nullable NSData *)fileData {
    if (fallbackPresent) {
        return NO;
    }
    if (!fileExists) {
        return NO;
    }
    NSDictionary *plist = nil;
    if (fileData != nil) {
        plist = [NSDictionary castFrom:[NSPropertyListSerialization propertyListWithData:fileData
                                                                                 options:0
                                                                                  format:NULL
                                                                                   error:NULL]];
    }
    return [NSArray castFrom:plist[@"snippets"]] == nil;
}

+ (BOOL)onDiskFileIsPresentButUnparseable {
    const BOOL fallbackPresent = ([[iTermUserDefaults userDefaults] objectForKey:kPreferenceKeySnippets] != nil);
    NSString *path = [self plistPathCreatingFolderIfNeeded:NO];
    const BOOL fileExists = (path != nil && [[NSFileManager defaultManager] fileExistsAtPath:path]);
    NSData *data = fileExists ? [NSData dataWithContentsOfFile:path] : nil;
    return [self fileIsPresentButUnparseableWithFallbackPresent:fallbackPresent
                                                    fileExists:fileExists
                                                      fileData:data];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _loadedFromUnparseableFile = [iTermSnippetsModel onDiskFileIsPresentButUnparseable];
        _snippets = [iTermSnippetsModel loadSnippetsFromDisk];
    }
    return self;
}

- (void)reloadFromDisk {
    NSString *path = [iTermSnippetsModel plistPathCreatingFolderIfNeeded:NO];
    const BOOL fileExists = (path != nil && [[NSFileManager defaultManager] fileExistsAtPath:path]);

    id fallback = [[iTermUserDefaults userDefaults] objectForKey:kPreferenceKeySnippets];
    if (fallback != nil) {
        // Snippets currently live in the user-defaults fallback (a prior plist write failed). Normally
        // the fallback is authoritative and must not be cleared (it may be the only copy). But if the
        // import changed on-disk state out from under the lingering fallback, keeping the fallback would
        // ignore that change and a later -save would clobber it, so we back the fallback up (recoverable)
        // and adopt disk. Two such cases:
        if (!fileExists) {
            // The import propagated a DELETION (snippets.plist now absent). Keeping the fallback would
            // ignore the deletion and a later -save would recreate the file, republishing the deleted
            // snippets fleet-wide. Back the fallback up and clear it, then fall through to the
            // deletion-propagation branch below (which clears the in-memory set).
            DLog(@"Snippets deleted by import while an un-flushed fallback lingered; backing up the fallback and reflecting the deletion");
            [iTermSnippetsModel backUpAndClearFallbackUnderKey:kSnippetsSupersededFallbackBackupKey];
            // Fall through (fallback cleared) to the !fileExists deletion branch below.
        } else {
            NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
            NSArray *onDisk = [NSArray castFrom:plist[@"snippets"]];
            if (onDisk != nil && ![onDisk isEqual:[NSArray castFrom:fallback]]) {
                // An import wrote a snippets.plist that DIFFERS from the fallback (the flush write
                // failed yet the pull's write succeeded). Back the fallback up and adopt the import.
                DLog(@"Imported snippets.plist differs from the un-flushed fallback; backing up the fallback and adopting the import");
                [iTermSnippetsModel backUpAndClearFallbackUnderKey:kSnippetsSupersededFallbackBackupKey];
                // Fall through to load the imported file below.
            } else {
                // Unparseable, or already equal to the fallback: the fallback stays the only/authoritative
                // copy. (When the disk becomes writable the flush in -ensurePersistedToDisk reconciles
                // the difference through the conflict/backup path.)
                DLog(@"Snippets are in the user-defaults fallback; not reloading to avoid data loss");
                return;
            }
        }
    }

    if (!fileExists) {
        // The file is definitively gone: a launch-time unparseable state (if any) no longer applies, so
        // clear the guard that would refuse an empty writeback.
        _loadedFromUnparseableFile = NO;
        // With no fallback, an absent snippets.plist means the import propagated a DELETION (the
        // reconcile's deleteMissing:YES pull removed it). Clear the in-memory snippets so the deletion
        // is reflected, mirroring how ToolNotes clears its view when notes.rtfd is deleted. Otherwise
        // the stale in-memory set would survive and a later -save would recreate the deleted snippets
        // and push them back, undoing the deletion fleet-wide.
        if (_snippets.count > 0) {
            _snippets = [NSMutableArray array];
            [[iTermSnippetsDidChangeNotification fullReplacementNotification] post];
        }
        return;
    }

    // The content-signature gate only proved the imported bytes were readable, not that they parse as
    // a valid snippets plist. A truncated/partial write or a structurally wrong root would make
    // dictionaryWithContentsOfFile return nil (or lack a snippets array), and loadSnippetsFromDisk
    // would then map that to an empty array, wiping the in-memory snippets and writing the empty set
    // back on the next edit. Guard against that the way ToolNotes guards a notes read failure: leave
    // the current snippets untouched and skip the notification.
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
    NSArray *onDisk = [NSArray castFrom:plist[@"snippets"]];
    if (!onDisk) {
        DLog(@"Imported snippets.plist is present but unparseable; keeping current snippets");
        return;
    }
    // The on-disk file now parses, so any launch-time unparseable state has been superseded by a good
    // file: clear the guard so normal saves resume.
    _loadedFromUnparseableFile = NO;
    // Skip the reassign + full-replacement post when the imported file is byte-identical to what's
    // already in memory (a folder touch, or a re-import of a file this machine just authored). A
    // full-replacement resets every open snippets UI, losing selection and in-progress row edits, so
    // only fire it on a real change. dictionaryValue is the canonical serialized form (the same dicts a
    // save writes), so equal serialized arrays mean identical content; this never suppresses a real one.
    NSArray *currentSerialized = [_snippets mapWithBlock:^id(iTermSnippet *snippet) {
        return snippet.dictionaryValue;
    }];
    if ([onDisk isEqualToArray:currentSerialized]) {
        DLog(@"Imported snippets.plist matches the in-memory snippets; skipping redundant full reload");
        return;
    }
    _snippets = [iTermSnippetsModel loadSnippetsFromDisk];
    [[iTermSnippetsDidChangeNotification fullReplacementNotification] post];
}

// If snippets currently live only in the user-defaults fallback (a prior plist write failed), retry
// writing them to disk. The settings-sync layer reads only on-disk state, so without this a first
// folder-adoption would treat fallback-only snippets as "nothing local to lose" and silently
// overwrite them. After a successful flush the on-disk file reflects the real snippets, so sync sees
// them and routes through the conflict/backup path.
- (void)ensurePersistedToDisk {
    id fallback = [[iTermUserDefaults userDefaults] objectForKey:kPreferenceKeySnippets];
    if (fallback == nil) {
        return;
    }
    // The plist write is atomic, so after a failed write the OLD file survives and onDisk != fallback
    // is the NORM, not the exception. A blanket "skip flush when disk differs from fallback" would
    // therefore skip the retry in exactly the case it exists for. Instead compare against the
    // predecessor digest recorded when the fallback was created.
    NSString *currentDigest = [iTermSnippetsModel onDiskDigest];
    NSString *predecessorDigest = [NSString castFrom:[[iTermUserDefaults userDefaults] objectForKey:kSnippetsFallbackPredecessorDigestKey]];
    const BOOL neverHadFile = (currentDigest == nil && predecessorDigest == nil);
    const BOOL diskIsPredecessor = (currentDigest != nil && [currentDigest isEqualToString:predecessorDigest]);
    if (neverHadFile || diskIsPredecessor) {
        // Either our failed write never created a file (nothing to lose on disk), or the disk still
        // holds the exact predecessor our failed write meant to replace. Flushing the fallback over it
        // is precisely the retry this method exists for. -save clears the fallback and the predecessor
        // key on success.
        [self save];
        return;
    }
    // Otherwise the on-disk state changed out from under the fallback since it was created: either a
    // newer copy was imported (the sync layer writes snippets.plist directly, bypassing the model), or
    // the file was DELETED under us by a sync-propagated deletion (currentDigest == nil while a
    // predecessor existed). In both cases the on-disk state wins: flushing the fallback would clobber
    // the import or RESURRECT the deleted snippets and re-publish them fleet-wide with no conflict
    // prompt. Back up the un-flushed fallback (recoverable, local-only) and clear it so it stops
    // shadowing disk, then re-sync memory from disk (reloadFromDisk reflects an import or, for a
    // deletion, the now-absent file).
    DLog(@"Snippets fallback superseded by a newer on-disk state (import or deletion); backing up fallback and adopting disk");
    [iTermSnippetsModel backUpAndClearFallbackUnderKey:kSnippetsSupersededFallbackBackupKey];
    [self reloadFromDisk];
}

// A "Lose Changes"/discard removed snippets.plist from disk, but an un-flushed user-defaults fallback
// (from a prior failed plist write) would otherwise be resurrected by the next launch's
// ensurePersistedToDisk flush, undoing the discard. Back the fallback up (local-only, recoverable)
// and clear it so the discard actually sticks. Only when a fallback was actually cleared do we then
// reload: that re-syncs the in-memory model (which had been serving the fallback content) to the
// on-disk plist the fallback was shadowing, so a later pull that leaves snippets.plist untouched
// doesn't leave memory serving the discarded fallback. When there was no fallback we skip the reload
// entirely, so a discard doesn't post a spurious full-replacement (UI churn, arming the save debounce)
// every time; the caller reloads the actually-changed owners afterward.
- (void)discardUnflushedFallbackBackingUp {
    if ([[iTermUserDefaults userDefaults] objectForKey:kPreferenceKeySnippets] == nil) {
        // No fallback: skip the reload so a discard doesn't post a spurious full-replacement.
        return;
    }
    [iTermSnippetsModel backUpAndClearFallbackUnderKey:kSnippetsDiscardedFallbackBackupKey];
    [self reloadFromDisk];
}

- (void)addSnippet:(iTermSnippet *)snippet {
    [_snippets addObject:snippet];
    [self save];
    [[iTermSnippetsDidChangeNotification notificationWithMutationType:iTermSnippetsDidChangeMutationTypeInsertion index:_snippets.count - 1] post];
}

- (void)removeSnippets:(NSArray<iTermSnippet *> *)snippets {
    NSIndexSet *indexes = [_snippets it_indexSetWithIndexesOfObjects:snippets];
    [_snippets removeObjectsAtIndexes:indexes];
    [self save];
    [[iTermSnippetsDidChangeNotification removalNotificationWithIndexes:indexes] post];
}

- (void)replaceSnippet:(iTermSnippet *)snippetToReplace withSnippet:(iTermSnippet *)replacement {
    NSInteger index = [_snippets indexOfObject:snippetToReplace];
    if (index == NSNotFound) {
        return;
    }
    _snippets[index] = replacement;
    [self save];
    [[iTermSnippetsDidChangeNotification notificationWithMutationType:iTermSnippetsDidChangeMutationTypeEdit index:index] post];
}

- (NSInteger)indexOfSnippetWithGUID:(NSString *)guid {
    return [_snippets indexOfObjectPassingTest:^BOOL(iTermSnippet * _Nonnull snippet, NSUInteger idx, BOOL * _Nonnull stop) {
        return [snippet.guid isEqual:guid];
    }];
}

- (iTermSnippet *)snippetWithGUID:(NSString *)guid {
    const NSInteger i = [self indexOfSnippetWithGUID:guid];
    if (i == NSNotFound) {
        return nil;
    }
    return _snippets[i];
}

- (nullable iTermSnippet *)snippetWithActionKey:(id)actionKey {
    return [_snippets objectPassingTest:^BOOL(iTermSnippet *snippet, NSUInteger index, BOOL *stop) {
        return [snippet matchesActionKey:actionKey];
    }];
}

+ (BOOL)snippet:(iTermSnippet *)snippet matchesQuery:(NSString *)queryString {
    if (queryString.length == 0) {
        return YES;
    }
    NSArray<NSString *> *operators = @[ @"tag:", @"title:", @"text:" ];
    iTermProfileStyleSearchEngineQuery *query =
        [[iTermProfileStyleSearchEngineQuery alloc] initWithQuery:queryString
                                                        operators:operators];
    iTermProfileStyleSearchEngine *engine = [[iTermProfileStyleSearchEngine alloc] initWithQuery:query];

    NSDictionary<NSString *, NSString *> *phrases = @{ @"title:": snippet.title ?: @"",
                                                       @"text:": snippet.value ?: @"" };
    iTermProfileStyleSearchEngineDocument *doc =
    [[iTermProfileStyleSearchEngineDocument alloc] initWithPhrases:phrases
                                                              tags:snippet.tags];
    iTermProfileStyleSearchEngineResult *result = [engine searchWithDocument:doc sloppy:NO];
    return result != nil;
}

+ (BOOL)snippet:(iTermSnippet *)snippet
   matchesQuery:(NSString *)queryString
 additionalTags:(NSArray<NSString *> *)additionalTags {
    return [self snippetsMatchingSearchQuery:queryString
                              additionalTags:additionalTags
                                   tagsFound:nil
                                    snippets:@[ snippet ]].count > 0;
}

- (NSArray<iTermSnippet *> *)snippetsMatchingSearchQuery:(NSString *)queryString
                                          additionalTags:(NSArray<NSString *> *)additionalTags
                                               tagsFound:(out BOOL *)tagsFoundPtr {
    return [iTermSnippetsModel snippetsMatchingSearchQuery:queryString
                                            additionalTags:additionalTags
                                                 tagsFound:tagsFoundPtr
                                                  snippets:self.snippets];
}

+ (NSArray<iTermSnippet *> *)snippetsMatchingSearchQuery:(NSString *)queryString
                                          additionalTags:(NSArray<NSString *> *)additionalTags
                                               tagsFound:(out BOOL *)tagsFoundPtr
                                                snippets:(NSArray<iTermSnippet *> *)snippets {
    if (queryString.length == 0 && additionalTags.count == 0) {
        return [snippets copy];
    }
    NSArray<NSString *> *operators = @[ @"tag:", @"title:", @"text:" ];
    iTermProfileStyleSearchEngineQuery *query =
        [[iTermProfileStyleSearchEngineQuery alloc] initWithQuery:queryString
                                                        operators:operators];
    for (NSString *tag in additionalTags) {
        [query addTag:tag];
    }
    iTermProfileStyleSearchEngine *engine = [[iTermProfileStyleSearchEngine alloc] initWithQuery:query];

    NSArray<iTermSnippet *> *filteredSnippets =
    [snippets mapWithBlock:^iTermSnippet *(iTermSnippet *snippet) {
        NSDictionary<NSString *, NSString *> *phrases = @{ @"title:": snippet.title ?: @"",
                                                           @"text:": snippet.value ?: @"" };
        iTermProfileStyleSearchEngineDocument *doc =
        [[iTermProfileStyleSearchEngineDocument alloc] initWithPhrases:phrases
                                                                  tags:snippet.tags];
        iTermProfileStyleSearchEngineResult *result = [engine searchWithDocument:doc sloppy:NO];
        if (!result) {
            return nil;
        }
        return [snippet copyWithSearchMatches:result.phraseIndexes];
    }];
    if (tagsFoundPtr) {
        *tagsFoundPtr = [additionalTags count] > 0 || query.hasTags;
    }
    return filteredSnippets;
}

- (void)moveSnippetsWithGUIDs:(NSArray<NSString *> *)guids
                      toIndex:(NSInteger)row {
    NSArray<iTermSnippet *> *snippets = [_snippets filteredArrayUsingBlock:^BOOL(iTermSnippet *snippet) {
        return [guids containsObject:snippet.guid];
    }];
    NSInteger countBeforeRow = [[snippets filteredArrayUsingBlock:^BOOL(iTermSnippet *snippet) {
        return [self indexOfSnippetWithGUID:snippet.guid] < row;
    }] count];
    NSMutableArray<iTermSnippet *> *updatedSnippets = [_snippets mutableCopy];
    NSMutableIndexSet *removals = [NSMutableIndexSet indexSet];
    for (iTermSnippet *snippet in snippets) {
        const NSInteger i = [_snippets indexOfObject:snippet];
        assert(i != NSNotFound);
        [removals addIndex:i];
        [updatedSnippets removeObject:snippet];
    }
    NSInteger insertionIndex = row - countBeforeRow;
    for (iTermSnippet *snippet in snippets) {
        [updatedSnippets insertObject:snippet atIndex:insertionIndex++];
    }
    _snippets = updatedSnippets;
    [self save];
    [[iTermSnippetsDidChangeNotification moveNotificationWithRemovals:removals
                                                     destinationIndex:row - countBeforeRow] post];
}

- (void)setSnippets:(NSArray<iTermSnippet *> *)snippets {
    _snippets = [snippets mutableCopy];
    [self save];
    [[iTermSnippetsDidChangeNotification fullReplacementNotification] post];
}

#pragma mark - Private

- (void)save {
    if (_loadedFromUnparseableFile && _snippets.count == 0) {
        // We launched with a present-but-unparseable snippets.plist, so the in-memory set loaded empty
        // (see -init). Writing that empty set back would replace the corrupt-but-preserved file with a
        // VALID empty plist, which the settings-sync layer would push to every other machine, wiping
        // their snippets fleet-wide. Refuse the write while the set is still empty, leaving the corrupt
        // file in place (recoverable). As soon as the user adds a snippet the set is non-empty and normal
        // saves resume (the corrupt originals were unrecoverable regardless); a reloadFromDisk that
        // adopts a good file or a propagated deletion also clears the flag.
        DLog(@"Refusing to overwrite a present-but-unparseable snippets.plist with an empty set");
        return;
    }
    _loadedFromUnparseableFile = NO;
    [iTermSnippetsModel writeDictionaries:[self arrayOfDictionaries]];
}

- (NSArray<NSDictionary *> *)arrayOfDictionaries {
    return [_snippets mapWithBlock:^id(iTermSnippet *snippet) {
        return snippet.dictionaryValue;
    }];
}

@end

@implementation iTermSnippetsDidChangeNotification

+ (instancetype)notificationWithMutationType:(iTermSnippetsDidChangeMutationType)mutationType index:(NSInteger)index {
    iTermSnippetsDidChangeNotification *notif = [[self alloc] initPrivate];
    notif->_mutationType = mutationType;
    notif->_index = index;
    return notif;
}

+ (instancetype)moveNotificationWithRemovals:(NSIndexSet *)removals
                            destinationIndex:(NSInteger)destinationIndex {
    iTermSnippetsDidChangeNotification *notif = [[self alloc] initPrivate];
    notif->_mutationType = iTermSnippetsDidChangeMutationTypeMove;
    notif->_indexSet = removals;
    notif->_index = destinationIndex;
    return notif;
}

+ (instancetype)fullReplacementNotification {
    iTermSnippetsDidChangeNotification *notif = [[self alloc] initPrivate];
    notif->_mutationType = iTermSnippetsDidChangeMutationTypeFullReplacement;
    return notif;
}

+ (instancetype)removalNotificationWithIndexes:(NSIndexSet *)indexes {
    iTermSnippetsDidChangeNotification *notif = [[self alloc] initPrivate];
    notif->_mutationType = iTermSnippetsDidChangeMutationTypeDeletion;
    notif->_indexSet = indexes;
    return notif;
}

+ (void)subscribe:(NSObject *)owner
            block:(void (^)(iTermSnippetsDidChangeNotification * _Nonnull notification))block {
    [self internalSubscribe:owner withBlock:block];
}

@end
