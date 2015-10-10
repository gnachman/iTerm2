//
//  CommandHistory.m
//  iTerm
//
//  Created by George Nachman on 1/6/14.
//
//

#import "iTermShellHistoryController.h"

#import "iTermCommandHistoryEntryMO+Additions.h"
#import "iTermDirectoryTree.h"
#import "iTermHostRecordMO.h"
#import "iTermHostRecordMO+Additions.h"
#import "iTermPreferences.h"
#import "iTermRecentDirectoryMO.h"
#import "iTermRecentDirectoryMO+Additions.h"
#import "NSArray+iTerm.h"
#import "iTermCommandHistoryEntryMO.h"
#import "PreferencePanel.h"
#import "VT100RemoteHost.h"
#import "VT100ScreenMark.h"

NSString *const kCommandHistoryDidChangeNotificationName = @"kCommandHistoryDidChangeNotificationName";
NSString *const kDirectoriesDidChangeNotificationName = @"kDirectoriesDidChangeNotificationName";
NSString *const kCommandHistoryHasEverBeenUsed = @"NoSyncCommandHistoryHasEverBeenUsed";

static const int kMaxResults = 200;

static const NSTimeInterval kMaxTimeToRememberCommands = 60 * 60 * 24 * 90;
static const NSTimeInterval kMaxTimeToRememberDirectories = 60 * 60 * 24 * 90;

@interface VT100RemoteHost (CommandHistory)

- (NSString *)key;

@end

@implementation VT100RemoteHost (CommandHistory)

- (NSString *)key {
    return [NSString stringWithFormat:@"%@@%@", self.username, self.hostname];
}

@end

@implementation iTermShellHistoryController {
    NSMutableDictionary<NSString *, iTermHostRecordMO *> *_records;
    
    // Keys are remote host keys, "user@hostname".
    NSMutableDictionary<NSString *, NSMutableArray<iTermCommandHistoryCommandUseMO *> *> *_expandedCache;
    NSManagedObjectContext *_managedObjectContext;
    iTermDirectoryTree *_tree;

    // Prevents notifications from being posted durinig initialization since that causes deadlock in
    // -sharedInstance.
    BOOL _initializing;

    // Current store is on-disk?
    BOOL _savingToDisk;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (id)init {
    self = [super init];
    if (self) {
        _initializing = YES;
        if (![self finishInitialization]) {
            return nil;
        }
    }
    return self;
}

- (instancetype)initPartially {
    self = [super init];
    if (self) {
        _initializing = YES;
    }
    return self;
}

- (BOOL)finishInitialization {
    if (![self initializeCoreDataWithRetry:YES vacuum:NO]) {
        [self release];
        return NO;
    }
    _records = [[NSMutableDictionary alloc] init];
    _expandedCache = [[NSMutableDictionary alloc] init];
    _tree = [[iTermDirectoryTree alloc] init];

    [self migrateFromPlistToCoreData];
    [self removeOldData];
    [self loadObjectGraph];

    _initializing = NO;
    return YES;
}

- (NSString *)pathForFileNamed:(NSString *)name {
    NSString *path;
    path = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                NSUserDomainMask,
                                                YES) lastObject];
    NSString *appname =
        [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleNameKey];
    path = [path stringByAppendingPathComponent:appname];
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return [path stringByAppendingPathComponent:name];
}

- (NSString *)pathToDeprecatedCommandHistoryPlist {
    return [self pathForFileNamed:@"commandhistory.plist"];
}

- (NSString *)pathToDeprecatedDirectoriesPlist {
    return [self pathForFileNamed:@"directories.plist"];
}

- (NSString *)databaseFilenamePrefix {
    return @"CommandHistory.sqlite";
}

- (NSString *)pathToDatabase {
    return [self pathForFileNamed:self.databaseFilenamePrefix];
}

- (void)dealloc {
    [_records release];
    [_expandedCache release];
    [_managedObjectContext release];
    [_tree release];
    [super dealloc];
}

