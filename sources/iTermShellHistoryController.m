//
//  CommandHistory.m
//  iTerm
//
//  Created by George Nachman on 1/6/14.
//
//

#import "iTermShellHistoryController.h"

#import "DebugLogging.h"
#import "iTermCommandHistoryEntryMO+Additions.h"
#import "iTermDirectoryTree.h"
#import "iTermHostRecordMO.h"
#import "iTermHostRecordMO+Additions.h"
#import "iTermPreferences.h"
#import "iTermRecentDirectoryMO.h"
#import "iTermRecentDirectoryMO+Additions.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSStringITerm.h"
#import "iTermCommandHistoryEntryMO.h"
#import "PreferencePanel.h"
#import "VT100RemoteHost.h"
#import "VT100ScreenMark.h"
#include <sys/stat.h>

NSString *const kCommandHistoryDidChangeNotificationName = @"kCommandHistoryDidChangeNotificationName";
NSString *const kDirectoriesDidChangeNotificationName = @"kDirectoriesDidChangeNotificationName";
NSString *const kCommandHistoryHasEverBeenUsed = @"NoSyncCommandHistoryHasEverBeenUsed";

static const int kMaxResults = 200;

static const NSTimeInterval kMaxTimeToRememberCommands = 60 * 60 * 24 * 90;
static const NSTimeInterval kMaxTimeToRememberDirectories = 60 * 60 * 24 * 90;

@interface VT100RemoteHost (CommandHistory)

- (NSString *)key;

@end

static NSString *iTermShellIntegrationRemoteHostKey(id<VT100RemoteHostReading> self) {
    return [NSString stringWithFormat:@"%@@%@", self.username, self.hostname];
}

@implementation iTermShellHistoryController {
    NSMutableDictionary<NSString *, iTermHostRecordMO *> *_records;

    // Keys are remote host keys, "user@hostname".
    NSMutableDictionary<NSString *, NSMutableArray<iTermCommandHistoryCommandUseMO *> *> *_expandedCache;
    NSManagedObjectContext *_managedObjectContext;
    iTermDirectoryTree *_tree;

    // Prevents notifications from being posted during initialization since that causes deadlock in
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

    [self removeOldData];
    [self loadObjectGraph];

    _initializing = NO;
    return YES;
}

- (void)dealloc {
    [_records release];
    [_expandedCache release];
    [_managedObjectContext release];
    [_tree release];
    [super dealloc];
}

#pragma mark - Filesystem

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
    if (name) {
        return [path stringByAppendingPathComponent:name];
    } else {
        return path;
    }
}

- (NSString *)pathToDeprecatedCommandHistoryPlist {
    return [self pathForFileNamed:@"commandhistory.plist"];
}

- (NSString *)pathToDeprecatedDirectoriesPlist {
    return [self pathForFileNamed:@"directories.plist"];
}

- (NSString *)databaseFilenamePrefix {
    return @"ShellHistory.sqlite";
}

- (NSString *)pathToDatabase {
    NSString *path = [self pathForFileNamed:self.databaseFilenamePrefix];
    if (!self.shouldSaveToDisk) {
        // For migration to work the in-memory path must be different than the on-disk path.
        path = [path stringByAppendingString:@".ram"];
    }
    return path;
}

#pragma mark - Core Data

