//
//  CommandHistoryEntry.m
//  iTerm
//
//  Created by George Nachman on 1/19/14.
//
//

#import "CommandHistoryEntry.h"
#import "CommandUse.h"

// Keys for serializing an entry
static NSString *const kCommand = @"command";
static NSString *const kDirectory = @"directory";
static NSString *const kUses = @"uses";
static NSString *const kLastUsed = @"last used";
static NSString *const kUseTimes = @"use times";

@interface CommandHistoryEntry () <NSCopying>

@property(nonatomic, retain) NSMutableArray *useTimes;

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