// Note: setting vacuum to YES forces it to use the on-disk sqlite database. This allows you to
// vacuum a database after changing the setting to in-memory. It doesn't make sense to vacuum RAM,
// after all.
- (BOOL)initializeCoreDataWithRetry:(BOOL)retry vacuum:(BOOL)vacuum {
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"Model" withExtension:@"momd"];
    assert(modelURL);

    NSManagedObjectModel *managedObjectModel =
        [[[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL] autorelease];
    assert(managedObjectModel);

    NSPersistentStoreCoordinator *persistentStoreCoordinator =
        [[[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:managedObjectModel] autorelease];
    assert(persistentStoreCoordinator);
    
    _managedObjectContext =
        [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    assert(_managedObjectContext);

    _managedObjectContext.persistentStoreCoordinator = persistentStoreCoordinator;
    NSURL *storeURL = [NSURL fileURLWithPath:[self pathToDatabase]];

    // Apple wants you to do this on a background thread, but you can't do a fetch until it's done.
    // Since -init does a fetch, there's no point doing this on a background thread, since it would
    // need to wait for it to finish before -loadCommandHistory could be called.
    NSError *error = nil;
    NSString *storeType;
    if ([self saveToDisk] || vacuum) {
        _savingToDisk = YES;
        storeType = NSSQLiteStoreType;
    } else {
        _savingToDisk = NO;
        storeType = NSInMemoryStoreType;
    }

    NSDictionary *options = @{};
    if (vacuum) {
        options = @{ NSSQLiteManualVacuumOption: @YES };
    }
    // An exception will be thrown here during the unit test that checks database corruption.
    // This is expected, just hit continue.
    [persistentStoreCoordinator addPersistentStoreWithType:storeType
                                             configuration:nil
                                                       URL:storeURL
                                                   options:options
                                                     error:&error];
    if (error) {
        NSLog(@"Got an exception when opening the command history database: %@", error);
        if (![self saveToDisk]) {
            NSLog(@"This is an in-memory database, it should not fail.");
            return NO;
        }
        if (!retry) {
            NSLog(@"Giving up");
            return NO;
        }
        
        NSLog(@"Deleting the presumably corrupt file and trying again");
        NSError *removeError = nil;
        [self deleteDatabase];
        if (removeError) {
            NSLog(@"Failed to delete corrupt database: %@", removeError);
            return NO;
        }
        
        NSLog(@"Trying again...");
        [_managedObjectContext release];
        _managedObjectContext = nil;
        return [self initializeCoreDataWithRetry:NO vacuum:vacuum];
    }
    
    return YES;
}

- (void)backingStoreTypeDidChange {
    if (!self.saveToDisk) {
        [self eraseCommandHistory:YES directories:YES];
    }

    [_managedObjectContext release];
    _managedObjectContext = nil;
    [self initializeCoreDataWithRetry:YES vacuum:NO];

    // Reload everything.
    [_records removeAllObjects];
    [_expandedCache removeAllObjects];
    [_tree release];
    _tree = [[iTermDirectoryTree alloc] init];
    [self loadObjectGraph];

    if (!_initializing) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kDirectoriesDidChangeNotificationName
                                                            object:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:kCommandHistoryDidChangeNotificationName
                                                            object:nil];
    }
}

- (BOOL)saveToDisk {
    return [iTermPreferences boolForKey:kPreferenceKeySavePasteAndCommandHistory];
}

- (BOOL)deleteDatabase {
    NSString *path = [[self pathToDatabase] stringByDeletingLastPathComponent];
    NSDirectoryEnumerator<NSString *> *enumerator =
        [[NSFileManager defaultManager] enumeratorAtPath:path];
    BOOL foundAny = NO;
    BOOL anyErrors = NO;
    for (NSString *filename in enumerator) {
        if ([filename hasPrefix:[self databaseFilenamePrefix]]) {
            NSError *error = nil;
            [[NSFileManager defaultManager] removeItemAtPath:[path stringByAppendingPathComponent:filename]
                                                       error:&error];
            if (error) {
                anyErrors = YES;
            }
            foundAny = YES;
        }
    }
    return foundAny && !anyErrors;
}

