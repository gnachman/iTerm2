//
//  CommandHistory.m
//  iTerm
//
//  Created by George Nachman on 1/6/14.
//
//

#import "iTermCommandHistoryController.h"

#import "iTermCommandHistoryEntryMO+Additions.h"
#import "iTermPreferences.h"
#import "NSArray+iTerm.h"
#import "NSManagedObjects/iTermCommandHistoryEntryMO.h"
#import "NSManagedObjects/iTermCommandHistoryMO.h"
#import "PreferencePanel.h"
#import "VT100RemoteHost.h"
#import "VT100ScreenMark.h"

NSString *const kCommandHistoryDidChangeNotificationName = @"kCommandHistoryDidChangeNotificationName";
NSString *const kCommandHistoryHasEverBeenUsed = @"kCommandHistoryHasEverBeenUsed";

static const int kMaxResults = 200;

static const NSTimeInterval kMaxTimeToRememberCommands = 60 * 60 * 24 * 90;

@interface iTermCommandHistoryMO (iTerm)
+ (instancetype)commandHistoryInContext:(NSManagedObjectContext *)context;
+ (NSString *)entityName;
- (NSString *)hostKey;
@end

@implementation iTermCommandHistoryMO (iTerm)

+ (instancetype)commandHistoryInContext:(NSManagedObjectContext *)context {
    return [NSEntityDescription insertNewObjectForEntityForName:self.entityName
                                         inManagedObjectContext:context];
}

+ (NSString *)entityName {
    return @"CommandHistory";
}

- (NSString *)hostKey {
    return [NSString stringWithFormat:@"%@@%@", self.username, self.hostname];
}

@end

@interface VT100RemoteHost (CommandHistory)

- (NSString *)key;

@end

@implementation VT100RemoteHost (CommandHistory)

- (NSString *)key {
    return [NSString stringWithFormat:@"%@@%@", self.username, self.hostname];
}

@end
@implementation iTermCommandHistoryController {
    NSMutableDictionary<NSString *, iTermCommandHistoryMO *> *_historyByHost;
    
    // Keys are remote host keys, "user@hostname".
    NSMutableDictionary<NSString *, NSArray<iTermCommandHistoryCommandUseMO *> *> *_expandedCache;
    NSManagedObjectContext *_managedObjectContext;
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
        [self initializeCoreData];
        _historyByHost = [[NSMutableDictionary alloc] init];
        _expandedCache = [[NSMutableDictionary alloc] init];

        [self loadCommandHistory];
    }
    return self;
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
    return path;
}

- (NSString *)pathToDeprecatedPlist {
    return [self pathForFileNamed:@"commandhistory.plist"];
}

- (NSString *)pathToDatabase {
    return [self pathForFileNamed:@"CommandHistory.sqlite"];
}

- (void)dealloc {
    [_historyByHost release];
    [_expandedCache release];
    [_managedObjectContext release];
    [super dealloc];
}

- (void)initializeCoreData {
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
    if ([iTermPreferences boolForKey:kPreferenceKeySavePasteAndCommandHistory]) {
        storeType = NSSQLiteStoreType;
    } else {
        storeType = NSInMemoryStoreType;
    }
    // TODO: Handle migrating store types when the preference changes.
    NSPersistentStore *store = [persistentStoreCoordinator addPersistentStoreWithType:storeType
                                                                        configuration:nil
                                                                                  URL:storeURL
                                                                              options:0
                                                                                error:&error];
    assert(store);
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
    return (_historyByHost.count > 0 ||
            [[NSUserDefaults standardUserDefaults] boolForKey:kCommandHistoryHasEverBeenUsed]);
}

