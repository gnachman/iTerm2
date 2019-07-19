//
//  iTermAutomaticProfileSwitching.m
//  iTerm2
//
//  Created by George Nachman on 2/28/16.
//
//

#import "iTermAutomaticProfileSwitcher.h"
#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermRule.h"
#import "iTermScriptHistory.h"
#import "iTermUserDefaults.h"
#import "NSDictionary+iTerm.h"
#import "NSDictionary+Profile.h"

static void APSWriteToScriptHistory(id<iTermAutomaticProfileSwitcherDelegate> delegate,
                                    NSString *format, ...) {
    if (![iTermUserDefaults enableAutomaticProfileSwitchingLogging]) {
        return;
    }
    [[iTermScriptHistory sharedInstance] addAPSLoggingEntryIfNeeded];

    va_list args;
    va_start(args, format);
    NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *output = [NSString stringWithFormat:@"[%@] %@\n",
                        [delegate automaticProfileSwitcherSessionName],
                        string];
    [[iTermScriptHistoryEntry apsEntry] addOutput:output];
}

#define APSLog(args...) do { DLog(args); APSWriteToScriptHistory(self.delegate, args); } while (0)

static NSString *const kProfileKey = @"Profile";
static NSString *const kOriginalProfileKey = @"Original Profile";
static NSString *const kOverriddenFieldsKey = @"Overridden Fields";

NS_ASSUME_NONNULL_BEGIN

@implementation iTermSavedProfile

- (instancetype)initWithSavedState:(NSDictionary *)state {
    self = [super init];
    if (self) {
        state = [state dictionaryByRemovingNullValues];
        self.profile = state[kProfileKey];
        self.originalProfile = state[kOriginalProfileKey];
        self.overriddenFields = state[kOverriddenFieldsKey];
    }
    return self;
}

- (NSDictionary *)savedState {
    return @{ kProfileKey: _profile,
              kOriginalProfileKey: _originalProfile ?: [NSNull null],
              kOverriddenFieldsKey: _overriddenFields ?: [NSNull null] };
}

@end

static NSString *const kStackKey = @"Profile Stack";

@implementation iTermAutomaticProfileSwitcher {
    NSMutableArray<iTermSavedProfile *> *_profileStack;
    NSString *_lastHostname;
    NSString *_lastUsername;
    NSString *_lastPath;
    NSString *_lastJob;
    NSString *_lastProfileGUID;
    BOOL _dirty;
}