#pragma mark - APIs

+ (void)showInformationalMessage {
    NSResponder *firstResponder = [[NSApp keyWindow] firstResponder];
    SEL selector = @selector(installShellIntegration:);
    if (![firstResponder respondsToSelector:selector]) {
        firstResponder = nil;
    }
    NSString *otherText = firstResponder ? @"Install Now" : nil;
    switch (NSRunInformationalAlertPanel(@"About Shell Integration",
                                         @"To use shell integration features such as "
                                         @"Command History, "
                                         @"Recent Directories, "
                                         @"Select Output of Last Command, "
                                         @"and Automatic Profile Switching, "
                                         @"your shell must be properly configured.",
                                         @"Learn More…",
                                         @"OK",
                                         otherText)) {
        case NSAlertDefaultReturn:
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://iterm2.com/shell_integration.html"]];
            break;

        case NSAlertOtherReturn:
            [firstResponder performSelector:selector withObject:self];
            break;
    }
}

- (BOOL)commandHistoryHasEverBeenUsed {
    return (_records.count > 0 ||
            [[NSUserDefaults standardUserDefaults] boolForKey:kCommandHistoryHasEverBeenUsed]);
}

- (iTermRecentDirectoryMO *)recordUseOfPath:(NSString *)path
                                     onHost:(VT100RemoteHost *)host
                                   isChange:(BOOL)isChange {
    if (!isChange || !path) {
        return nil;
    }

    iTermHostRecordMO *hostRecord = [self recordForHost:host];
    if (!hostRecord) {
        hostRecord = [iTermHostRecordMO hostRecordInContext:_managedObjectContext];
        hostRecord.hostname = host.hostname;
        hostRecord.username = host.username;
        [self setRecord:hostRecord forHost:host];
    }

    // Check if we already have it;
    iTermRecentDirectoryMO *directory = nil;
    for (iTermRecentDirectoryMO *existingDirectory in hostRecord.directories) {
        if ([existingDirectory.path isEqualToString:path]) {
            directory = existingDirectory;
            break;
        }
    }

    if (!directory) {
        // Is a new directory on this host.
        directory = [NSEntityDescription insertNewObjectForEntityForName:[iTermRecentDirectoryMO entityName]
                                                  inManagedObjectContext:_managedObjectContext];
        directory.path = path;
        [_tree addPath:path];
        [hostRecord addDirectoriesObject:directory];
    }
    directory.useCount = @(directory.useCount.integerValue + 1);
    directory.lastUse = @([self now]);

    [self saveDirectories];

    return directory;
}

- (NSArray *)directoriesSortedByScoreOnHost:(VT100RemoteHost *)host {
    return [[self directoriesForHost:host] sortedArrayUsingSelector:@selector(compare:)];
}

- (void)addCommand:(NSString *)command
            onHost:(VT100RemoteHost *)host
       inDirectory:(NSString *)directory
          withMark:(VT100ScreenMark *)mark {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kCommandHistoryHasEverBeenUsed];

    iTermHostRecordMO *hostRecord = [self recordForHost:host];
    if (!hostRecord) {
        hostRecord = [iTermHostRecordMO hostRecordInContext:_managedObjectContext];
        hostRecord.hostname = host.hostname;
        hostRecord.username = host.username;
        [self setRecord:hostRecord forHost:host];
    }

    iTermCommandHistoryEntryMO *theEntry = nil;
    for (iTermCommandHistoryEntryMO *entry in hostRecord.entries) {
        if ([entry.command isEqualToString:command]) {
            theEntry = entry;
            break;
        }
    }

    if (!theEntry) {
        theEntry = [iTermCommandHistoryEntryMO commandHistoryEntryInContext:_managedObjectContext];
        theEntry.command = command;
        [hostRecord addEntriesObject:theEntry];
    }
    
    theEntry.numberOfUses = @(theEntry.numberOfUses.integerValue + 1);
    theEntry.timeOfLastUse = @([self now]);
    
    iTermCommandHistoryCommandUseMO *commandUse =
        [iTermCommandHistoryCommandUseMO commandHistoryCommandUseInContext:_managedObjectContext];
    commandUse.time = theEntry.timeOfLastUse;
    commandUse.mark = mark;
    commandUse.directory = directory;
    commandUse.command = theEntry.command;
    [theEntry addUsesObject:commandUse];

    NSString *key = host.key ?: @"";
    if (_expandedCache[key]) {
        [_expandedCache[key] addObject:commandUse];
    }
    [self saveCommandHistory];
}

