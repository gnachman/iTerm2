#import "iTermOpenQuicklyModel.h"

#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermColorPresets.h"
#import "iTermController.h"
#import "iTermLogoGenerator.h"
#import "iTermMinimumSubsequenceMatcher.h"
#import "iTermOpenQuicklyCommands.h"
#import "iTermOpenQuicklyItem.h"
#import "iTermScriptsMenuController.h"
#import "iTermVariables.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"
#import "PseudoTerminal.h"
#import "PTYSession+Scripting.h"
#import "VT100RemoteHost.h"
#import "WindowArrangements.h"

// It's nice for each of these to be unique so in degenerate cases (e.g., empty query) the detail
// uses the same feature for all items.
static const double kSessionNameMultiplier = 2;
static const double kSessionBadgeMultiplier = 3;
static const double kCommandMultiplier = 0.8;
static const double kDirectoryMultiplier = 0.9;
static const double kHostnameMultiplier = 1.2;
static const double kUsernameMultiplier = 0.5;
static const double kProfileNameMultiplier = 1;
static const double kUserDefinedVariableMultiplier = 1;

// Multiplier for color preset name. Rank between scripts and profiles.
static const double kProfileNameMultiplierForColorPresetItem = 0.095;

// Multipliers for profile items
static const double kProfileNameMultiplierForProfileItem = 0.1;

// Multipliers for arrangement items. Arrangements rank just above profiles
static const double kProfileNameMultiplierForArrangementItem = 0.11;

// Multipliers for script items. Ranks below profiles.
static const double kProfileNameMultiplierForScriptItem = 0.09;

@implementation iTermOpenQuicklyModel

#pragma mark - Commands

- (NSArray<Class> *)commands {
    static NSArray<Class> *commands;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        commands = @[ [iTermOpenQuicklyWindowArrangementCommand class],
                      [iTermOpenQuicklySearchSessionsCommand class],
                      [iTermOpenQuicklySwitchProfileCommand class],
                      [iTermOpenQuicklyCreateTabCommand class],
                      [iTermOpenQuicklyColorPresetCommand class],
                      [iTermOpenQuicklyScriptCommand class] ];
    });
    return commands;
}

- (Class)commandTypeWithAbbreviation:(NSString *)abbreviation {
    for (Class commandClass in self.commands) {
        if ([[commandClass command] isEqualToString:abbreviation]) {
            return commandClass;
        }
    }
    return nil;
}

- (id<iTermOpenQuicklyCommand>)commandForQuery:(NSString *)queryString {
    if ([queryString hasPrefix:@"/"]) {
        NSRange rangeOfSpace = [queryString rangeOfString:@" "];
        if (rangeOfSpace.location != NSNotFound) {
            NSString *command = [[queryString substringToIndex:rangeOfSpace.location] substringFromIndex:1];
            NSString *text = [queryString substringFromIndex:rangeOfSpace.location + 1];
            Class commandClass = [self commandTypeWithAbbreviation:command];
            if (commandClass) {
                id<iTermOpenQuicklyCommand> theCommand= [[commandClass alloc] init];
                theCommand.text = text;
                return theCommand;
            }
        }
    }
    id<iTermOpenQuicklyCommand> theCommand = [[iTermOpenQuicklyNoCommand alloc] init];
    theCommand.text = queryString;
    return theCommand;
}

#pragma mark - Utilities

// Returns an array of all sessions.
- (NSArray *)sessions {
    NSArray *terminals = [[iTermController sharedInstance] terminals];
    // sessions and scores are parallel.
    NSMutableArray *sessions = [NSMutableArray array];
    for (PseudoTerminal *term in terminals) {
        [sessions addObjectsFromArray:term.allSessions];
    }
    return sessions;
}

#pragma mark - Add Items

