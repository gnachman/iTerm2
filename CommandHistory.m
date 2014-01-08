//
//  CommandHistory.m
//  iTerm
//
//  Created by George Nachman on 1/6/14.
//
//

#import "CommandHistory.h"
#import "VT100RemoteHost.h"

static const int kMaxResults = 20;

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

- (NSComparisonResult)compare:(CommandHistoryEntry *)other {
    if (_matchLocation == 0 && other.matchLocation > 0) {
        return NSOrderedAscending;
    }
    if (other.matchLocation == 0 && _matchLocation > 0) {
        return NSOrderedDescending;
    }
    int otherUses = other.uses;
    if (_uses < otherUses) {
        return NSOrderedAscending;
    } else if (_uses > other.uses) {
        return NSOrderedDescending;
    }
    
    NSTimeInterval otherLastUsed = other.lastUsed;
    if (_lastUsed < otherLastUsed) {
        return NSOrderedAscending;
    } else if (_lastUsed > otherLastUsed) {
        return NSOrderedDescending;
    } else {
        return NSOrderedSame;
    }
}

@end

@implementation CommandHistory

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
    }
    return self;
}

- (void)dealloc {
    [_hosts release];
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
}

- (NSArray *)autocompleteSuggestionsWithPartialCommand:(NSString *)partialCommand
                                                onHost:(VT100RemoteHost *)host {
    NSMutableArray *result = [NSMutableArray array];
    for (CommandHistoryEntry *entry in [self commandsForHost:host]) {
        NSRange match = [entry.command rangeOfString:partialCommand];
        if (match.location != NSNotFound) {
            entry.matchLocation = match.location;
            [result addObject:entry];
        }
    }
    
    // TODO: Cache this.
    NSArray *sortedEntries = [result sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *strings = [NSMutableArray array];
    for (CommandHistoryEntry *entry in sortedEntries) {
        [strings addObject:entry.command];
        if (strings.count == kMaxResults) {
            break;
        }
    }
    return strings;
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
        _hosts[key] = [NSMutableArray array];
    }
    return result;
}

@end