- (NSTimeInterval)now {
    return [NSDate timeIntervalSinceReferenceDate];
}

- (void)saveObjectGraph {
    NSError *error = nil;
    if (![_managedObjectContext save:&error]) {
        NSLog(@"Failed to save command history: %@", error);
    }
}

- (void)saveCommandHistory {
    [self saveObjectGraph];
    if (!_initializing) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kCommandHistoryDidChangeNotificationName
                                                            object:nil];
    }
}

- (void)saveDirectories {
    [self saveObjectGraph];
    if (!_initializing) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kDirectoriesDidChangeNotificationName
                                                            object:nil];
    }
}

- (void)setDirectory:(iTermRecentDirectoryMO *)directory starred:(BOOL)starred {
    directory.starred = @(starred);
    [self saveDirectories];
}

- (void)setStatusOfCommandAtMark:(VT100ScreenMark *)mark
                          onHost:(VT100RemoteHost *)remoteHost
                              to:(int)status {
    iTermCommandHistoryCommandUseMO *commandUse =
        [self commandUseWithMarkGuid:mark.guid onHost:remoteHost];
    // If the status is 0 and commandUse doesn't have a code set, do nothing. This saves some time
    // in the common case.
    if (commandUse && commandUse.code.intValue != status) {
        commandUse.code = @(status);
        [self saveCommandHistory];
    }
}

- (BOOL)haveCommandsForHost:(VT100RemoteHost *)host {
    return [[[self recordForHost:host] entries] count] > 0;
}

- (BOOL)haveDirectoriesForHost:(VT100RemoteHost *)host {
    return [[[self recordForHost:host] directories] count] > 0;
}


- (NSArray<iTermCommandHistoryCommandUseMO *> *)autocompleteSuggestionsWithPartialCommand:(NSString *)partialCommand
                                                                                   onHost:(VT100RemoteHost *)host {
    NSArray<iTermCommandHistoryEntryMO *> *temp =
        [self commandHistoryEntriesWithPrefix:partialCommand onHost:host];
    NSMutableArray<iTermCommandHistoryCommandUseMO *> *result = [NSMutableArray array];
    for (iTermCommandHistoryEntryMO *entry in temp) {
        iTermCommandHistoryCommandUseMO *lastUse = [entry.uses lastObject];
        if (lastUse) {
            [result addObject:lastUse];
        }
    }
    return result;
}

- (NSArray<iTermCommandHistoryEntryMO *> *)commandHistoryEntriesWithPrefix:(NSString *)partialCommand
                                                                    onHost:(VT100RemoteHost *)host {
    BOOL emptyPartialCommand = (partialCommand.length == 0);
    NSMutableArray<iTermCommandHistoryEntryMO *> *result = [NSMutableArray array];
    iTermHostRecordMO *hostRecord = [self recordForHost:host];
    for (iTermCommandHistoryEntryMO *entry in hostRecord.entries) {
        if (emptyPartialCommand || [entry.command hasPrefix:partialCommand]) {
            // The FinalTerm algorithm doesn't require |partialCommand| to be a prefix of the
            // history entry, but based on how our autocomplete works, it makes sense to only
            // accept prefixes. Their scoring algorithm is implemented in case this should change.
            entry.matchLocation = @0;
            [result addObject:entry];
        }
    }

    // TODO: Cache this.
    NSArray *sortedEntries = [result sortedArrayUsingSelector:@selector(compare:)];
    return [sortedEntries subarrayWithRange:NSMakeRange(0, MIN(kMaxResults, sortedEntries.count))];
}