- (void)addTipsToItems:(NSMutableArray<iTermOpenQuicklyItem *> *)items {
    for (Class commandClass in self.commands) {
        iTermOpenQuicklyHelpItem *item = [[iTermOpenQuicklyHelpItem alloc] init];
        item.score = 0;
        item.title = [_delegate openQuicklyModelDisplayStringForFeatureNamed:nil
                                                                       value:[commandClass tipTitle]
                                                          highlightedIndexes:nil];
        item.detail = [_delegate openQuicklyModelDisplayStringForFeatureNamed:nil
                                                                        value:[commandClass tipDetail]
                                                           highlightedIndexes:nil];
        item.identifier = [NSString stringWithFormat:@"/%@ ", [commandClass command]];
        [items addObject:item];
    }
}

- (void)addSessionLocationToItems:(NSMutableArray<iTermOpenQuicklyItem *> *)items
                    withMatcher:(iTermMinimumSubsequenceMatcher *)matcher {
    for (PTYSession *session in self.sessions) {
        NSMutableArray *features = [NSMutableArray array];
        iTermOpenQuicklySessionItem *item = [[iTermOpenQuicklySessionItem alloc] init];
        item.logoGenerator.textColor = session.foregroundColor;
        item.logoGenerator.backgroundColor = session.backgroundColor;
        item.logoGenerator.tabColor = session.tabColor;
        item.logoGenerator.cursorColor = session.cursorColor;

        NSMutableAttributedString *attributedName = [[NSMutableAttributedString alloc] init];
        item.score = [self scoreForSession:session
                                   matcher:matcher
                                  features:features
                            attributedName:attributedName];
        if (item.score > 0) {
            item.detail = [self detailForSession:session features:features];
            if (attributedName.length) {
                item.title = attributedName;
            } else {
                item.title = [_delegate openQuicklyModelDisplayStringForFeatureNamed:nil
                                                                               value:session.name
                                                                  highlightedIndexes:nil];
            }

            item.identifier = session.guid;
            [items addObject:item];
        }
    }
}

- (void)addCreateNewTabToItems:(NSMutableArray<iTermOpenQuicklyItem *> *)items
                   withMatcher:(iTermMinimumSubsequenceMatcher *)matcher
             haveCurrentWindow:(BOOL)haveCurrentWindow {
    for (Profile *profile in [[ProfileModel sharedInstance] bookmarks]) {
        iTermOpenQuicklyProfileItem *newSessionWithProfileItem = [[iTermOpenQuicklyProfileItem alloc] init];
        NSMutableAttributedString *attributedName = [[NSMutableAttributedString alloc] init];
        newSessionWithProfileItem.score = [self scoreForProfile:profile matcher:matcher attributedName:attributedName];
        if (newSessionWithProfileItem.score > 0) {
            NSString *theValue;
            if (!haveCurrentWindow || [profile[KEY_PREVENT_TAB] boolValue]) {
                theValue = @"Create a new window with this profile";
            } else {
                theValue = @"Create a new tab with this profile";
            }
            newSessionWithProfileItem.detail = [_delegate openQuicklyModelDisplayStringForFeatureNamed:nil
                                                                                                 value:theValue
                                                                                    highlightedIndexes:nil];
            newSessionWithProfileItem.title = attributedName;
            newSessionWithProfileItem.identifier = profile[KEY_GUID];
            [items addObject:newSessionWithProfileItem];
        }
    }
}

