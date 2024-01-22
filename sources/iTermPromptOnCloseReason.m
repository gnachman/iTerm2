//
//  iTermPromptOnCloseReason.m
//  iTerm2
//
//  Created by George Nachman on 11/29/16.
//
//

#import "iTermPromptOnCloseReason.h"
#import "ITAddressBookMgr.h"
#import "NSArray+iTerm.h"

@interface iTermPromptOnCloseReason()
@property (nonatomic, readonly) NSNumber *priority;
+ (NSString *)groupFooter;
@end

@interface iTermPromptOnCloseCompoundReason : iTermPromptOnCloseReason
@end

@implementation iTermPromptOnCloseCompoundReason {
    NSMutableArray<iTermPromptOnCloseReason *> *_children;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _children = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_children release];
    [super dealloc];
}

- (BOOL)hasReason {
    return _children.count > 0;
}

- (NSString *)message {
    NSArray<iTermPromptOnCloseReason *> *sortedReasons = [_children sortedArrayUsingComparator:^NSComparisonResult(iTermPromptOnCloseReason *_Nonnull obj1,
                                                                                                                   iTermPromptOnCloseReason *_Nonnull obj2) {
        return [obj1.priority compare:obj2.priority];
    }];

    __block NSString *previousMessage = nil;
    NSArray *uniqueReasons = [sortedReasons filteredArrayUsingBlock:^BOOL(iTermPromptOnCloseReason *reason) {
        BOOL ok = ![reason.message isEqualToString:previousMessage];
        previousMessage = reason.message;
        return ok;
    }];

    __block Class previousClass = [uniqueReasons.firstObject class];
    NSArray *prettyReasons = [uniqueReasons flatMapWithBlock:^id(iTermPromptOnCloseReason *reason) {
        NSString *formattedMessage = [@"• " stringByAppendingString:reason.message];
        NSString *groupFooter = [previousClass groupFooter];
        NSArray *result;
        if (reason.class != previousClass && groupFooter) {
            result = @[ groupFooter, @"", formattedMessage ];
        } else {
            result = @[ formattedMessage ];
        }
        previousClass = [reason class];
        return result;
    }];
    if ([previousClass groupFooter]) {
        prettyReasons = [prettyReasons arrayByAddingObject:[previousClass groupFooter]];
    }

    return [prettyReasons componentsJoinedByString:@"\n"];
}

- (void)addReason:(iTermPromptOnCloseReason *)reason {
    if ([reason isKindOfClass:[iTermPromptOnCloseCompoundReason class]]) {
        iTermPromptOnCloseCompoundReason *compound = (iTermPromptOnCloseCompoundReason *)reason;
        for (iTermPromptOnCloseReason *child in compound->_children) {
            [self addReason:child];
        }
    } else {
        [_children addObject:reason];
    }
}

- (NSNumber *)priority {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

@end

@interface iTermPromptOnCloseAlwaysReason : iTermPromptOnCloseReason
@end

@implementation iTermPromptOnCloseAlwaysReason {
    NSString *_name;
}

- (instancetype)initWithProfileName:(NSString *)name {
    self = [super init];
    if (self) {
        _name = [name copy];
    }
    return self;
}

- (void)dealloc {
    [_name release];
    [super dealloc];
}

- (NSString *)message {
    return [NSString stringWithFormat:@"The profile “%@” always requires confirmation.", _name];
}

+ (NSString *)groupFooter {
    return @"You can change this setting in Settings > Profiles > Session";
}

- (NSNumber *)priority {
    return @50;
}

@end

@interface iTermPromptOnCloseBlockedReason : iTermPromptOnCloseReason
@end

@implementation iTermPromptOnCloseBlockedReason {
    NSString *_name;
    NSArray<NSString *> *_jobs;
}

- (instancetype)initWithName:(NSString *)name jobs:(NSArray<NSString *> *)jobs {
    self = [super init];
    if (self) {
        _name = [name copy];
        _jobs = [jobs copy];
    }
    return self;
}

- (void)dealloc {
    [_name release];
    [_jobs release];
    [super dealloc];
}

- (NSString *)message {
    const NSInteger maxJobsToList = 3;
    if (_jobs.count <= maxJobsToList) {
        return [NSString stringWithFormat:@"A session with profile “%@” is running %@.",
                _name,
                [_jobs componentsJoinedWithOxfordComma]];
    } else {
        return [NSString stringWithFormat:@"A session with profile “%@” is running %@, and %@ other %@.",
                _name,
                [[_jobs subarrayWithRange:NSMakeRange(0, maxJobsToList)] componentsJoinedByString:@", "],
                @(_jobs.count - maxJobsToList),
                _jobs.count == (maxJobsToList + 1) ? @"job" : @"jobs"];
    }
}

+ (NSString *)groupFooter {
    return @"You can change this setting in Settings > Profiles > Session";
}

- (NSNumber *)priority {
    return @25;
}

@end

@interface iTermPromptOnCloseMessageReason : iTermPromptOnCloseReason
@end

@implementation iTermPromptOnCloseMessageReason {
    NSString *_message;
    double _priority;
}

- (instancetype)initWithMessage:(NSString *)message priority:(double)priority {
    self = [super init];
    if (self) {
        _message = [message copy];
        _priority = priority;
    }
    return self;
}

- (void)dealloc {
    [_message release];
    [super dealloc];
}

- (NSString *)message {
    return _message;
}

- (NSNumber *)priority {
    return @(_priority);
}

@end

@implementation iTermPromptOnCloseReason

+ (instancetype)noReason {
    return [[[iTermPromptOnCloseCompoundReason alloc] init] autorelease];
}

+ (instancetype)profileAlwaysPrompts:(Profile *)profile {
    return [[[iTermPromptOnCloseAlwaysReason alloc] initWithProfileName:profile[KEY_NAME]] autorelease];
}

+ (instancetype)profile:(Profile *)profile blockedByJobs:(NSArray<NSString *> *)jobs {
    return [[[iTermPromptOnCloseBlockedReason alloc] initWithName:profile[KEY_NAME] jobs:jobs] autorelease];
}

+ (instancetype)alwaysConfirmQuitPreferenceEnabled {
    return [[[iTermPromptOnCloseMessageReason alloc] initWithMessage:@"“Prefs > General > Closing > Confirm Quit iTerm2” is enabled and there is at least one terminal window." priority:100] autorelease];
}

+ (instancetype)alwaysConfirmQuitPreferenceEvenIfThereAreNoWindowsEnabled {
    return [[[iTermPromptOnCloseMessageReason alloc] initWithMessage:@"“Prefs > General > Closing > Confirm Quit iTerm2” and “Even if there are no windows” is enabled." priority:100] autorelease];
}

+ (instancetype)closingMultipleSessionsPreferenceEnabled {
    return [[[iTermPromptOnCloseMessageReason alloc] initWithMessage:@"“Prefs > General > Closing > Confirm closing multiple sessions” is enabled." priority:90] autorelease];
}

+ (instancetype)tmuxClientsAlwaysPromptBecauseJobsAreNotExposed {
    return [[[iTermPromptOnCloseMessageReason alloc] initWithMessage:@"A tmux session is configured to prompt if jobs are running, but tmux doesn’t expose the process tree." priority:80] autorelease];
}

- (BOOL)hasReason {
    return YES;
}

+ (NSString *)groupFooter {
    return nil;
}


- (NSString *)message {
    [self doesNotRecognizeSelector:_cmd];
    return @"";
}

- (void)addReason:(iTermPromptOnCloseReason *)reason {
    [self doesNotRecognizeSelector:_cmd];
}

@end