- (NSMutableArray<iTermCommandHistoryCommandUseMO *> *)commandUsesByExpandingEntries:(NSArray<iTermCommandHistoryEntryMO *> *)array {
    NSMutableArray<iTermCommandHistoryCommandUseMO *> *result = [NSMutableArray array];
    for (iTermCommandHistoryEntryMO *entry in array) {
        for (iTermCommandHistoryCommandUseMO *commandUse in entry.uses) {
            if (!commandUse.command) {
                commandUse.command = entry.command;
            }
            [result addObject:commandUse];
        }
    }

    // Sort result chronologically from earliest to latest
    [result sortWithOptions:0 usingComparator:^NSComparisonResult(iTermCommandHistoryCommandUseMO *obj1,
                                                                  iTermCommandHistoryCommandUseMO *obj2) {
        return [(obj1.time ?: @0) compare:(obj2.time ?: @0)];
    }];
    return result;
}

- (NSArray<iTermCommandHistoryCommandUseMO *> *)commandUsesForHost:(VT100RemoteHost *)host {
    NSString *key = host.key ?: @"";
    if (!_expandedCache[key]) {
        [self loadExpandedCacheForHost:host];
    }
    return _expandedCache[key];
}

#pragma mark - Private

- (void)loadExpandedCacheForHost:(VT100RemoteHost *)host {
    NSString *key = host.key ?: @"";

    NSArray<iTermCommandHistoryEntryMO *> *temp =
        [self commandHistoryEntriesWithPrefix:@"" onHost:host];
    NSMutableArray<iTermCommandHistoryCommandUseMO *> *expanded =
        [self commandUsesByExpandingEntries:temp];

    _expandedCache[key] = expanded;

}

- (NSArray *)managedObjects {
    NSFetchRequest *fetchRequest =
        [NSFetchRequest fetchRequestWithEntityName:[iTermHostRecordMO entityName]];
    NSError *error = nil;
    return [_managedObjectContext executeFetchRequest:fetchRequest error:&error];
}

- (BOOL)removeOldData {
    NSFetchRequest *fetchRequest = [[[NSFetchRequest alloc] init] autorelease];
    [fetchRequest setEntity:[NSEntityDescription entityForName:[iTermCommandHistoryCommandUseMO entityName]
                                        inManagedObjectContext:_managedObjectContext]];
    NSPredicate *predicate =
        [NSPredicate predicateWithFormat:@"time < %f", [self now] - kMaxTimeToRememberCommands];
    [fetchRequest setPredicate:predicate];
    NSError *error = nil;
    NSArray<iTermCommandHistoryCommandUseMO *> *results =
        [_managedObjectContext executeFetchRequest:fetchRequest error:&error];
    for (iTermCommandHistoryCommandUseMO *commandUse in results) {
        iTermCommandHistoryEntryMO *entry = commandUse.entry;
        [entry removeUsesObject:commandUse];
        
        if (entry.uses.count == 0) {
            [_managedObjectContext deleteObject:entry];
        }
    }

    // Directories
    fetchRequest = [[[NSFetchRequest alloc] init] autorelease];
    [fetchRequest setEntity:[NSEntityDescription entityForName:[iTermRecentDirectoryMO entityName]
                                        inManagedObjectContext:_managedObjectContext]];
    predicate =
        [NSPredicate predicateWithFormat:@"lastUse < %f and starred == 0",
            [self now] - kMaxTimeToRememberDirectories];
    [fetchRequest setPredicate:predicate];
    error = nil;
    NSArray<iTermRecentDirectoryMO *> *directories =
        [_managedObjectContext executeFetchRequest:fetchRequest error:&error];
    for (iTermRecentDirectoryMO *directory in directories) {
        iTermHostRecordMO *hostRecord = directory.remoteHost;
        [hostRecord removeDirectoriesObject:directory];
    }

    error = nil;
    [_managedObjectContext save:&error];

    return results.count > 0 || directories.count > 0;
}