- (void)addChangeColorPresetToItems:(NSMutableArray<iTermOpenQuicklyItem *> *)items
                        withMatcher:(iTermMinimumSubsequenceMatcher *)matcher {
    iTermColorPresetDictionary *allPresets = [iTermColorPresets allColorPresets];
    NSColor *defaultColor = [NSColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1];
    for (NSString *name in allPresets) {
        iTermColorPreset *preset = allPresets[name];
        
        iTermOpenQuicklyColorPresetItem *item = [[iTermOpenQuicklyColorPresetItem alloc] init];
        item.presetName = name;
        item.logoGenerator.textColor = [preset[KEY_FOREGROUND_COLOR] colorValue];
        item.logoGenerator.backgroundColor = [preset[KEY_BACKGROUND_COLOR] colorValue];
        item.logoGenerator.tabColor = [preset[KEY_TAB_COLOR] colorValue] ?: defaultColor;
        item.logoGenerator.cursorColor = [preset[KEY_CURSOR_COLOR] colorValue] ?: defaultColor;

        NSMutableAttributedString *attributedName = [[NSMutableAttributedString alloc] init];
        item.score = [self scoreForColorPreset:name matcher:matcher attributedName:attributedName];
        if (item.score > 0) {
            NSString *value = [NSString stringWithFormat:@"Load color preset ”%@“", name];
            item.detail = [_delegate openQuicklyModelDisplayStringForFeatureNamed:nil
                                                                            value:value
                                                               highlightedIndexes:nil];
            item.title = attributedName;
            item.identifier = name;
            [items addObject:item];
        }
    }
}

- (void)addChangeProfileToItems:(NSMutableArray<iTermOpenQuicklyItem *> *)items
                    withMatcher:(iTermMinimumSubsequenceMatcher *)matcher {
    for (Profile *profile in [[ProfileModel sharedInstance] bookmarks]) {
        iTermOpenQuicklyChangeProfileItem *changeProfileItem = [[iTermOpenQuicklyChangeProfileItem alloc] init];
        NSMutableAttributedString *attributedName = [[NSMutableAttributedString alloc] init];
        changeProfileItem.score = [self scoreForProfile:profile matcher:matcher attributedName:attributedName];
        if (changeProfileItem.score > 0) {
            changeProfileItem.detail = [_delegate openQuicklyModelDisplayStringForFeatureNamed:nil
                                                                                         value:@"Change current session’s profile"
                                                                            highlightedIndexes:nil];
            changeProfileItem.title = attributedName;
            changeProfileItem.identifier = profile[KEY_GUID];
            [items addObject:changeProfileItem];
        }
    }
}

- (iTermOpenQuicklyArrangementItem *)arrangementItemWithName:(NSString *)arrangementName
                                                     matcher:(iTermMinimumSubsequenceMatcher *)matcher
                                                      inTabs:(BOOL)inTabs {
    iTermOpenQuicklyArrangementItem *item = [[iTermOpenQuicklyArrangementItem alloc] init];
    NSMutableAttributedString *attributedName = [[NSMutableAttributedString alloc] init];
    item.score = [self scoreForArrangementWithName:arrangementName
                                           matcher:matcher
                                    attributedName:attributedName];
    if (item.score > 0) {
        item.inTabs = inTabs;
        item.detail = [_delegate openQuicklyModelDisplayStringForFeatureNamed:nil
                                                                        value:inTabs ? @"Restore window arrangement in tabs" : @"Restore window arrangement"
                                                           highlightedIndexes:nil];
        item.title = attributedName;
        item.identifier = arrangementName;
        return item;
    } else {
        return nil;
    }
}

- (iTermOpenQuicklyScriptItem *)scriptItemWithName:(NSString *)scriptName
                                           matcher:(iTermMinimumSubsequenceMatcher *)matcher {
    iTermOpenQuicklyScriptItem *item = [[iTermOpenQuicklyScriptItem alloc] init];
    NSMutableAttributedString *attributedName = [[NSMutableAttributedString alloc] init];
    item.score = [self scoreForScriptWithName:scriptName
                                      matcher:matcher
                               attributedName:attributedName];
    if (item.score > 0) {
        item.detail = [_delegate openQuicklyModelDisplayStringForFeatureNamed:nil
                                                                        value:@"Run Script"
                                                           highlightedIndexes:nil];
        item.title = attributedName;
        item.identifier = scriptName;
        return item;
    } else {
        return nil;
    }
}