- (void)addCommand:(NSString *)command
            onHost:(VT100RemoteHost *)host
       inDirectory:(NSString *)directory
          withMark:(VT100ScreenMark *)mark {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kCommandHistoryHasEverBeenUsed];
    
    iTermCommandHistoryMO *commandHistory = _historyByHost[host.key ?: @""];
    if (!commandHistory) {
        commandHistory = [iTermCommandHistoryMO commandHistoryInContext:_managedObjectContext];
        commandHistory.hostname = host.hostname;
        commandHistory.username = host.username;
    }

    iTermCommandHistoryEntryMO *theEntry = nil;
    for (iTermCommandHistoryEntryMO *entry in commandHistory.entries) {
        if ([entry.command isEqualToString:command]) {
            theEntry = entry;
            break;
        }
    }

    if (!theEntry) {
        theEntry = [iTermCommandHistoryEntryMO commandHistoryEntryInContext:_managedObjectContext];
        theEntry.command = command;
        [commandHistory addEntriesObject:theEntry];
    }
    
    theEntry.numberOfUses = @(theEntry.numberOfUses.integerValue + 1);
    theEntry.timeOfLastUse = @([NSDate timeIntervalSinceReferenceDate]);
    
    iTermCommandHistoryCommandUseMO *commandUse =
        [iTermCommandHistoryCommandUseMO commandHistoryCommandUseInContext:_managedObjectContext];
    commandUse.time = theEntry.timeOfLastUse;
    commandUse.mark = mark;
    commandUse.directory = directory;
    commandUse.command = theEntry.command;
    [theEntry addUsesObject:commandUse];

    [self save];
}

- (void)save {
    NSError *error = nil;
    if (![_managedObjectContext save:&error]) {
        NSLog(@"Failed to save command history: %@", error);
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:kCommandHistoryDidChangeNotificationName
                                                        object:nil];
}

- (void)setStatusOfCommandAtMark:(VT100ScreenMark *)mark
                          onHost:(VT100RemoteHost *)remoteHost
                              to:(int)status {
    iTermCommandHistoryCommandUseMO *commandUse =
        [[iTermCommandHistoryController sharedInstance] commandUseWithMarkGuid:mark.guid
                                                         onHost:remoteHost];
    // If the status is 0 and commandUse doesn't have a code set, do nothing. This saves some time
    // in the common case.
    if (commandUse && commandUse.code.intValue != status) {
        commandUse.code = @(status);
        [self save];
    }
}

- (BOOL)haveCommandsForHost:(VT100RemoteHost *)host {
    return [[_historyByHost[host.key ?: @""] entries] count] > 0;
}