// Note: setting vacuum to YES forces it to use the on-disk sqlite database. This allows you to
// vacuum a database after changing the setting to in-memory. It doesn't make sense to vacuum RAM,
// after all.
- (BOOL)initializeCoreDataWithRetry:(BOOL)retry vacuum:(BOOL)vacuum {
    NSURL *modelURL = [[NSBundle bundleForClass:self.class] URLForResource:@"Model" withExtension:@"momd"];
    assert(modelURL);

    NSManagedObjectModel *managedObjectModel =
        [[[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL] autorelease];
    if (!managedObjectModel) {
        XLog(@"Failed to initialize managed object model for URL %@", modelURL);
        return NO;
    }

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
    if ([self shouldSaveToDisk] || vacuum) {
        _savingToDisk = YES;
        storeType = NSSQLiteStoreType;
    } else {
        _savingToDisk = NO;
        storeType = NSInMemoryStoreType;
    }

    NSDictionary *options = @{ NSInferMappingModelAutomaticallyOption: @YES,
                               NSMigratePersistentStoresAutomaticallyOption: @YES };
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
        if (![self shouldSaveToDisk]) {
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

    if (self.shouldSaveToDisk) {
        [self makeDatabaseReadableOnlyByUser];
    }
    return YES;
}

- (void)makeDatabaseReadableOnlyByUser {
    NSString *basePath = [self pathForFileNamed:nil];
    NSDirectoryEnumerator<NSURL *> *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:[NSURL fileURLWithPath:basePath]
                                                                      includingPropertiesForKeys:nil
                                                                                         options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
                                                                                    errorHandler:nil];
    for (NSURL *fileURL in enumerator) {
        NSString *filename = fileURL.path;
        if (![filename hasPrefix:self.databaseFilenamePrefix]) {
            DLog(@"Skip setting permissions on file %@ that isn't part of the shell history db", filename);
            continue;
        }
        NSString *fullPath = [basePath stringByAppendingPathComponent:filename];
        NSError *error = nil;
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:fullPath error:&error];
        if (error) {
            XLog(@"Failed to get attributes of %@: %@", fullPath, error);
            continue;
        }

        NSNumber *permissionsNumber = attributes[NSFilePosixPermissions];
        if (!permissionsNumber) {
            XLog(@"Couldn't get permissions of file %@. Attributes are: %@", fullPath, attributes);
            continue;
        }

        short posixPermissions = [permissionsNumber shortValue];
        short fixedPosixPermissions = (posixPermissions & 0700);  // Remove other and group permissions.
        if (fixedPosixPermissions != posixPermissions) {
            NSDictionary *updatedAttributes = [attributes dictionaryBySettingObject:@(fixedPosixPermissions)
                                                                             forKey:NSFilePosixPermissions];
            error = nil;
            [[NSFileManager defaultManager] setAttributes:updatedAttributes ofItemAtPath:fullPath error:&error];
            if (error) {
                XLog(@"Failed to set attributes of %@ to %@: %@", fullPath, updatedAttributes, error);
            }
        }
    }
}