- (void)addOpenArrangementToItems:(NSMutableArray<iTermOpenQuicklyItem *> *)items
                      withMatcher:(iTermMinimumSubsequenceMatcher *)matcher {
    for (NSString *arrangementName in [WindowArrangements allNames]) {
        iTermOpenQuicklyArrangementItem *item;
        item = [self arrangementItemWithName:arrangementName matcher:matcher inTabs:NO];
        if (item) {
            [items addObject:item];
        }
        item = [self arrangementItemWithName:arrangementName matcher:matcher inTabs:YES];
        if (item) {
            [items addObject:item];
        }
    }
}

- (void)addScriptToItems:(NSMutableArray<iTermOpenQuicklyItem *> *)items
             withMatcher:(iTermMinimumSubsequenceMatcher *)matcher {
    NSArray<NSString *> *allScripts = [[[[iTermApplication sharedApplication] delegate] scriptsMenuController] allScripts];
    for (NSString *script in allScripts) {
        iTermOpenQuicklyScriptItem *item;
        item = [self scriptItemWithName:script matcher:matcher];
        if (item) {
            [items addObject:item];
        }
    }
}

#pragma mark - APIs

- (void)removeAllItems {
    [_items removeAllObjects];
}

- (void)updateWithQuery:(NSString *)queryString {
    id<iTermOpenQuicklyCommand> command = [self commandForQuery:[queryString lowercaseString]];

    iTermMinimumSubsequenceMatcher *matcher =
        [[iTermMinimumSubsequenceMatcher alloc] initWithQuery:command.text];

    NSMutableArray *items = [NSMutableArray array];

    if ([queryString isEqualToString:@"/"]) {
        [self addTipsToItems:items];
    }

    if ([command supportsSessionLocation]) {
        [self addSessionLocationToItems:items withMatcher:matcher];
    }

    BOOL haveCurrentWindow = [[iTermController sharedInstance] currentTerminal] != nil;
    if ([command supportsCreateNewTab]) {
        [self addCreateNewTabToItems:items withMatcher:matcher haveCurrentWindow:haveCurrentWindow];
    }
    if ([command supportsChangeProfile] && haveCurrentWindow) {
        [self addChangeProfileToItems:items withMatcher:matcher];
    }

    if ([command supportsOpenArrangement]) {
        [self addOpenArrangementToItems:items withMatcher:matcher];
    }

    if ([command supportsScript]) {
        [self addScriptToItems:items withMatcher:matcher];
    }
    if ([command supportsColorPreset] && haveCurrentWindow) {
        [self addChangeColorPresetToItems:items withMatcher:matcher];
    }

    // Sort from highest to lowest score.
    [items sortUsingComparator:^NSComparisonResult(iTermOpenQuicklyItem *obj1,
                                                   iTermOpenQuicklyItem *obj2) {
        return [@(obj2.score) compare:@(obj1.score)];
    }];

    // To avoid performance issues, only keep the 100 best.
    static const int kMaxItems = 100;
    if (items.count > kMaxItems) {
        [items removeObjectsInRange:NSMakeRange(kMaxItems, items.count - kMaxItems)];
    }

    // Replace self.items with new items.
    self.items = items;
}

- (id)objectAtIndex:(NSInteger)index {
    iTermOpenQuicklyItem *item = _items[index];
    if ([item isKindOfClass:[iTermOpenQuicklyProfileItem class]]) {
        return [[ProfileModel sharedInstance] bookmarkWithGuid:item.identifier];
    } else if ([item isKindOfClass:[iTermOpenQuicklyChangeProfileItem class]] ||
               [item isKindOfClass:[iTermOpenQuicklyHelpItem class]]) {
        return item;
    } else if ([item isKindOfClass:[iTermOpenQuicklyArrangementItem class]]) {
        return item;
    } else if ([item isKindOfClass:[iTermOpenQuicklySessionItem class]]) {
        NSString *guid = item.identifier;
        for (PTYSession *session in [self sessions]) {
            if ([session.guid isEqualTo:guid]) {
                return session;
            }
        }
    } else if ([item isKindOfClass:[iTermOpenQuicklyScriptItem class]]) {
        return item;
    } else if ([item isKindOfClass:[iTermOpenQuicklyColorPresetItem class]]) {
        return item;
    }
    return nil;
}

