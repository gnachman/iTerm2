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
#import "NSDictionary+iTerm.h"
#import "NSDictionary+Profile.h"

// #define APSLog ELog
#define APSLog DLog

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

- (void)dealloc {
    [_profile release];
    [_originalProfile release];
    [_overriddenFields release];
    [super dealloc];
}

@end

static NSString *const kStackKey = @"Profile Stack";

@implementation iTermAutomaticProfileSwitcher {
    NSMutableArray<iTermSavedProfile *> *_profileStack;
}

- (instancetype)initWithDelegate:(id<iTermAutomaticProfileSwitcherDelegate>)delegate {
    self = [super init];
    if (self) {
        _profileStack = [[NSMutableArray alloc] init];
        _delegate = delegate;
    }
    return self;
}

- (instancetype)initWithDelegate:(id<iTermAutomaticProfileSwitcherDelegate>)delegate
                      savedState:(NSDictionary *)savedState {
    self = [self initWithDelegate:delegate];
    if (self) {
        for (NSDictionary *dict in savedState[kStackKey]) {
            iTermSavedProfile *savedProfile = [[[iTermSavedProfile alloc] initWithSavedState:dict] autorelease];
            if (savedProfile) {
                [_profileStack addObject:savedProfile];
            }
            APSLog(@"Initialized automatic profile switcher %@", self);
        }
    }
    return self;
}

- (void)dealloc {
    [_profileStack release];
    [super dealloc];
}

#pragma mark - APIs

- (void)setHostname:(nullable NSString *)hostname
           username:(nullable NSString *)username
               path:(nullable NSString *)path {
    APSLog(@"APS: hostname=%@, username=%@, path=%@", hostname, username, path);
    iTermSavedProfile *savedProfile = [[[self savedProfileMatchingHostname:hostname
                                                                  username:username
                                                                      path:path] retain] autorelease];
    if (savedProfile && ![savedProfile.originalProfile isEqualToProfile:_delegate.automaticProfileSwitcherCurrentProfile]) {
        APSLog(@"%@ is in the stack and matches. Popping until we remove it", savedProfile.profile[KEY_NAME]);
        while (_profileStack.lastObject.originalProfile == savedProfile.originalProfile) {
            APSLog(@"Pop");
            [_profileStack removeLastObject];
        }
        APSLog(@"Stack is now: %@", self.profileStackString);
        [_delegate automaticProfileSwitcherLoadProfile:savedProfile];
    } else {
        BOOL sticky = NO;
        Profile *profileToSwitchTo = [self profileToSwitchToForHostname:hostname
                                                               username:username
                                                                   path:path
                                                                 sticky:&sticky];
        if (profileToSwitchTo && ![profileToSwitchTo isEqualToProfile:_delegate.automaticProfileSwitcherCurrentProfile]) {
            APSLog(@"Switching to %@", profileToSwitchTo[KEY_NAME]);
            [self pushCurrentProfileIfNeeded];
            
            iTermSavedProfile *newSavedProfile = [[[iTermSavedProfile alloc] init] autorelease];
            newSavedProfile.originalProfile = profileToSwitchTo;
            [_delegate automaticProfileSwitcherLoadProfile:newSavedProfile];
            
            if (sticky) {
                DLog(@"Found a sticky rule so clearing the stack and pushing the new profile");
                [_profileStack removeAllObjects];
                [self pushCurrentProfileIfNeeded];
            }
        } else if (!profileToSwitchTo && _profileStack.count) {
            // Restore first profile in stack
            if (_profileStack.count > 1) {
                APSLog(@"  Removing all but first object in stack");
                [_profileStack removeObjectsInRange:NSMakeRange(1, _profileStack.count - 1)];
            }
            if (![_profileStack.firstObject.originalProfile isEqualToProfile:_delegate.automaticProfileSwitcherCurrentProfile]) {
                APSLog(@"Restoring the stack to the root element: %@", [_profileStack.firstObject profile][KEY_NAME]);
                [_delegate automaticProfileSwitcherLoadProfile:_profileStack.firstObject];
            }
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
- (Profile *)profileToSwitchToForHostname:(NSString *)hostname
                                 username:(NSString *)username
                                     path:(NSString *)path
                                   sticky:(BOOL *)sticky {
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
    int longestHost = 0;
    Profile *bestProfile = nil;

    for (NSString *ruleString in ruleToProfileMap) {
        iTermRule *rule = [iTermRule ruleWithString:ruleString];
        double score = [rule scoreForHostname:hostname username:username path:path];
        if (score > bestScore) {
            bestScore = score;
            longestHost = [rule.hostname length];
            bestProfile = ruleToProfileMap[ruleString];
            if (sticky) {
                *sticky = rule.isSticky;
            }
        }
    }
    return bestProfile;
}

// If the current configuration is not already on the top of the stack, push it.
- (void)pushCurrentProfileIfNeeded {
    if (![_profileStack.lastObject.originalProfile isEqualToProfile:_delegate.automaticProfileSwitcherCurrentProfile]) {
        // Push the current profile state onto the stack if its guid is different that the one
        // already on the stack. This means if you make changes in Edit Info they'll be lost.
        APSLog(@"*** push %@", _delegate.automaticProfileSwitcherCurrentProfile[KEY_NAME]);
        [_profileStack addObject:_delegate.automaticProfileSwitcherCurrentSavedProfile];
        APSLog(@"Stack is now: %@", [self profileStackString]);
    } else {
        APSLog(@"(not pushing %@ because it matches the top of the stack)",
             _delegate.automaticProfileSwitcherCurrentProfile[KEY_NAME]);
    }
}

// Does any rule in |candidate| match the current configuration?
- (BOOL)profile:(Profile *)candidate
    hasRuleMatchingHostname:(NSString *)hostname
           username:(NSString *)username
               path:(NSString *)path {
    for (NSString *ruleString in candidate[KEY_BOUND_HOSTS]) {
        iTermRule *rule = [iTermRule ruleWithString:ruleString];
        if ([rule scoreForHostname:hostname username:username path:path] > 0) {
            return YES;
        }
    }
    return NO;
}

// Search the stack (without modifying it) and return a saved profile that matches the current
// configuration, or nil if none matches.
- (iTermSavedProfile *)savedProfileMatchingHostname:(NSString *)hostname
                                           username:(NSString *)username
                                               path:(NSString *)path {
    for (iTermSavedProfile *savedProfile in [_profileStack reverseObjectEnumerator]) {
        if ([self profile:savedProfile.profile hasRuleMatchingHostname:hostname username:username path:path]) {
            return savedProfile;
        }
    }
    return nil;
}

@end

NS_ASSUME_NONNULL_END
