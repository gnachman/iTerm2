//
//  CommandHistory.m
//  iTerm
//
//  Created by George Nachman on 1/6/14.
//
//

#import "CommandHistory.h"
#import "PreferencePanel.h"
#import "VT100RemoteHost.h"

NSString *const kCommandHistoryDidChangeNotificationName = @"kCommandHistoryDidChangeNotificationName";

static const int kMaxResults = 200;

// Keys for serializing an entry
static NSString *const kCommand = @"command";
static NSString *const kDirectory = @"directory";
static NSString *const kUses = @"uses";
static NSString *const kLastUsed = @"last used";
static NSString *const kUseTimes = @"use times";

// Top level serialization keys
static NSString *const kHostname = @"hostname";
static NSString *const kCommands = @"commands";

static const NSTimeInterval kMaxTimeToRememberCommands = 60 * 60 * 24 * 90;
static const int kMaxCommandsToSavePerHost = 200;

@interface CommandUse : NSObject <NSCopying>
@property(nonatomic, assign) NSTimeInterval time;
@property(nonatomic, retain) VT100ScreenMark *mark;
@property(nonatomic, retain) NSString *directory;

+ (instancetype)commandUseFromSerializedValue:(NSArray *)serializedValue;
- (NSArray *)serializedValue;

@end

@implementation CommandUse

- (void)dealloc {
    [_mark release];
    [_directory release];
    [super dealloc];
}

- (NSArray *)serializedValue {
    return @[ @(self.time), _directory ?: @"" ];
}

- (id)copyWithZone:(NSZone *)zone {
    return [[[self class] commandUseFromSerializedValue:[self serializedValue]] retain];
}

+ (instancetype)commandUseFromSerializedValue:(id)serializedValue {
    CommandUse *commandUse = [[[CommandUse alloc] init] autorelease];
    if ([serializedValue isKindOfClass:[NSArray class]]) {
        commandUse.time = [serializedValue[0] doubleValue];
        if ([serializedValue count] > 1) {
            commandUse.directory = serializedValue[1];
        }
    } else if ([serializedValue isKindOfClass:[NSNumber class]]) {
        commandUse.time = [serializedValue doubleValue];
    }
    return commandUse;
}

@end

@interface CommandHistory ()
@property(nonatomic, retain) NSMutableDictionary *hosts;
@end

@interface CommandHistoryEntry () <NSCopying>

// First character matched by current search.
@property(nonatomic, assign) int matchLocation;
@property(nonatomic, retain) NSMutableArray *useTimes;

+ (instancetype)commandHistoryEntry;

@end

@implementation CommandHistoryEntry

+ (instancetype)commandHistoryEntry {
    return [[[self alloc] init] autorelease];
}

+ (instancetype)entryWithDictionary:(NSDictionary *)dict {
    CommandHistoryEntry *entry = [self commandHistoryEntry];
    entry.command = dict[kCommand];
    entry.uses = [dict[kUses] intValue];
    entry.lastUsed = [dict[kLastUsed] doubleValue];
    [entry setUseTimesFromSerializedArray:dict[kUseTimes]];
    return entry;
}

- (id)init {
    self = [super init];
    if (self) {
        _useTimes = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_command release];
    [_useTimes release];
    [super dealloc];
}

- (NSArray *)serializedUseTimes {
    NSMutableArray *result = [NSMutableArray array];
    for (CommandUse *use in self.useTimes) {
        [result addObject:[use serializedValue]];
    }
    return result;
}

- (void)setUseTimesFromSerializedArray:(NSArray *)array {
    for (NSArray *value in array) {
        [self.useTimes addObject:[CommandUse commandUseFromSerializedValue:value]];
    }
}

- (NSDictionary *)dictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if (self.command) {
        dict[kCommand] = self.command;
    }
    dict[kUses] = @(self.uses);
    dict[kLastUsed] = @(self.lastUsed);
    dict[kUseTimes] = [self serializedUseTimes];
    return dict;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p command=%@ uses=%d lastUsed=%@ matchLocation=%d>",
            [self class],
            self,
            self.command,
            self.uses,
            [NSDate dateWithTimeIntervalSinceReferenceDate:self.lastUsed],
            self.matchLocation];
}