#pragma mark - Scoring

- (double)scoreForArrangementWithName:(NSString *)arrangementName
                              matcher:(iTermMinimumSubsequenceMatcher *)matcher
                       attributedName:(NSMutableAttributedString *)attributedName {
    NSMutableArray *nameFeature = [NSMutableArray array];
    double score = [self scoreUsingMatcher:matcher
                                 documents:@[ arrangementName ?: @"" ]
                                multiplier:kProfileNameMultiplierForArrangementItem
                                      name:nil
                                  features:nameFeature
                                     limit:2 * kProfileNameMultiplierForArrangementItem];
    if (score > 0 &&
        [[WindowArrangements defaultArrangementName] isEqualToString:arrangementName]) {
        // Make the default arrangement always be the highest-scored arrangement if it matches the query.
        score += 0.2;
    }
    if (nameFeature.count) {
        [attributedName appendAttributedString:nameFeature[0][0]];
    }
    return score;
}

- (double)scoreForScriptWithName:(NSString *)arrangementName
                         matcher:(iTermMinimumSubsequenceMatcher *)matcher
                  attributedName:(NSMutableAttributedString *)attributedName {
    NSMutableArray *nameFeature = [NSMutableArray array];
    double score = [self scoreUsingMatcher:matcher
                                 documents:@[ arrangementName ?: @"" ]
                                multiplier:kProfileNameMultiplierForScriptItem
                                      name:nil
                                  features:nameFeature
                                     limit:2 * kProfileNameMultiplierForScriptItem];
    if (nameFeature.count) {
        [attributedName appendAttributedString:nameFeature[0][0]];
    }
    return score;
}

- (double)scoreForColorPreset:(NSString *)presetName
                      matcher:(iTermMinimumSubsequenceMatcher *)matcher
               attributedName:(NSMutableAttributedString *)attributedName {
    NSMutableArray *nameFeature = [NSMutableArray array];
    double score = [self scoreUsingMatcher:matcher
                                 documents:@[ presetName ]
                                multiplier:kProfileNameMultiplierForColorPresetItem
                                      name:nil
                                  features:nameFeature
                                     limit:2 * kProfileNameMultiplierForColorPresetItem];
    if (nameFeature.count) {
        [attributedName appendAttributedString:nameFeature[0][0]];
    }
    return score;
}

- (double)scoreForProfile:(Profile *)profile
                  matcher:(iTermMinimumSubsequenceMatcher *)matcher
           attributedName:(NSMutableAttributedString *)attributedName {
    NSMutableArray *nameFeature = [NSMutableArray array];
    double score = [self scoreUsingMatcher:matcher
                                 documents:@[ profile[KEY_NAME] ]
                                multiplier:kProfileNameMultiplierForProfileItem
                                      name:nil
                                  features:nameFeature
                                     limit:2 * kProfileNameMultiplierForProfileItem];
    if (score > 0 &&
        [[[ProfileModel sharedInstance] defaultBookmark][KEY_GUID] isEqualToString:profile[KEY_GUID]]) {
        // Make the default profile always be the highest-scored profile if it matches the query.
        score += 0.2;
    }
    if (nameFeature.count) {
        [attributedName appendAttributedString:nameFeature[0][0]];
    }
    return score;
}

