//
//  iTermDirectoriesModel.m
//  iTerm
//
//  Created by George Nachman on 5/1/14.
//
//

#import "iTermDirectoriesModel.h"
#import "iTermPreferences.h"
#import "VT100RemoteHost.h"

static NSString *const kDirectoryEntryPath = @"path";
static NSString *const kDirectoryEntryUseCount = @"use count";
static NSString *const kDirectoryEntryLastUse = @"last use";
static NSString *const kDirectoryEntryDescription = @"description";
static NSString *const kDirectoryEntryIsStarred = @"starred";
static NSString *const kDirectoryEntryShortcut = @"shortcut";

NSString *const kDirectoriesDidChangeNotificationName = @"kDirectoriesDidChangeNotificationName";

static const NSTimeInterval kMaxTimeToRememberDirectories = 60 * 60 * 24 * 90;
static const int kMaxDirectoriesToSavePerHost = 200;

@implementation iTermDirectoryEntry

+ (instancetype)entryWithDictionary:(NSDictionary *)dictionary {
    iTermDirectoryEntry *entry = [[[iTermDirectoryEntry alloc] init] autorelease];
    entry.path = dictionary[kDirectoryEntryPath];
    entry.useCount = [dictionary[kDirectoryEntryUseCount] intValue];
    entry.lastUse =
    [NSDate dateWithTimeIntervalSinceReferenceDate:[dictionary[kDirectoryEntryLastUse] doubleValue]];
    entry.description = dictionary[kDirectoryEntryDescription];
    entry.starred = [dictionary[kDirectoryEntryIsStarred] boolValue];
    entry.shortcut = dictionary[kDirectoryEntryShortcut];
    return entry;
}

- (NSDictionary *)dictionary {
    return @{ kDirectoryEntryPath: _path ?: @"",
              kDirectoryEntryUseCount: @(_useCount),
              kDirectoryEntryLastUse: @([_lastUse timeIntervalSinceReferenceDate]),
              kDirectoryEntryDescription: _description ?: @"",
              kDirectoryEntryIsStarred: @(_starred),
              kDirectoryEntryShortcut: _shortcut ?: @"" };
}

- (NSComparisonResult)compare:(iTermDirectoryEntry *)other {
    if (_starred && !other.starred) {
        return NSOrderedAscending;
    } else if (!_starred && other.starred) {
        return NSOrderedDescending;
    }

    if (_description.length && !other.description.length) {
        return NSOrderedAscending;
    } else if (!_description.length && other.description.length) {
        return NSOrderedDescending;
    }

    if ((int)log2(_useCount) > (int)log2(other.useCount)) {
        return NSOrderedAscending;
    } else if ((int)log2(_useCount) < (int)log2(other.useCount)) {
        return NSOrderedDescending;
    }

    return [other.lastUse compare:_lastUse];
}

- (void)dealloc {
    [_path release];
    [_lastUse release];
    [super dealloc];
}

@end

@implementation iTermDirectoriesModel {
    NSMutableDictionary *_hostToPathArrayDictionary;  // NSString hostname -> NSArray iTermDirectoryEntry
    NSString *_path;  // Path to backing store
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
        _hostToPathArrayDictionary = [[NSMutableDictionary alloc] init];
        _path = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                     NSUserDomainMask,
                                                     YES) lastObject];
        NSString *appname = [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleNameKey];
        _path = [_path stringByAppendingPathComponent:appname];
        [[NSFileManager defaultManager] createDirectoryAtPath:_path
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL];
        _path = [[_path stringByAppendingPathComponent:@"directories.plist"] copy];

        [self loadDirectories];
    }
    return self;
}

- (void)dealloc {
    [_hostToPathArrayDictionary release];
    [_path release];
    [super dealloc];
}

- (void)recordUseOfPath:(NSString *)path
                 onHost:(VT100RemoteHost *)host
               isChange:(BOOL)isChange {
    if (!isChange) {
        return;
    }
    NSMutableArray *array = [self arrayForHost:host createIfNeeded:YES];
    iTermDirectoryEntry *entry = nil;
    for (iTermDirectoryEntry *anEntry in array) {
        if ([anEntry.path isEqualToString:path]) {
            entry = anEntry;
            break;
        }
    }

    if (!entry) {
        entry = [[[iTermDirectoryEntry alloc] init] autorelease];
        entry.path = path;
        [array addObject:entry];
    }
    entry.useCount = entry.useCount + 1;
    entry.lastUse = [NSDate date];

    if ([iTermPreferences boolForKey:kPreferenceKeySavePasteAndCommandHistory]) {
        [NSKeyedArchiver archiveRootObject:[self dictionaryForEntries] toFile:_path];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:kDirectoriesDidChangeNotificationName
                                                        object:nil];
}

- (NSArray *)entriesSortedByScoreOnHost:(VT100RemoteHost *)host {
    NSMutableArray *array = [self arrayForHost:host createIfNeeded:NO];
    return [array sortedArrayUsingSelector:@selector(compare:)];
}

- (NSString *)keyForHost:(VT100RemoteHost *)host {
    if (host) {
        return [NSString stringWithFormat:@"%@@%@", host.username, host.hostname];
    } else {
        return @"";
    }
}

- (NSMutableArray *)arrayForHost:(VT100RemoteHost *)host createIfNeeded:(BOOL)createIfNeeded {
    NSString *key = [self keyForHost:host];
    NSMutableArray *array = _hostToPathArrayDictionary[key];
    if (!array && createIfNeeded) {
        array = [NSMutableArray array];
        _hostToPathArrayDictionary[key] = array;
    }
    return array;
}

- (NSDictionary *)dictionaryForEntries {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    for (NSString *key in _hostToPathArrayDictionary) {
        NSArray *array = [self arrayForEntries:_hostToPathArrayDictionary[key]];
        if (array.count) {
            [dictionary setObject:array
                           forKey:key];
        }
    }
    return dictionary;
}

- (NSArray *)arrayForEntries:(NSArray *)entries {
    NSMutableArray *array = [NSMutableArray array];
    NSDate *minLastUse = [[NSDate date] dateByAddingTimeInterval:-kMaxTimeToRememberDirectories];
    for (iTermDirectoryEntry *entry in entries) {
        if ([entry.lastUse compare:minLastUse] == NSOrderedDescending) {
            [array addObject:[entry dictionary]];
        }
    }
    if (array.count > kMaxDirectoriesToSavePerHost) {
        return [array subarrayWithRange:NSMakeRange(array.count - kMaxDirectoriesToSavePerHost,
                                                    kMaxDirectoriesToSavePerHost)];
    } else {
        return array;
    }
}

- (void)loadDirectories {
    NSDictionary *archive = [NSKeyedUnarchiver unarchiveObjectWithFile:_path];
    for (NSString *host in archive) {
        NSMutableArray *directories = _hostToPathArrayDictionary[host];
        if (!directories) {
            directories = [NSMutableArray array];
            _hostToPathArrayDictionary[host] = directories;
        }

        for (NSDictionary *dict in archive[host]) {
            [directories addObject:[iTermDirectoryEntry entryWithDictionary:dict]];
        }
    }
}

- (void)eraseHistory {
    [_hostToPathArrayDictionary removeAllObjects];
    [[NSFileManager defaultManager] removeItemAtPath:_path error:NULL];

    [[NSNotificationCenter defaultCenter] postNotificationName:kDirectoriesDidChangeNotificationName
                                                        object:nil];
}

@end
