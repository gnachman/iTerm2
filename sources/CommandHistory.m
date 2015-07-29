//
//  CommandHistory.m
//  iTerm
//
//  Created by George Nachman on 1/6/14.
//
//

#import "CommandHistory.h"
#import "CommandHistoryEntry.h"
#import "iTermPreferences.h"
#import "PreferencePanel.h"
#import "VT100RemoteHost.h"
#import "VT100ScreenMark.h"

NSString *const kCommandHistoryDidChangeNotificationName = @"kCommandHistoryDidChangeNotificationName";
NSString *const kCommandHistoryHasEverBeenUsed = @"kCommandHistoryHasEverBeenUsed";

static const int kMaxResults = 200;

static const NSTimeInterval kMaxTimeToRememberCommands = 60 * 60 * 24 * 90;
static const int kMaxCommandsToSavePerHost = 200;

@interface CommandHistory ()
@property(nonatomic, retain) NSMutableDictionary *hosts;
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
    return (_hosts.count > 0 ||
            [[NSUserDefaults standardUserDefaults] boolForKey:kCommandHistoryHasEverBeenUsed]);
}

- (void)addCommand:(NSString *)command
            onHost:(VT100RemoteHost *)host
       inDirectory:(NSString *)directory
          withMark:(VT100ScreenMark *)mark {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kCommandHistoryHasEverBeenUsed];
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

    if ([iTermPreferences boolForKey:kPreferenceKeySavePasteAndCommandHistory]) {
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
        } else {
            match = NSMakeRange(0, partialCommand.length);
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

- (void)eraseHistoryForHost:(VT100RemoteHost *)host {
    NSString *key = [self keyForHost:host];
    [_hosts removeObjectForKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:kCommandHistoryDidChangeNotificationName
                                                        object:nil];
}

- (CommandUse *)commandUseWithMarkGuid:(NSString *)markGuid onHost:(VT100RemoteHost *)host {
    if (!markGuid) {
        return nil;
    }
    NSArray *entries = _hosts[[self keyForHost:host]];
    // TODO: Create an index of markGuid's in command uses if this becomes a performance problem during restore.
    for (CommandHistoryEntry *entry in entries) {
        for (CommandUse *use in entry.useTimes) {
            if ([use.markGuid isEqual:markGuid]) {
                return use;
            }
        }
    }
    return nil;
}

@end