// Returns the score for a session.
// session: The session to score against a query
// query: The search query (null terminate)
// length: The length of the query array
// features: An array that will be populated with tuples of (detail, score).
//   The detail element is a suitable-for-display NSAttributedString*s
//   describing features that matched the query, while the score element is the
//   score assigned to that feature.
// attributedName: The session's name with matching characters highlighted
//   (suitable for display) will be appended to this NSMutableAttributedString.
- (double)scoreForSession:(PTYSession *)session
                  matcher:(iTermMinimumSubsequenceMatcher *)matcher
                 features:(NSMutableArray *)features
           attributedName:(NSMutableAttributedString *)attributedName {
    double score = 0;
    double maxScorePerFeature = 2 + matcher.query.length / 4;
    if (session.name) {
        NSMutableArray *nameFeature = [NSMutableArray array];
        score += [self scoreUsingMatcher:matcher
                               documents:@[ session.name ]
                              multiplier:kSessionNameMultiplier
                                    name:nil
                                features:nameFeature
                                   limit:maxScorePerFeature];
        if (nameFeature.count) {
            [attributedName appendAttributedString:nameFeature[0][0]];
        }
    }

    if (session.badgeLabel) {
        score += [self scoreUsingMatcher:matcher
                               documents:@[ session.badgeLabel ]
                              multiplier:kSessionBadgeMultiplier
                                    name:@"Badge"
                                features:features
                                   limit:maxScorePerFeature];
    }

    score += [self scoreUsingMatcher:matcher
                           documents:session.commands
                          multiplier:kCommandMultiplier
                                name:@"Command"
                            features:features
                               limit:maxScorePerFeature];

    score += [self scoreUsingMatcher:matcher
                           documents:session.directories
                          multiplier:kDirectoryMultiplier
                                name:@"Directory"
                            features:features
                               limit:maxScorePerFeature];

    score += [self scoreUsingMatcher:matcher
                           documents:[self hostnamesInHosts:session.hosts]
                          multiplier:kHostnameMultiplier
                                name:@"Host"
                            features:features
                               limit:maxScorePerFeature];

    score += [self scoreUsingMatcher:matcher
                           documents:[self usernamesInHosts:session.hosts]
                          multiplier:kUsernameMultiplier
                                name:@"User"
                            features:features
                               limit:maxScorePerFeature];

    score += [self scoreUsingMatcher:matcher
                           documents:@[ session.originalProfile[KEY_NAME] ?: @"" ]
                          multiplier:kProfileNameMultiplier
                                name:@"Profile"
                            features:features
                               limit:maxScorePerFeature];

    NSDictionary<NSString *, NSString *> *userVariablesDict = [[session.variables discouragedValueForVariableName:@"user"] stringValuedDictionary];
    for (NSString *name in userVariablesDict) {
        score += [self scoreUsingMatcher:matcher
                               documents:@[ userVariablesDict[name] ]
                              multiplier:kUserDefinedVariableMultiplier
                                    name:name
                                features:features
                                   limit:maxScorePerFeature];
    }

    // TODO: add a bonus for:
    // Doing lots of typing in a session
    // Being newly created
    // Recency of use

    return score;
}

// Given an array of features which are a tuple of (detail, score), return the
// detail for the highest scoring one.
- (NSAttributedString *)detailForSession:(PTYSession *)session features:(NSArray *)features {
    NSArray *sorted = [features sortedArrayUsingComparator:^NSComparisonResult(NSArray *tuple1, NSArray *tuple2) {
        NSNumber *score1 = tuple1[1];
        NSNumber *score2 = tuple2[1];
        return [score1 compare:score2];
    }];
    return [sorted lastObject][0];
}