- (instancetype)initWithDelegate:(id<iTermAutomaticProfileSwitcherDelegate>)delegate {
    self = [super init];
    if (self) {
        _profileStack = [[NSMutableArray alloc] init];
        _delegate = delegate;
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithDelegate:(id<iTermAutomaticProfileSwitcherDelegate>)delegate
                      savedState:(NSDictionary *)savedState {
    self = [self initWithDelegate:delegate];
    if (self) {
        for (NSDictionary *dict in savedState[kStackKey]) {
            iTermSavedProfile *savedProfile = [[iTermSavedProfile alloc] initWithSavedState:dict];
            if (savedProfile) {
                [_profileStack addObject:savedProfile];
            }
            DLog(@"Initialized automatic profile switcher %@", self);
        }
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadAllProfiles)
                                                 name:kReloadAllProfiles
                                               object:nil];
}

- (void)reloadAllProfiles {
    APSLog(@"A profile has changed. This will cause APS to re-check its state.");
    _dirty = YES;
}

#pragma mark - APIs

- (void)setHostname:(nullable NSString *)hostname
           username:(nullable NSString *)username
               path:(nullable NSString *)path
                job:(nullable NSString *)job {
    NSString *guid = [self.delegate automaticProfileSwitcherCurrentProfile][KEY_GUID];
    if (!_dirty &&
        [hostname isEqualToString:_lastHostname] &&
        [username isEqualToString:_lastUsername] &&
        [path isEqualToString:_lastPath] &&
        [job isEqualToString:_lastJob] &&
        [_lastProfileGUID isEqualToString:guid]) {
        return;
    }
    _lastHostname = [hostname copy];
    _lastUsername = [username copy];
    _lastPath = [path copy];
    _lastJob = [job copy];
    _lastProfileGUID = [guid copy];
    _dirty = NO;

    APSLog(@"APS: Updating configuration to hostname=%@, username=%@, path=%@, job=%@",
           hostname, username, path, job);
    BOOL sticky = NO;

    Profile *currentProfile = [_delegate automaticProfileSwitcherCurrentProfile];
    double scoreForCurrentProfile = [self highestScoreForProfile:currentProfile
                                                        hostname:hostname
                                                        username:username
                                                            path:path
                                                             job:job];
    double scoreForTopmostMatchingSavedProfile = 0;
    iTermSavedProfile *topmostMatchingSavedProfile =
        [self topmostSavedProfileMatchingHostname:hostname
                                         username:username
                                             path:path
                                              job:job
                                            score:&scoreForTopmostMatchingSavedProfile];
    APSLog(@"The current profile is %@ with a score of %0.2f. The highest-ranking profile in the stack is %@, with score of %0.2f",
           currentProfile[KEY_NAME],
           scoreForCurrentProfile,
           topmostMatchingSavedProfile.profile[KEY_NAME],
           scoreForTopmostMatchingSavedProfile);

    if (topmostMatchingSavedProfile &&
        ![topmostMatchingSavedProfile.originalProfile isEqualToProfile:currentProfile] &&
        scoreForTopmostMatchingSavedProfile > scoreForCurrentProfile) {
        APSLog(@"Profile %@ is in the stack and outranks the current profile. Will switch, but first, remove it and subsequent entries from the stack.", topmostMatchingSavedProfile.profile[KEY_NAME]);
        while (_profileStack.lastObject.originalProfile == topmostMatchingSavedProfile.originalProfile) {
            APSLog(@"Pop");
            [_profileStack removeLastObject];
        }
        APSLog(@"Stack is now: %@", self.profileStackString);
        APSLog(@"Switch to saved profile from stack: %@", topmostMatchingSavedProfile.profile[KEY_NAME]);
        [_delegate automaticProfileSwitcherLoadProfile:topmostMatchingSavedProfile];
    } else {
        APSLog(@"No profile in the stack outranks the current profile. Check if any profile not in the stack outranks the current profile.");
        double scoreOfHighestScoringProfile = 0;
        Profile *highestScoringProfile = [self highestScoringProfileForHostname:hostname
                                                                       username:username
                                                                           path:path
                                                                            job:job
                                                                         sticky:&sticky
                                                                          score:&scoreOfHighestScoringProfile];
        APSLog(@"The highest scoring profile is %@ with a score of %@",
               highestScoringProfile[KEY_NAME],
               @(scoreOfHighestScoringProfile));
        if (highestScoringProfile && ![highestScoringProfile isEqualToProfile:currentProfile]) {
            APSLog(@"Will switch to profile %@", highestScoringProfile[KEY_NAME]);
            [self pushCurrentProfileIfNeeded];

            iTermSavedProfile *newSavedProfile = [[iTermSavedProfile alloc] init];
            newSavedProfile.originalProfile = highestScoringProfile;
            APSLog(@"Switch to profile %@", highestScoringProfile[KEY_NAME]);
            [_delegate automaticProfileSwitcherLoadProfile:newSavedProfile];

            if (sticky) {
                APSLog(@"This profile's rule is sticky. Clearing the stack and pushing the new profile.");
                [_profileStack removeAllObjects];
                [self pushCurrentProfileIfNeeded];
            }
            APSLog(@"Stack is now: %@", self.profileStackString);
        } else if (!highestScoringProfile && _profileStack.count) {
            APSLog(@"No rule was matched by any profile, but the stack is not empty.");
            // Restore first profile in stack
            if (_profileStack.count > 1) {
                APSLog(@"Removing all but first profile in the stack since no rule was matched.");
                [_profileStack removeObjectsInRange:NSMakeRange(1, _profileStack.count - 1)];
                APSLog(@"Stack is now: %@", self.profileStackString);
            }
            if (![_profileStack.firstObject.originalProfile isEqualToProfile:currentProfile]) {
                APSLog(@"Switch to the topmost profile in the stack: %@", [_profileStack.firstObject profile][KEY_NAME]);
                [_delegate automaticProfileSwitcherLoadProfile:_profileStack.firstObject];
            } else {
                APSLog(@"Not switching profiles because the topmost profile in the stack equals the current profile.");
            }
        } else {
            APSLog(@"Not doing anything. Can't improve on the status quo.");
        }
    }
}

- (NSDictionary *)savedState {
    NSMutableArray *stack = [NSMutableArray array];
    for (iTermSavedProfile *savedProfile in _profileStack) {
        [stack addObject:savedProfile.savedState];
    }
    return @{ kStackKey: stack };
}

#pragma mark - Diagnostics

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p stack=%@>",
            NSStringFromClass(self.class), self, self.profileStackString];
}