- (VT100ScreenMark *)lastMark {
    CommandUse *use = [self.useTimes lastObject];
    return use.mark;
}

- (NSString *)lastDirectory {
    CommandUse *use = [self.useTimes lastObject];
    return use.directory.length > 0 ? use.directory : nil;
}

// Used to sort from highest to lowest score. So Ascending means self's score is higher
// than other's.
- (NSComparisonResult)compare:(CommandHistoryEntry *)other {
    if (_matchLocation == 0 && other.matchLocation > 0) {
        return NSOrderedDescending;
    }
    if (other.matchLocation == 0 && _matchLocation > 0) {
        return NSOrderedAscending;
    }
    int otherUses = other.uses;
    if (_uses < otherUses) {
        return NSOrderedDescending;
    } else if (_uses > other.uses) {
        return NSOrderedAscending;
    }
    
    NSTimeInterval otherLastUsed = other.lastUsed;
    if (_lastUsed < otherLastUsed) {
        return NSOrderedDescending;
    } else if (_lastUsed > otherLastUsed) {
        return NSOrderedAscending;
    } else {
        return NSOrderedSame;
    }
}

- (NSComparisonResult)compareUseTime:(CommandHistoryEntry *)other {
    return [@(other.lastUsed) compare:@(self.lastUsed)];
}

- (id)copyWithZone:(NSZone *)zone {
    CommandHistoryEntry *theCopy = [[CommandHistoryEntry alloc] init];
    theCopy.command = self.command;
    theCopy.uses = self.uses;
    theCopy.lastUsed = self.lastUsed;
    theCopy.useTimes = [NSMutableArray array];
    for (CommandUse *use in self.useTimes) {
        [theCopy.useTimes addObject:[use copy]];
    }
    return theCopy;
}


@end

@implementation CommandHistory {
    NSString *_path;
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
        _hosts = [[NSMutableDictionary alloc] init];
        _path = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                     NSUserDomainMask,
                                                     YES) lastObject];
        NSString *appname = [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleNameKey];
        _path = [_path stringByAppendingPathComponent:appname];
        [[NSFileManager defaultManager] createDirectoryAtPath:_path
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL];
        _path = [[_path stringByAppendingPathComponent:@"commandhistory.plist"] copy];

        [self loadCommandHistory];
    }
    return self;
}

- (void)dealloc {
    [_hosts release];
    [_path release];
    [super dealloc];
}

#pragma mark - APIs

- (void)addCommand:(NSString *)command
            onHost:(VT100RemoteHost *)host
       inDirectory:(NSString *)directory
          withMark:(VT100ScreenMark *)mark {
    NSMutableArray *commands = [self commandsForHost:host];
    CommandHistoryEntry *theEntry = nil;
    for (CommandHistoryEntry *entry in commands) {
        if ([entry.command isEqualToString:command]) {
            theEntry = entry;
            break;
        }
    }
    
    if (!theEntry) {
        theEntry = [CommandHistoryEntry commandHistoryEntry];
        theEntry.command = command;
        [commands addObject:theEntry];
    }
    theEntry.uses = theEntry.uses + 1;
    theEntry.lastUsed = [NSDate timeIntervalSinceReferenceDate];
    CommandUse *commandUse = [[[CommandUse alloc] init] autorelease];
    commandUse.time = theEntry.lastUsed;
    commandUse.mark = mark;
    commandUse.directory = directory;
    [theEntry.useTimes addObject:commandUse];

    if ([[PreferencePanel sharedInstance] savePasteHistory]) {
        [NSKeyedArchiver archiveRootObject:[self dictionaryForEntries] toFile:_path];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:kCommandHistoryDidChangeNotificationName
                                                        object:nil];
}

- (BOOL)haveCommandsForHost:(VT100RemoteHost *)host {
    return [[self commandsForHost:host] count] > 0;
}