- (void)loadObjectGraph {
    NSArray *managedObjects = [self managedObjects];
    [_expandedCache removeAllObjects];
    for (iTermHostRecordMO *hostRecord in managedObjects) {
        _records[hostRecord.hostKey] = hostRecord;
        for (iTermRecentDirectoryMO *directory in hostRecord.directories) {
            [_tree addPath:directory.path];
        }
    }
}

// Returns YES if a migration was attempted.
- (BOOL)migrateFromPlistToCoreData {
    BOOL attempted = NO;
    if ([self migrateCommandHistoryFromPlistToCoreData]) {
        attempted = YES;
    }
    if ([self migrateDirectoriesFromPlistToCoreData]) {
        attempted = YES;
    }
    return attempted;
}

- (BOOL)migrateDirectoriesFromPlistToCoreData {
    NSString *path = [self pathToDeprecatedDirectoriesPlist];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:nil]) {
        return NO;
    }
    NSDictionary *archive = [NSKeyedUnarchiver unarchiveObjectWithFile:path];
    for (NSString *host in archive) {
        NSArray *parts = [host componentsSeparatedByString:@"@"];
        if (parts.count != 2) {
            continue;
        }
        iTermHostRecordMO *hostRecord = _records[host];
        if (!hostRecord) {
            hostRecord = [iTermHostRecordMO hostRecordInContext:_managedObjectContext];
        }
        hostRecord.username = parts[0];
        hostRecord.hostname = parts[1];
        for (NSDictionary *dict in archive[host]) {
            iTermRecentDirectoryMO *directory =
                [iTermRecentDirectoryMO entryWithDictionary:dict
                                                  inContext:_managedObjectContext];
            [hostRecord addDirectoriesObject:directory];
            directory.remoteHost = hostRecord;
        }
    }
    NSError *error = nil;
    if (![_managedObjectContext save:&error]) {
        NSLog(@"Failed to migrate directory history: %@", error);
    } else {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    }
    return YES;
}

- (BOOL)migrateCommandHistoryFromPlistToCoreData {
    NSString *path = [self pathToDeprecatedCommandHistoryPlist];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:nil]) {
        return NO;
    }
    NSDictionary *archive = [NSKeyedUnarchiver unarchiveObjectWithFile:self.pathToDeprecatedCommandHistoryPlist];
    for (NSString *host in archive) {
        NSArray *parts = [host componentsSeparatedByString:@"@"];
        if (parts.count != 2) {
            continue;
        }
        iTermHostRecordMO *hostRecord = _records[host];
        if (!hostRecord) {
            hostRecord = [iTermHostRecordMO hostRecordInContext:_managedObjectContext];
        }
        hostRecord.username = parts[0];
        hostRecord.hostname = parts[1];
        for (NSDictionary *commandDict in archive[host]) {
            iTermCommandHistoryEntryMO *managedObject =
                [iTermCommandHistoryEntryMO commandHistoryEntryFromDeprecatedDictionary:commandDict
                                                                              inContext:_managedObjectContext];
            managedObject.remoteHost = hostRecord;
            [hostRecord addEntriesObject:managedObject];
        }
    }
    NSError *error = nil;
    if (![_managedObjectContext save:&error]) {
        NSLog(@"Failed to migrate command history: %@", error);
    } else {
        [[NSFileManager defaultManager] removeItemAtPath:self.pathToDeprecatedCommandHistoryPlist error:NULL];
    }
    return YES;
}