- (BOOL)deleteDatabase {
    NSString *path = [[self pathToDatabase] stringByDeletingLastPathComponent];
    NSDirectoryEnumerator<NSString *> *enumerator =
        [[NSFileManager defaultManager] enumeratorAtPath:path];
    [enumerator skipDescendants];
    BOOL foundAny = NO;
    BOOL anyErrors = NO;
    for (NSString *filename in enumerator) {
        [enumerator skipDescendants];
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

- (void)deleteObjectsWithEntityName:(NSString *)entityName {
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:entityName];
    NSArray *objects = [_managedObjectContext executeFetchRequest:fetchRequest error:nil];
    for (NSManagedObject *object in objects) {
        [_managedObjectContext deleteObject:object];
    }
}

- (void)saveObjectGraph {
    NSError *error = nil;
    @try {
        if (![_managedObjectContext save:&error]) {
            NSLog(@"Failed to save command history: %@", error);
        }
    }
    @catch (NSException *exception) {
        NSLog(@"Exception while saving managed object context: %@", exception);
    }
}

- (BOOL)shouldSaveToDisk {
    return [iTermPreferences boolForKey:kPreferenceKeySavePasteAndCommandHistory];
}

- (NSArray *)managedObjects {
    NSFetchRequest *fetchRequest =
        [NSFetchRequest fetchRequestWithEntityName:[iTermHostRecordMO entityName]];
    NSError *error = nil;
    return [_managedObjectContext executeFetchRequest:fetchRequest error:&error];
}

- (void)vacuum {
    if (_savingToDisk) {
        // No sense vacuuming RAM.
        // We have to vacuum to erase history in journals.
        [_managedObjectContext release];
        _managedObjectContext = nil;
        [self initializeCoreDataWithRetry:YES vacuum:YES];

        // Reinitialize so we can go on with life.
        [_managedObjectContext release];
        _managedObjectContext = nil;
        [self initializeCoreDataWithRetry:YES vacuum:NO];
    }

    // Reload everything.
    [_records removeAllObjects];
    [_expandedCache removeAllObjects];
    [_tree release];
    _tree = [[iTermDirectoryTree alloc] init];
    [self loadObjectGraph];
}

#pragma mark - APIs

+ (void)showInformationalMessage {
    NSResponder *firstResponder = [[NSApp keyWindow] firstResponder];
    SEL selector = @selector(installShellIntegration:);
    if (![firstResponder respondsToSelector:selector]) {
        firstResponder = nil;
    }
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = @"About Shell Integration";
    alert.informativeText =
        @"To use shell integration features such as "
        @"Command History, "
        @"Recent Directories, "
        @"Select Output of Last Command, "
        @"and Automatic Profile Switching, "
        @"your shell must be properly configured.";
    [alert addButtonWithTitle:@"Learn More…"];
    [alert addButtonWithTitle:@"OK"];
    if (firstResponder) {
        [alert addButtonWithTitle:@"Install Now"];
    }
    switch ([alert runModal]) {
        case NSAlertFirstButtonReturn:
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://iterm2.com/shell_integration.html"]];
            break;

        case NSAlertThirdButtonReturn:  // Install now, optional button
            [firstResponder performSelector:selector withObject:self];
            break;
    }
}

- (void)backingStoreTypeDidChange {
    NSPersistentStore *store =
        _managedObjectContext.persistentStoreCoordinator.persistentStores.firstObject;
    NSString *storeType = self.shouldSaveToDisk ? NSSQLiteStoreType : NSInMemoryStoreType;
    if ([store.type isEqualToString:storeType]) {
        // No change
        return;
    }

    // Change the store to the new type
    NSError *error = nil;
    [_managedObjectContext.persistentStoreCoordinator migratePersistentStore:store
                                                                       toURL:[NSURL fileURLWithPath:[self pathToDatabase]]
                                                                     options:@{}
                                                                    withType:storeType
                                                                       error:&error];
    if (error) {
        NSLog(@"Failed to migrate to on-disk storage: %@", error);
        // Do it the hard way.
        [_managedObjectContext release];
        _managedObjectContext = nil;
        [self initializeCoreDataWithRetry:YES vacuum:NO];
    }

    if (self.shouldSaveToDisk) {
        // Fix file permissions.
        [self makeDatabaseReadableOnlyByUser];
    } else {
        // Erase files containing user data.
        [self deleteDatabase];
    }
}

- (void)eraseCommandHistory:(BOOL)commandHistory directories:(BOOL)directories {
    // This operates at a low level to ensure data is really removed.
    if (commandHistory) {
        [[NSFileManager defaultManager] removeItemAtPath:self.pathToDeprecatedCommandHistoryPlist
                                                   error:NULL];
    }
    if (directories) {
        [[NSFileManager defaultManager] removeItemAtPath:self.pathToDeprecatedDirectoriesPlist
                                                   error:NULL];
    }

    if (commandHistory) {
        [self deleteObjectsWithEntityName:[iTermCommandHistoryEntryMO entityName]];
        [self deleteObjectsWithEntityName:[iTermCommandHistoryCommandUseMO entityName]];
    }
    if (directories) {
        [self deleteObjectsWithEntityName:[iTermRecentDirectoryMO entityName]];
    }
    if (commandHistory && directories) {
        [self deleteObjectsWithEntityName:[iTermHostRecordMO entityName]];
    }

    [self saveObjectGraph];
    [self vacuum];

    [[NSNotificationCenter defaultCenter] postNotificationName:kDirectoriesDidChangeNotificationName
                                                        object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:kCommandHistoryDidChangeNotificationName
                                                        object:nil];
}

#pragma mark - Command History

#pragma mark Mutation

- (void)addCommand:(NSString *)command
            onHost:(id<VT100RemoteHostReading>)host
       inDirectory:(NSString *)directory
          withMark:(id<VT100ScreenMarkReading>)mark {
    DLog(@"addCommand:%@ onHost:%@ inDirectory:%@ withMark:%@", command, host, directory, mark);
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
            DLog(@"Add to existing entry");
            theEntry = entry;
            break;
        }
    }

    if (!theEntry) {
        DLog(@"Create new entry");
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

    NSString *key = iTermShellIntegrationRemoteHostKey(host) ?: @"";
    if (_expandedCache[key]) {
        [_expandedCache[key] addObject:commandUse];
    }
    [self saveCommandHistory];
}

