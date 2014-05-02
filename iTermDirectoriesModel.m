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

@interface iTermDirectoryTreeNode : NSObject

@property(nonatomic, copy) NSString *component;
@property(nonatomic, readonly) NSMutableDictionary *children;  // NSString component -> iTermDirectoryTreeNode
@property(nonatomic, assign) int count;

- (int)numberOfChildrenStartingWithString:(NSString *)prefix;
- (void)removePathWithParts:(NSArray *)parts;

@end

@implementation iTermDirectoryTreeNode

+ (instancetype)nodeWithComponent:(NSString *)component {
    return [[[self alloc] initWithComponent:component] autorelease];
}

- (id)initWithComponent:(NSString *)component {
    self = [super init];
    if (self) {
        _component = [component copy];
        _children = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p component=%@ %lu children>",
            [self class], self, _component, (unsigned long)_children.count];
}

- (int)numberOfChildrenStartingWithString:(NSString *)prefix {
    int number = 0;
    for (NSString *child in _children) {
        if ([child hasPrefix:prefix]) {
            number++;
        }
    }
    return number;
}

- (void)dealloc {
    [_component release];
    [_children release];
    [super dealloc];
}

- (void)removePathWithParts:(NSArray *)parts {
    --_count;
    if (parts.count > 1) {
        NSString *firstPart = parts[0];
        NSArray *tailParts = [parts subarrayWithRange:NSMakeRange(1, parts.count - 1)];
        iTermDirectoryTreeNode *node = _children[firstPart];
        [node removePathWithParts:tailParts];
        if (!node.count) {
            [_children removeObjectForKey:firstPart];
        }
    }
}

@end

@interface iTermDirectoryTree : NSObject {
    iTermDirectoryTreeNode *_root;
}

- (void)addPath:(NSString *)path;
- (NSIndexSet *)abbreviationSafeIndexesInPath:(NSString *)path;
- (void)removePath:(NSString *)path;

@end

@implementation iTermDirectoryTree

- (id)init {
    self = [super init];
    if (self) {
        _root = [[iTermDirectoryTreeNode alloc] initWithComponent:nil];
    }
    return self;
}

- (void)dealloc {
    [_root release];
    [super dealloc];
}

+ (NSMutableArray *)componentsInPath:(NSString *)path {
    NSMutableArray *components = [[[path componentsSeparatedByString:@"/"] mutableCopy] autorelease];
    NSUInteger index = [components indexOfObject:@""];
    while (index != NSNotFound) {
        [components removeObjectAtIndex:index];
        index = [components indexOfObject:@""];
    }
    return components;
}

- (void)addPath:(NSString *)path {
    NSArray *parts = [[self class] componentsInPath:path];
    if (!parts.count) {
        return;
    }
    iTermDirectoryTreeNode *parent = _root;
    parent.count = parent.count + 1;
    for (int i = 0; i < parts.count; i++) {
        NSString *part = parts[i];
        iTermDirectoryTreeNode *node = parent.children[part];
        if (!node) {
            node = [iTermDirectoryTreeNode nodeWithComponent:part];
            parent.children[part] = node;
        }
        node.count = node.count + 1;
        parent = node;
    }
}

- (void)removePath:(NSString *)path {
    NSArray *parts = [[self class] componentsInPath:path];
    if (!parts.count) {
        return;
    }
    [_root removePathWithParts:parts];
}

- (NSIndexSet *)abbreviationSafeIndexesInPath:(NSString *)path {
    NSArray *parts = [[self class] componentsInPath:path];
    iTermDirectoryTreeNode *node = _root;
    NSMutableIndexSet *indexSet = [NSMutableIndexSet indexSet];
    for (int i = 0; i < parts.count; i++) {
        NSString *part = parts[i];
        NSString *prefix = [part substringToIndex:1];
        if ([node numberOfChildrenStartingWithString:prefix] <= 1) {
            [indexSet addIndex:i];
        }
        node = node.children[part];
    }
    return indexSet;
}

@end

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

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p path=%@>",
            [self class], self, _path];
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
    iTermDirectoryTree *_tree;
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
        _tree = [[iTermDirectoryTree alloc] init];
        [self loadDirectories];
    }
    return self;
}

- (void)dealloc {
    [_hostToPathArrayDictionary release];
    [_path release];
    [_tree release];
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
        [_tree addPath:path];
    }
    entry.useCount = entry.useCount + 1;
    entry.lastUse = [NSDate date];

    [self save];
    [[NSNotificationCenter defaultCenter] postNotificationName:kDirectoriesDidChangeNotificationName
                                                        object:nil];
}

- (void)save {
    if ([iTermPreferences boolForKey:kPreferenceKeySavePasteAndCommandHistory]) {
        [NSKeyedArchiver archiveRootObject:[self dictionaryForEntries] toFile:_path];
    }
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
            iTermDirectoryEntry *entry = [iTermDirectoryEntry entryWithDictionary:dict];
            [directories addObject:entry];
            [_tree addPath:entry.path];
        }
    }
}

- (void)eraseHistory {
    [_tree release];
    _tree = [[iTermDirectoryTree alloc] init];
    [_hostToPathArrayDictionary removeAllObjects];
    [[NSFileManager defaultManager] removeItemAtPath:_path error:NULL];

    [[NSNotificationCenter defaultCenter] postNotificationName:kDirectoriesDidChangeNotificationName
                                                        object:nil];
}

- (NSIndexSet *)abbreviationSafeIndexesInEntry:(iTermDirectoryEntry *)entry {
    return [_tree abbreviationSafeIndexesInPath:entry.path];
}

- (NSMutableArray *)componentsInPath:(NSString *)path {
    return [iTermDirectoryTree componentsInPath:path];
}

@end
