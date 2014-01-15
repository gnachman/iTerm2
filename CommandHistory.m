//
//  CommandHistory.m
//  iTerm
//
//  Created by George Nachman on 1/6/14.
//
//

#import "CommandHistory.h"
#import "VT100RemoteHost.h"

static const int kMaxResults = 200;

// Keys for serializing an entry
static NSString *const kCommand = @"command";
static NSString *const kUses = @"uses";
static NSString *const kLastUsed = @"last used";

// Top level serialization keys
static NSString *const kHostname = @"hostname";
static NSString *const kCommands = @"commands";

static const NSTimeInterval kMaxTimeToRememberCommands = 60 * 60 * 24 * 90;
static const int kMaxCommandsToSavePerHost = 200;

@interface CommandHistory ()
@property(nonatomic, retain) NSMutableDictionary *hosts;
@end

@interface CommandHistoryEntry ()

// First character matched by current search.
@property(nonatomic, assign) int matchLocation;

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

    return entry;
}

- (NSDictionary *)dictionary {
    return @{ kCommand: self.command,
              kUses: @(self.uses),
              kLastUsed: @(self.lastUsed) };
}

- (void)dealloc {
    [_command release];
    [super dealloc];
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

- (void)addCommand:(NSString *)command onHost:(VT100RemoteHost *)host {
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

    [NSKeyedArchiver archiveRootObject:[self dictionaryForEntries] toFile:_path];
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

@end