- (void)vacuum {
    if (_savingToDisk) {
        // No sense vacuuming RAM.
        // We have to vacuum to erase history in journals.
        [_managedObjectContext release];
        _managedObjectContext = nil;
        [self initializeCoreDataWithRetry:YES vacuum:YES];
        [_managedObjectContext release];
        _managedObjectContext = nil;

        // Reinitialize so we can go on with life.
        [self initializeCoreDataWithRetry:YES vacuum:NO];
    }

    // Reload everything.
    [_records removeAllObjects];
    [_expandedCache removeAllObjects];
    [_tree release];
    _tree = [[iTermDirectoryTree alloc] init];
    [self loadObjectGraph];
}

- (void)eraseCommandHistory:(BOOL)commandHistory directories:(BOOL)directories {
    if (commandHistory) {
        [[NSFileManager defaultManager] removeItemAtPath:self.pathToDeprecatedCommandHistoryPlist
                                                   error:NULL];
    }
    if (directories) {
        [[NSFileManager defaultManager] removeItemAtPath:self.pathToDeprecatedDirectoriesPlist
                                                   error:NULL];
    }

    for (iTermHostRecordMO *hostRecord in _records.allValues) {
        if (commandHistory) {
            [hostRecord removeEntries:hostRecord.entries];
        }
        if (directories) {
            [hostRecord removeDirectories:hostRecord.directories];
        }
    }

    if (commandHistory) {
        [self saveCommandHistory];
    }
    if (directories) {
        [self saveDirectories];
    }

    [self vacuum];
    [[NSNotificationCenter defaultCenter] postNotificationName:kDirectoriesDidChangeNotificationName
                                                        object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:kCommandHistoryDidChangeNotificationName
                                                        object:nil];
}

- (void)eraseCommandHistoryForHost:(VT100RemoteHost *)host {
    NSString *key = host.key ?: @"";
    iTermHostRecordMO *hostRecord = [self recordForHost:host];
    if (hostRecord) {
        [hostRecord removeEntries:hostRecord.entries];
        [_expandedCache removeObjectForKey:key];
        [self saveCommandHistory];
    }
}

- (void)eraseDirectoriesForHost:(VT100RemoteHost *)host {
    iTermHostRecordMO *hostRecord = [self recordForHost:host];
    if (hostRecord) {
        [hostRecord removeDirectories:hostRecord.directories];
        [self saveDirectories];
    }
}

- (NSIndexSet *)abbreviationSafeIndexesInRecentDirectory:(iTermRecentDirectoryMO *)entry {
    return [_tree abbreviationSafeIndexesInPath:entry.path];
}

- (NSArray<iTermRecentDirectoryMO *> *)directoriesForHost:(VT100RemoteHost *)host {
    NSMutableArray<iTermRecentDirectoryMO *> *results = [NSMutableArray array];
    NSMutableArray<iTermRecentDirectoryMO *> *starred = [NSMutableArray array];
    for (iTermRecentDirectoryMO *directory in [[self recordForHost:host] directories]) {
        if (directory.starred.boolValue) {
            [starred addObject:directory];
        } else {
            [results addObject:directory];
        }
    }
    return [starred arrayByAddingObjectsFromArray:results];
}

- (iTermCommandHistoryCommandUseMO *)commandUseWithMarkGuid:(NSString *)markGuid
                                                     onHost:(VT100RemoteHost *)host {
    if (!markGuid) {
        return nil;
    }
    iTermHostRecordMO *hostRecord = [self recordForHost:host];
    // TODO: Create an index of markGuid's in command uses if this becomes a performance problem during restore.
    for (iTermCommandHistoryEntryMO *entry in hostRecord.entries) {
        for (iTermCommandHistoryCommandUseMO *use in entry.uses) {
            if ([use.markGuid isEqual:markGuid]) {
                return use;
            }
        }
    }
    return nil;
}

- (iTermHostRecordMO *)recordForHost:(VT100RemoteHost *)host {
    return _records[host.key ?: @""];
}

- (void)setRecord:(iTermHostRecordMO *)record forHost:(VT100RemoteHost *)host {
    _records[host.key ?: @""] = record;
}

@end
