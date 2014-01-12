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

@end