// Returns the total score for a query matching an array of documents. This
// should be called once per feature.
// query: The user-entered query
// documents: An array of NSString*s to search, ordered from least recent to
//   most recent (less recent documents have their scores heavily discounted)
// multiplier: The sum of the documents' scores is multiplied by this value.
// name: The display name of the current feature.
// features: The highest-scoring document will have an NSAttributedString added
//   to this array describing the match, suitable for display.
// limit: Upper bound for the returned score.
- (double)scoreUsingMatcher:(iTermMinimumSubsequenceMatcher *)matcher
                  documents:(NSArray *)documents
                 multiplier:(double)multipler
                       name:(NSString *)name
                   features:(NSMutableArray *)features
                      limit:(double)limit {
    if (multipler == 0) {
        // Feature is disabled. In the future, we might let users tweak multipliers.
        return 0;
    }
    if (matcher.query.length == 0) {
        // Trivially matches every document.
        double score = 0.01;
        for (NSString *document in documents) {
            if (features) {
                id displayString = [_delegate openQuicklyModelDisplayStringForFeatureNamed:name
                                                                                     value:document
                                                                        highlightedIndexes:[NSIndexSet indexSet]];
                [features addObject:@[ displayString, @(score) ]];
            }
        }
        return score;
    }
    double score = 0;
    double highestValue = 0;
    NSString *bestFeature = nil;
    NSIndexSet *bestIndexSet = nil;
    int n = documents.count;
    NSMutableIndexSet *indexSet = [NSMutableIndexSet indexSet];
    for (NSString *document in documents) {
        [indexSet removeAllIndexes];
        double value = [self qualityOfMatchWithMatcher:matcher
                                              document:[document lowercaseString]
                                              indexSet:indexSet];

        // Discount older documents (which appear at the beginning of the list)
        value /= n;
        n--;

        if (value > highestValue) {
            highestValue = value;
            bestFeature = document;
            bestIndexSet = [indexSet copy];
        }
        score += value * multipler;
        if (score > limit) {
            break;
        }
    }

    if (bestFeature && features) {
        id displayString = [_delegate openQuicklyModelDisplayStringForFeatureNamed:name
                                                                             value:bestFeature
                                                                highlightedIndexes:bestIndexSet];
        [features addObject:@[ displayString, @(score) ]];
    }

    return MIN(limit, score);
}

// Returns a value between 0 and 1 for how well a query matches a document.
// The passed-in indexSet will be populated with indices into documentString
// that were found to match query.
// The current implementation returns:
//   1.0 if query equals document.
//   0.9 if query is a prefix of document.
//   0.5 if query is a substring of document
//   0 < score < 0.5 if query is a subsequence of a document. Each gap of non-matching characters
//       increases the penalty.
//   0.0 otherwise
- (double)qualityOfMatchWithMatcher:(iTermMinimumSubsequenceMatcher *)matcher
                           document:(NSString *)documentString
                           indexSet:(NSMutableIndexSet *)indexSet {
    [indexSet addIndexes:[matcher indexSetForDocument:documentString]];

    double score;
    if (!indexSet.count) {
        // No match
        score = 0;
    } else if (indexSet.firstIndex == 0 && indexSet.lastIndex == documentString.length - 1) {
        // Exact equality
        score = 1;
    } else if (indexSet.firstIndex == 0) {
        // Is a prefix
        score = 0.9;
    } else {
        score = 0.5 / ([self numberOfGapsInIndexSet:indexSet] + 1);
    }

    return score;
}

- (NSInteger)numberOfGapsInIndexSet:(NSIndexSet *)indexSet {
    __block NSInteger numRanges = 0;
    [indexSet enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
        ++numRanges;
    }];
    return numRanges - 1;
}

#pragma mark - Feature Extraction

// Returns an array of hostnames from an array of VT100RemoteHost*s
- (NSArray *)hostnamesInHosts:(NSArray *)hosts {
    NSMutableArray *names = [NSMutableArray array];
    for (VT100RemoteHost *host in hosts) {
        [names addObject:host.hostname];
    }
    return names;
}

// Returns an array of usernames from an array of VT100RemoteHost*s
- (NSArray *)usernamesInHosts:(NSArray *)hosts {
    NSMutableArray *names = [NSMutableArray array];
    for (VT100RemoteHost *host in hosts) {
        [names addObject:host.username];
    }
    return names;
}

@end