- (void)setStatusOfCommandAtMark:(id<VT100ScreenMarkReading>)mark
                          onHost:(id<VT100RemoteHostReading>)remoteHost
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

#pragma mark Lookup

- (BOOL)commandHistoryHasEverBeenUsed {
    return (_records.count > 0 ||
            [[NSUserDefaults standardUserDefaults] boolForKey:kCommandHistoryHasEverBeenUsed]);
}

- (NSArray<iTermCommandHistoryEntryMO *> *)commandHistoryEntriesWithPrefix:(NSString *)partialCommand
                                                                    onHost:(id<VT100RemoteHostReading>)host {
    if (host == nil) {
        return [self commandHistoryEntriesWithPrefix:partialCommand onHost:[VT100RemoteHost localhost]];
    }
    BOOL emptyPartialCommand = (partialCommand.length == 0);
    NSMutableArray<iTermCommandHistoryEntryMO *> *result = [NSMutableArray array];
    iTermHostRecordMO *hostRecord = [self recordForHost:host];
    for (iTermCommandHistoryEntryMO *entry in hostRecord.entries) {
        if (emptyPartialCommand || [entry.command caseInsensitiveHasPrefix:partialCommand]) {
            DLog(@"Add candidate %@", entry.command);
            // The FinalTerm algorithm doesn't require |partialCommand| to be a prefix of the
            // history entry, but based on how our autocomplete works, it makes sense to only
            // accept prefixes. Their scoring algorithm is implemented in case this should change.
            entry.matchLocation = @0;
            [result addObject:entry];
        } else {
            DLog(@"Skip candidate %@", entry.command);
        }
    }

    NSArray *sortedEntries;
    if (partialCommand.length == 0) {
        sortedEntries = [result sortedArrayUsingSelector:@selector(compareUseTime:)];
    } else {
        sortedEntries = [result sortedArrayUsingSelector:@selector(compare:)];
    }
    return [sortedEntries subarrayWithRange:NSMakeRange(0, MIN(kMaxResults, sortedEntries.count))];
}