- (NSArray *)autocompleteSuggestionsWithPartialCommand:(NSString *)partialCommand
                                                onHost:(VT100RemoteHost *)host {
    BOOL emptyPartialCommand = (partialCommand.length == 0);
    NSMutableArray *result = [NSMutableArray array];
    for (CommandHistoryEntry *entry in [self commandsForHost:host]) {
        NSRange match;
        if (!emptyPartialCommand) {
            match = [entry.command rangeOfString:partialCommand];
        }
        if (emptyPartialCommand || match.location == 0) {
            // The FinalTerm algorithm doesn't require |partialCommand| to be a prefix of the
            // history entry, but based on how our autocomplete works, it makes sense to only
            // accept prefixes. Their scoring algorithm is implemented in case this should change.
            entry.matchLocation = match.location;
            [result addObject:entry];
        }
    }
    
    // TODO: Cache this.
    NSArray *sortedEntries = [result sortedArrayUsingSelector:@selector(compare:)];
    return [sortedEntries subarrayWithRange:NSMakeRange(0, MIN(kMaxResults, sortedEntries.count))];
}

- (NSArray *)entryArrayByExpandingAllUsesInEntryArray:(NSArray *)array {
    NSMutableArray *result = [NSMutableArray array];
    for (CommandHistoryEntry *entry in array) {
        for (CommandUse *commandUse in entry.useTimes) {
            CommandHistoryEntry *singleUseEntry = [[entry copy] autorelease];
            [singleUseEntry.useTimes removeAllObjects];

            [singleUseEntry.useTimes addObject:commandUse];
            singleUseEntry.lastUsed = commandUse.time;
            [result addObject:singleUseEntry];
        }
    }
    return [result sortedArrayUsingSelector:@selector(compareUseTime:)];
}

#pragma mark - Private

- (NSString *)keyForHost:(VT100RemoteHost *)host {
    if (host) {
        return [NSString stringWithFormat:@"%@@%@", host.username, host.hostname];
    } else {
        return @"";
    }
}

- (NSMutableArray *)commandsForHost:(VT100RemoteHost *)host {
    NSString *key = [self keyForHost:host];
    NSMutableArray *result = _hosts[key];
    if (!result) {
        _hosts[key] = result = [NSMutableArray array];
    }
    return result;
}

- (void)loadCommandHistory {
    NSDictionary *archive = [NSKeyedUnarchiver unarchiveObjectWithFile:_path];
    for (NSString *host in archive) {
        NSMutableArray *commands = _hosts[host];
        if (!commands) {
            _hosts[host] = commands = [NSMutableArray array];
        }

        for (NSDictionary *commandDict in archive[host]) {
            [commands addObject:[CommandHistoryEntry entryWithDictionary:commandDict]];
        }
    }
}

- (NSDictionary *)dictionaryForEntries {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    for (NSString *key in _hosts) {
        NSArray *array = [self arrayForCommandEntries:_hosts[key]];
        if (array.count) {
            [dictionary setObject:array
                           forKey:key];
        }
    }
    return dictionary;
}

- (NSArray *)arrayForCommandEntries:(NSArray *)entries {
    NSMutableArray *array = [NSMutableArray array];
    NSTimeInterval minLastUse = [NSDate timeIntervalSinceReferenceDate] - kMaxTimeToRememberCommands;
    for (CommandHistoryEntry *entry in entries) {
        if (entry.lastUsed >= minLastUse) {
            [array addObject:[entry dictionary]];
        }
    }
    if (array.count > kMaxCommandsToSavePerHost) {
        return [array subarrayWithRange:NSMakeRange(array.count - kMaxCommandsToSavePerHost,
                                                    kMaxCommandsToSavePerHost)];
    } else {
        return array;
    }
}

- (void)eraseHistory {
    [_hosts release];
    _hosts = [[NSMutableDictionary alloc] init];
    [[NSFileManager defaultManager] removeItemAtPath:_path error:NULL];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kCommandHistoryDidChangeNotificationName
                                                        object:nil];
}

@end
