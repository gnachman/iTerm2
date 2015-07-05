//
//  iTermDirectoriesModel.m
//  iTerm
//
//  Created by George Nachman on 5/1/14.
//
//

#import "iTermDirectoriesModel.h"
#import "iTermPreferences.h"
#import "NSArray+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "VT100RemoteHost.h"

static NSString *const kDirectoryEntryPath = @"path";
static NSString *const kDirectoryEntryUseCount = @"use count";
static NSString *const kDirectoryEntryLastUse = @"last use";
static NSString *const kDirectoryEntryIsStarred = @"starred";
static NSString *const kDirectoryEntryShortcut = @"shortcut";

NSString *const kDirectoriesDidChangeNotificationName = @"kDirectoriesDidChangeNotificationName";

static const NSTimeInterval kMaxTimeToRememberDirectories = 60 * 60 * 24 * 90;
static const int kMaxDirectoriesToSavePerHost = 200;

@interface iTermDirectoriesModel ()
- (NSIndexSet *)abbreviationSafeIndexesInEntry:(iTermDirectoryEntry *)entry;
@end

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

+ (NSMutableArray *)attributedComponentsInPath:(NSAttributedString *)path {
    NSMutableArray *components = [[[path attributedComponentsSeparatedByString:@"/"] mutableCopy] autorelease];
    for (int i = components.count - 1; i >= 0; i--) {
        if ([components[i] string].length == 0) {
            [components removeObjectAtIndex:i];
        }
    }
    return components;
}

+ (NSMutableArray *)componentsInPath:(NSString *)path {
    if (!path) {
        return nil;
    }
    NSMutableArray *components = [[[path componentsSeparatedByString:@"/"] mutableCopy] autorelease];
    NSUInteger index = [components indexOfObject:@""];
    while (index != NSNotFound && components.count > 0) {
        [components removeObjectAtIndex:index];
        index = [components indexOfObject:@""];
    }
    return components;
}

- (void)addPath:(NSString *)path {
    NSArray *parts = [iTermDirectoryTree componentsInPath:path];
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
    NSArray *parts = [iTermDirectoryTree  componentsInPath:path];
    if (!parts.count) {
        return;
    }
    [_root removePathWithParts:parts];
}

- (NSIndexSet *)abbreviationSafeIndexesInPath:(NSString *)path {
    NSArray *parts = [iTermDirectoryTree  componentsInPath:path];
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
    entry.starred = [dictionary[kDirectoryEntryIsStarred] boolValue];
    entry.shortcut = dictionary[kDirectoryEntryShortcut];
    return entry;
}

- (NSDictionary *)dictionary {
    return @{ kDirectoryEntryPath: _path ?: @"",
              kDirectoryEntryUseCount: @(_useCount),
              kDirectoryEntryLastUse: @([_lastUse timeIntervalSinceReferenceDate]),
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

- (NSAttributedString *)attributedStringForTableColumn:(NSTableColumn *)aTableColumn
                               basedOnAttributedString:(NSAttributedString *)attributedString
                                        baseAttributes:(NSDictionary *)baseAttributes {
    NSFont *font = [[aTableColumn dataCell] font];
    // Split up the passed-in attributed string into components.
    // There is a wee bug where attributes on slashes are lost.
    NSMutableArray *components = [iTermDirectoryTree attributedComponentsInPath:attributedString];

    // Figure out which components can safely be abbreviated.
    NSIndexSet *abbreviationSafeIndexes =
        [[iTermDirectoriesModel sharedInstance] abbreviationSafeIndexesInEntry:self];

    // Initialize attributes.
    NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
    style.lineBreakMode = NSLineBreakByTruncatingMiddle;
    NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithDictionary:baseAttributes];
    attributes[NSFontAttributeName] = font;
    attributes[NSParagraphStyleAttributeName] = style;

    // Compute the prefix of the result.
    NSMutableAttributedString *result = [[[NSMutableAttributedString alloc] init] autorelease];
    NSString *prefix = _starred ? @"★ /" : @"/";
    [result iterm_appendString:prefix withAttributes:attributes];
    NSAttributedString *attributedSlash =
        [[[NSAttributedString alloc] initWithString:@"/" attributes:attributes] autorelease];

    // Initialize the abbreviated name in case no further changes are made.
    NSMutableAttributedString *abbreviatedName = [[[NSMutableAttributedString alloc] init] autorelease];
    [abbreviatedName iterm_appendString:prefix withAttributes:attributes];
    NSAttributedString *attributedPath =
        [components attributedComponentsJoinedByAttributedString:attributedSlash];
    [abbreviatedName appendAttributedString:attributedPath];

    // Abbreviate each allowed component until it fits. The last component can't be abbreviated.
    CGFloat maxWidth = aTableColumn.width;
    for (int i = 0; i + 1 < components.count && [abbreviatedName size].width > maxWidth; i++) {
        if ([abbreviationSafeIndexes containsIndex:i]) {
            components[i] = [components[i] attributedSubstringFromRange:NSMakeRange(0, 1)];
        }
        [abbreviatedName deleteCharactersInRange:NSMakeRange(0, abbreviatedName.length)];
        [abbreviatedName iterm_appendString:prefix withAttributes:attributes];
        attributedPath = [components attributedComponentsJoinedByAttributedString:attributedSlash];
        [abbreviatedName appendAttributedString:attributedPath];
    }

    return abbreviatedName;
}

- (NSAttributedString *)attributedStringForTableColumn:(NSTableColumn *)aTableColumn {
    NSAttributedString *theString = [[[NSAttributedString alloc] initWithString:_path] autorelease];
    return [self attributedStringForTableColumn:aTableColumn
                        basedOnAttributedString:theString
                                 baseAttributes:@{}];
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
    if (!isChange || !path) {
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
    // Keep starred entries separate from non-starred to ensure they never go away.
    NSMutableArray *array = [NSMutableArray array];
    NSMutableArray *starredArray = [NSMutableArray array];
    NSDate *minLastUse = [[NSDate date] dateByAddingTimeInterval:-kMaxTimeToRememberDirectories];
    for (iTermDirectoryEntry *entry in entries) {
        if (entry.starred) {
            [starredArray addObject:[entry dictionary]];
        } else if ([entry.lastUse compare:minLastUse] == NSOrderedDescending) {
            [array addObject:[entry dictionary]];
        }
    }
    NSArray *baseArray;
    if (array.count > kMaxDirectoriesToSavePerHost) {
        baseArray = [array subarrayWithRange:NSMakeRange(array.count - kMaxDirectoriesToSavePerHost,
                                                         kMaxDirectoriesToSavePerHost)];
    } else {
        baseArray = array;
    }
    [starredArray addObjectsFromArray:baseArray];
    return starredArray;
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

- (void)eraseHistoryForHost:(VT100RemoteHost *)host {
    [_hostToPathArrayDictionary removeObjectForKey:[self keyForHost:host]];
}

- (NSIndexSet *)abbreviationSafeIndexesInEntry:(iTermDirectoryEntry *)entry {
    return [_tree abbreviationSafeIndexesInPath:entry.path];
}

- (BOOL)haveEntriesForHost:(VT100RemoteHost *)host {
    NSString *key = [self keyForHost:host];
    return _hostToPathArrayDictionary[key] != nil;
}

@end