- (NSArray<iTermCommandHistoryCommandUseMO *> *)autocompleteSuggestionsWithPartialCommand:(NSString *)partialCommand
                                                                                   onHost:(id<VT100RemoteHostReading>)host {
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

- (BOOL)haveCommandsForHost:(id<VT100RemoteHostReading>)host {
    return [[[self recordForHost:host] entries] count] > 0;
}

- (iTermCommandHistoryCommandUseMO *)commandUseWithMarkGuid:(NSString *)markGuid
                                                     onHost:(id<VT100RemoteHostReading>)host {
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

- (NSArray<iTermCommandHistoryCommandUseMO *> *)commandUsesForHost:(id<VT100RemoteHostReading>)host {
    NSString *key = iTermShellIntegrationRemoteHostKey(host) ?: @"";
    if (!_expandedCache[key]) {
        [self loadExpandedCacheForHost:host];
    }
    return _expandedCache[key];
}

#pragma mark - Recent Directories

#pragma mark Mutation

- (iTermRecentDirectoryMO *)recordUseOfPath:(NSString *)path
                                     onHost:(id<VT100RemoteHostReading>)host
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

- (void)setDirectory:(iTermRecentDirectoryMO *)directory starred:(BOOL)starred {
    directory.starred = @(starred);
    [self saveDirectories];
}

#pragma mark Lookup

- (NSIndexSet *)abbreviationSafeIndexesInRecentDirectory:(iTermRecentDirectoryMO *)entry {
    return [_tree abbreviationSafeIndexesInPath:entry.path];
}

- (NSArray *)directoriesSortedByScoreOnHost:(id<VT100RemoteHostReading>)host {
    return [[self directoriesForHost:host] sortedArrayUsingSelector:@selector(compare:)];
}

- (BOOL)haveDirectoriesForHost:(id<VT100RemoteHostReading>)host {
    return [[[self recordForHost:host] directories] count] > 0;
}

#pragma mark - Testing

- (void)eraseCommandHistoryForHost:(id<VT100RemoteHostReading>)host {
    NSString *key = iTermShellIntegrationRemoteHostKey(host) ?: @"";
    iTermHostRecordMO *hostRecord = [self recordForHost:host];
    if (hostRecord) {
        [hostRecord removeEntries:hostRecord.entries];
        [_expandedCache removeObjectForKey:key];
        [self saveCommandHistory];
    }
}

- (void)eraseDirectoriesForHost:(id<VT100RemoteHostReading>)host {
    iTermHostRecordMO *hostRecord = [self recordForHost:host];
    if (hostRecord) {
        [hostRecord removeDirectories:hostRecord.directories];
        [self saveDirectories];
    }
}

- (NSTimeInterval)now {
    return [NSDate timeIntervalSinceReferenceDate];
}

#pragma mark - Private

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

        if (entry && entry.uses.count == 0) {
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
        [_managedObjectContext deleteObject:directory];
    }

    // Only save the most recent 1000 directories
    static const NSInteger iTermMaxDirectoriesToSave = 1000;

    NSSortDescriptor *lastUseDescriptor = [[[NSSortDescriptor alloc] initWithKey:@"lastUse"
                                                                       ascending:NO
                                                                        selector:@selector(compare:)] autorelease];
    fetchRequest = [[[NSFetchRequest alloc] init] autorelease];
    [fetchRequest setEntity:[NSEntityDescription entityForName:[iTermRecentDirectoryMO entityName]
                                        inManagedObjectContext:_managedObjectContext]];
    [fetchRequest setSortDescriptors:@[ lastUseDescriptor ]];
    predicate = [NSPredicate predicateWithFormat:@"starred == 0"];
    [fetchRequest setPredicate:predicate];
    error = nil;
    directories = [_managedObjectContext executeFetchRequest:fetchRequest error:&error];
    if (directories.count > iTermMaxDirectoriesToSave) {
        for (iTermRecentDirectoryMO *directory in [directories subarrayFromIndex:iTermMaxDirectoriesToSave]) {
            iTermHostRecordMO *hostRecord = directory.remoteHost;
            [hostRecord removeDirectoriesObject:directory];
            [_managedObjectContext deleteObject:directory];
        }
    }

    error = nil;
    [_managedObjectContext save:&error];

    return results.count > 0 || directories.count > 0;
}

- (void)loadObjectGraphIntoDictionary:(NSMutableDictionary *)records {
    NSArray *managedObjects = [self managedObjects];
    for (iTermHostRecordMO *hostRecord in managedObjects) {
        records[hostRecord.hostKey] = hostRecord;
    }
}

- (void)loadObjectGraph {
    [self loadObjectGraphIntoDictionary:_records];
    [_expandedCache removeAllObjects];
    for (NSString *hostKey in _records) {
        iTermHostRecordMO *hostRecord = _records[hostKey];
        for (iTermRecentDirectoryMO *directory in hostRecord.directories) {
            [_tree addPath:directory.path];
        }
    }
}

- (iTermHostRecordMO *)recordForHost:(id<VT100RemoteHostReading>)host {
    return _records[iTermShellIntegrationRemoteHostKey(host) ?: @""];
}

- (void)setRecord:(iTermHostRecordMO *)record forHost:(id<VT100RemoteHostReading>)host {
    _records[iTermShellIntegrationRemoteHostKey(host) ?: @""] = record;
}

#pragma mark Private Command History

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

- (void)loadExpandedCacheForHost:(id<VT100RemoteHostReading>)host {
    NSString *key = iTermShellIntegrationRemoteHostKey(host) ?: @"";

    NSArray<iTermCommandHistoryEntryMO *> *temp =
        [self commandHistoryEntriesWithPrefix:@"" onHost:host];
    NSMutableArray<iTermCommandHistoryCommandUseMO *> *expanded =
        [self commandUsesByExpandingEntries:temp];

    _expandedCache[key] = expanded;

}

- (void)saveCommandHistory {
    [self saveObjectGraph];
    if (!_initializing) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kCommandHistoryDidChangeNotificationName
                                                            object:nil];
    }
}

#pragma mark Private Directories

- (NSArray<iTermRecentDirectoryMO *> *)directoriesForHost:(id<VT100RemoteHostReading>)host {
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

- (void)saveDirectories {
    [self saveObjectGraph];
    if (!_initializing) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kDirectoriesDidChangeNotificationName
                                                            object:nil];
    }
}

@end