- (NSArray<iTermCommandHistoryCommandUseMO *> *)autocompleteSuggestionsWithPartialCommand:(NSString *)partialCommand
                                                                                   onHost:(VT100RemoteHost *)host {
    NSArray<iTermCommandHistoryEntryMO *> *temp =
        [self commandHistoryEntriesWithPrefix:partialCommand onHost:host];
    NSMutableArray *result = [NSMutableArray array];
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
    iTermCommandHistoryMO *commandHistory = _historyByHost[host.key ?: @""];
    for (iTermCommandHistoryEntryMO *entry in commandHistory.entries) {
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
        [[iTermCommandHistoryController sharedInstance] commandHistoryEntriesWithPrefix:@""
                                                                                 onHost:host];
    NSMutableArray<iTermCommandHistoryCommandUseMO *> *expanded =
        [[iTermCommandHistoryController sharedInstance] commandUsesByExpandingEntries:temp];

    _expandedCache[key] = expanded;

}

- (NSArray *)managedObjects {
    NSFetchRequest *fetchRequest =
        [NSFetchRequest fetchRequestWithEntityName:[iTermCommandHistoryMO entityName]];
    NSError *error = nil;
    return [_managedObjectContext executeFetchRequest:fetchRequest error:&error];
}

- (void)removeOldData {
    NSFetchRequest *fetchRequest = [[[NSFetchRequest alloc] init] autorelease];
    [fetchRequest setEntity:[NSEntityDescription entityForName:[iTermCommandHistoryCommandUseMO entityName]
                                        inManagedObjectContext:_managedObjectContext]];
    NSPredicate *predicate =
        [NSPredicate predicateWithFormat:@"time < %f",
            [NSDate timeIntervalSinceReferenceDate] - kMaxTimeToRememberCommands];
    [fetchRequest setPredicate:predicate];
    NSError *error = nil;
    NSArray<iTermCommandHistoryCommandUseMO *> *results =
        [_managedObjectContext executeFetchRequest:fetchRequest error:&error];
    for (iTermCommandHistoryCommandUseMO *commandUse in results) {
        iTermCommandHistoryEntryMO *entry = commandUse.entry;
        [_managedObjectContext deleteObject:commandUse];
        
        if (entry.uses.count == 0) {
            [_managedObjectContext deleteObject:entry];
        }
    }
    [self save];
}

- (void)loadCommandHistory {
    [self removeOldData];
    NSArray *managedObjects = [self managedObjects];
    if (!managedObjects.count) {
        [self migrateFromPlistToCoreData];
        managedObjects = [self managedObjects];
    }
    for (iTermCommandHistoryMO *history in managedObjects) {
        _historyByHost[history.hostKey] = history;
    }
}

// Returns YES if a migration was attempted.
- (BOOL)migrateFromPlistToCoreData {
    NSString *path = [self pathToDeprecatedPlist];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:nil]) {
        return NO;
    }
    NSDictionary *archive = [NSKeyedUnarchiver unarchiveObjectWithFile:self.pathToDeprecatedPlist];
    for (NSString *host in archive) {
        NSArray *parts = [host componentsSeparatedByString:@"@"];
        if (parts.count != 2) {
            continue;
        }
        iTermCommandHistoryMO *remoteHost =
            [iTermCommandHistoryMO commandHistoryInContext:_managedObjectContext];
        remoteHost.username = parts[0];
        remoteHost.hostname = parts[1];
        for (NSDictionary *commandDict in archive[host]) {
            iTermCommandHistoryEntryMO *managedObject =
                [iTermCommandHistoryEntryMO commandHistoryEntryFromDeprecatedDictionary:commandDict
                                                                              inContext:_managedObjectContext];
            managedObject.remoteHost = remoteHost;
            [remoteHost addEntriesObject:managedObject];
        }
    }
    NSError *error = nil;
    if (![_managedObjectContext save:&error]) {
        NSLog(@"Failed to migrate command history: %@", error);
    } else {
        [[NSFileManager defaultManager] removeItemAtPath:self.pathToDeprecatedPlist error:NULL];
    }
    return YES;
}

- (void)eraseHistory {
    [_historyByHost removeAllObjects];
    [[NSFileManager defaultManager] removeItemAtPath:self.pathToDeprecatedPlist error:NULL];

    NSFetchRequest *fetchRequest = [[[NSFetchRequest alloc] init] autorelease];
        [fetchRequest setEntity:[NSEntityDescription entityForName:[iTermCommandHistoryMO entityName]
                                            inManagedObjectContext:_managedObjectContext]];
    NSError *error = nil;
    NSArray<iTermCommandHistoryMO *> *results =
        [_managedObjectContext executeFetchRequest:fetchRequest error:&error];
    for (iTermCommandHistoryMO *history in results) {
        [_managedObjectContext deleteObject:history];
    }
    [self save];
    // TODO: Make sure entries and uses get removed too
}

- (void)eraseHistoryForHost:(VT100RemoteHost *)host {
    NSString *key = host.key ?: @"";
    iTermCommandHistoryMO *managedObject = _historyByHost[key];
    if (managedObject) {
        [_managedObjectContext deleteObject:managedObject];
        [_historyByHost removeObjectForKey:key];
        [self save];
    }
}

- (iTermCommandHistoryCommandUseMO *)commandUseWithMarkGuid:(NSString *)markGuid
                                                     onHost:(VT100RemoteHost *)host {
    if (!markGuid) {
        return nil;
    }
    iTermCommandHistoryMO *history = _historyByHost[host.key ?: @""];
    // TODO: Create an index of markGuid's in command uses if this becomes a performance problem during restore.
    for (iTermCommandHistoryEntryMO *entry in history.entries) {
        for (iTermCommandHistoryCommandUseMO *use in entry.uses) {
            if ([use.markGuid isEqual:markGuid]) {
                return use;
            }
        }
    }
    return nil;
}

@end