- (NSString *)profileStackString {
    NSMutableString *temp = [NSMutableString string];
    for (iTermSavedProfile *savedProfile in _profileStack) {
        [temp appendFormat:@"%@ ", savedProfile.profile[KEY_NAME]];
    }
    return temp;
}

#pragma mark - Private

// Search all the profiles for one that is the best match for the current configuration.
- (nullable Profile *)highestScoringProfileForHostname:(NSString *)hostname
                                              username:(NSString *)username
                                                  path:(NSString *)path
                                                   job:(NSString *)job
                                                sticky:(BOOL *)sticky
                                                 score:(double *)scorePtr {
    // Construct a map from host binding to profile. This could be expensive with a lot of profiles
    // but it should be fairly rare for this code to run.
    NSMutableDictionary<NSString *, Profile *> *ruleToProfileMap = [NSMutableDictionary dictionary];
    for (Profile *profile in [_delegate automaticProfileSwitcherAllProfiles]) {
        NSArray *rules = profile[KEY_BOUND_HOSTS];
        for (NSString *rule in rules) {
            ruleToProfileMap[rule] = profile;
        }
    }

    // Find the best-matching rule.
    double bestScore = 0;
    Profile *bestProfile = nil;

    for (NSString *ruleString in ruleToProfileMap) {
        iTermRule *rule = [iTermRule ruleWithString:ruleString];
        double score = [rule scoreForHostname:hostname username:username path:path job:job];
        if (score > bestScore) {
            bestScore = score;
            bestProfile = ruleToProfileMap[ruleString];
            if (sticky) {
                *sticky = rule.isSticky;
            }
        }
    }
    if (scorePtr) {
        *scorePtr = bestScore;
    }
    return bestProfile;
}

// If the current configuration is not already on the top of the stack, push it.
- (void)pushCurrentProfileIfNeeded {
    if (![_profileStack.lastObject.originalProfile isEqualToProfile:_delegate.automaticProfileSwitcherCurrentProfile]) {
        // Push the current profile state onto the stack if its guid is different that the one
        // already on the stack. This means if you make changes in Edit Info they'll be lost.
        APSLog(@"Push profile on to stack: %@", _delegate.automaticProfileSwitcherCurrentProfile[KEY_NAME]);
        [_profileStack addObject:_delegate.automaticProfileSwitcherCurrentSavedProfile];
        APSLog(@"Stack is now: %@", [self profileStackString]);
    } else {
        APSLog(@"Not pushing profile %@ because it matches the top of the stack.",
             _delegate.automaticProfileSwitcherCurrentProfile[KEY_NAME]);
    }
}

// Does any rule in |candidate| match the current configuration?
- (double)highestScoreForProfile:(Profile *)candidate
                        hostname:(NSString *)hostname
                        username:(NSString *)username
                            path:(NSString *)path
                             job:(NSString *)job {
    double highestScore = 0;
    for (NSString *ruleString in candidate[KEY_BOUND_HOSTS]) {
        iTermRule *rule = [iTermRule ruleWithString:ruleString];
        double score = [rule scoreForHostname:hostname username:username path:path job:job];
        highestScore = MAX(highestScore, score);
    }
    return highestScore;
}

// Search the stack (without modifying it) and return a saved profile that matches the current
// configuration, or nil if none matches.
- (nullable iTermSavedProfile *)topmostSavedProfileMatchingHostname:(NSString *)hostname
                                                           username:(NSString *)username
                                                               path:(NSString *)path
                                                                job:(NSString *)job
                                                              score:(double *)scorePtr {
    for (iTermSavedProfile *savedProfile in [_profileStack reverseObjectEnumerator]) {
        double score = [self highestScoreForProfile:savedProfile.profile hostname:hostname username:username path:path job:job];
        if (score > 0) {
            if (scorePtr) {
                *scorePtr = score;
            }
            return savedProfile;
        }
    }
    return nil;
}

@end

NS_ASSUME_NONNULL_END
