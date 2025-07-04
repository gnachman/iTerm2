#import "iTermOpenQuicklyModel.h"

#import "iTerm2SharedARC-Swift.h"
#import "iTermActionsModel.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermColorPresets.h"
#import "iTermController.h"
#import "iTermExpressionParser.h"
#import "iTermGitPollWorker.h"
#import "iTermHotKeyController.h"
#import "iTermLogoGenerator.h"
#import "iTermMinimumSubsequenceMatcher.h"
#import "iTermOpenQuicklyCommands.h"
#import "iTermOpenQuicklyItem.h"
#import "iTermProfileHotKey.h"
#import "iTermScriptFunctionCall.h"
#import "iTermScriptsMenuController.h"
#import "iTermSnippetsModel.h"
#import "iTermVariableScope.h"
#import "iTermVariableScope+Global.h"
#import "iTermVariableScope+Session.h"
#import "iTermVariableScope+Tab.h"
#import "NSAppearance+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSScreen+iTerm.h"
#import "NSStringITerm.h"
#import "PseudoTerminal.h"
#import "PTYSession+Scripting.h"
#import "VT100RemoteHost.h"
#import "WindowArrangements.h"

// It's nice for each of these to be unique so in degenerate cases (e.g., empty query) the detail
// uses the same feature for all items.
static const double kMultiplierForURLItem = 6;
static const double kInvocationMultiplier = 5;
static const double kSessionBadgeMultiplier = 3;
static const double kSessionNameMultiplier = 2;
static const double kGitBranchMultiplier = 1.5;
static const double kHostnameMultiplier = 1.2;
static const double kProfileNameMultiplier = 1.01;
static const double kUserDefinedVariableMultiplier = 1;
static const double kDirectoryMultiplier = 0.9;
static const double kCommandMultiplier = 0.8;
static const double kUsernameMultiplier = 0.5;

// Variables like tty and job pid.
static const double kOtherVariableMultiplier = 0.4;

// Action items (as defined in Prefs > Shortcuts > Snippets)
static const double kActionMultiplier = 0.4;

// Snippet items (as defined in Prefs > Shortcuts > Snippets)
static const double kSnippetMultiplier = 0.3;

// Named Marks
static const double kNamedMarkMultiplier = 0.5;

// Menu items
static const double kMenuItemMultiplier = 0.2;

// Multipliers for arrangement items. Arrangements rank just above profiles
static const double kProfileNameMultiplierForArrangementItem = 0.11;

// Multipliers for profile items
static const double kProfileNameMultiplierForProfileItem = 0.1;

// Browser bookmarks
static const double kProfileNameMultiplierForBookmarkItem = 0.097;

// Multiplier for color preset name. Rank between scripts and profiles.
static const double kProfileNameMultiplierForColorPresetItem = 0.095;

// Multipliers for script items. Ranks below profiles.
static const double kProfileNameMultiplierForScriptItem = 0.09;

// Multipliers for windows items. Windows rank below scripts since it's a redundant feature.
static const double kProfileNameMultiplierForWindowItem = 0.08;

@implementation iTermOpenQuicklyModel

#pragma mark - Commands

- (NSArray<Class> *)commands {
    static NSArray<Class> *commands;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        commands = @[ [iTermOpenQuicklyInTabsWindowArrangementCommand class],
                      [iTermOpenQuicklyWindowArrangementCommand class],
                      [iTermOpenQuicklySearchSessionsCommand class],
                      [iTermOpenQuicklySwitchProfileCommand class],
                      [iTermOpenQuicklySearchWindowsCommand class],
                      [iTermOpenQuicklyCreateTabCommand class],
                      [iTermOpenQuicklyColorPresetCommand class],
                      [iTermOpenQuicklyScriptCommand class],
                      [iTermOpenQuicklyActionCommand class],
                      [iTermOpenQuicklySnippetCommand class],
                      [iTermOpenQuicklyBookmarkCommand class]];
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
    if ([queryString hasPrefix:@"/"] && queryString.length > 1) {
        NSString *command = [queryString substringWithRange:NSMakeRange(1, 1)];
        NSString *text = [[queryString substringFromIndex:2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        Class commandClass = [self commandTypeWithAbbreviation:command];
        if (commandClass) {
            id<iTermOpenQuicklyCommand> theCommand = [[commandClass alloc] init];
            theCommand.text = text;
            return theCommand;
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

- (NSString *)documentForSession:(PTYSession *)session {
    NSString *sessionName = session.name.removingHTMLFromTabTitleIfNeeded;
    NSString *tabTitle = session.variablesScope.tab.tabTitleOverride;
    NSString *tmuxWindowName = session.variablesScope.tab.tmuxWindowName;
    if (tabTitle.length == 0) {
        tabTitle = tmuxWindowName;
    }
    if (tabTitle.length == 0) {
        return sessionName;
    }
    if ([tabTitle containsString:sessionName]) {
        return tabTitle;
    } else {
        return [NSString stringWithFormat:@"%@ — %@", tabTitle, sessionName];
    }
}

- (NSString *)documentForWindow:(PseudoTerminal *)term {
    return term.window.title ?: @"";
}

// Returns a function PTYSession -> (Feature name, Feature value) that gives the value which most distinguishes sessions from one another.
- (iTermTuple<NSString *, NSString *> *(^)(PTYSession *))detailFunctionForSessions:(NSArray<PTYSession *> *)sessions {
    iTermTriple<NSString *, NSString *, NSNumber *> *(^pwd)(PTYSession *) = ^id(PTYSession *session) {
        return [iTermTriple tripleWithObject:@"Directory"
                                   andObject:session.variablesScope.path
                                   object:@(session.variablesScope.path.length > 0)];
    };
    iTermTriple<NSString *, NSString *, NSNumber *> *(^command)(PTYSession *) = ^id(PTYSession *session) {
        return [iTermTriple tripleWithObject:@"Command"
                                   andObject:session.commands.lastObject
                                   object:@(session.commands.lastObject.length > 0)];
    };
    iTermTriple<NSString *, NSString *, NSNumber *> *(^hostname)(PTYSession *) = ^id(PTYSession *session) {
        return [iTermTriple tripleWithObject:@"Host"
                                   andObject:session.currentHost.usernameAndHostname
                                   object:@(session.currentHost != nil)];
    };
    iTermTriple<NSString *, NSString *, NSNumber *> *(^badge)(PTYSession *) = ^id(PTYSession *session) {
        return [iTermTriple tripleWithObject:@"Badge"
                                   andObject:session.badgeLabel
                                   object:@(session.badgeLabel.length > 0)];
    };
    iTermTriple<NSString *, NSString *, NSNumber *> *(^webSite)(PTYSession *) = ^id(PTYSession *session) {
        return [iTermTriple tripleWithObject:@"Web Site"
                                   andObject:session.webSiteTitle ?: @""
                                      object:@(session.webSiteTitle.length > 0)];
    };

    // functions and functionValues are parallel arrays.
    NSArray<iTermTriple<NSString *, NSString *, NSNumber *>  *(^)(PTYSession *)> *functions = @[ pwd, command, hostname, badge ];
    if ([iTermAdvancedSettingsModel browserProfiles]) {
        functions = [functions arrayByAddingObject:webSite];
    }
    NSMutableArray<NSMutableArray *> *functionValues = [NSMutableArray array];
    [functions enumerateObjectsUsingBlock:^(iTermTriple<NSString *, NSString *, NSNumber *>  *(^ _Nonnull obj)(PTYSession *), NSUInteger idx, BOOL * _Nonnull stop) {
        [functionValues addObject:[NSMutableArray array]];
    }];
    [sessions enumerateObjectsUsingBlock:^(PTYSession * _Nonnull session, NSUInteger sessionIndex, BOOL * _Nonnull stop) {
        [functions enumerateObjectsUsingBlock:^(iTermTriple<NSString *, NSString *, NSNumber *>  *(^ _Nonnull f)(PTYSession *), NSUInteger functionIndex, BOOL * _Nonnull stop) {
            iTermTriple<NSString *, NSString *, NSNumber *>  *value = f(session);
            if (value) {
                [functionValues[functionIndex] addObject:value];
            }
        }];
    }];

    // indexes is the set of indexes that have values for all sessions.
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    [functionValues enumerateObjectsUsingBlock:^(NSMutableArray * _Nonnull values, NSUInteger idx, BOOL * _Nonnull stop) {
        if (values.count == sessions.count) {
            [indexes addIndex:idx];
        }
    }];

    // filteredFunction[Value]s is those functions and values that are usable by all sessions
    NSMutableArray<iTermTriple<NSString *, NSString *, NSNumber *>  *(^)(PTYSession *)> *filteredFunctions = [NSMutableArray array];
    NSMutableArray<NSMutableArray *> *filteredFunctionValues = [NSMutableArray array];
    [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        [filteredFunctions addObject:functions[idx]];
        [filteredFunctionValues addObject:functionValues[idx]];
    }];
    double (^variance)(NSArray<iTermTriple<NSString *, NSString *, NSNumber *>  *> *) = ^double(NSArray<iTermTriple<NSString *, NSString *, NSNumber *>  *> *tuples) {
        NSSet<NSString *> *set = [NSSet setWithArray:[tuples mapWithBlock:^id _Nonnull(iTermTuple<NSString *,NSString *> * _Nonnull tuple) {
            return tuple.secondObject;
        }]];
        return set.count;
    };

    // Indexes into filteredFunction[Value]s sorted by variance. The functions at the end of the list discriminate sessions better.
    NSArray<NSNumber *> *sortedIndexes = [NSArray sequenceWithRange:NSMakeRange(0, filteredFunctionValues.count)];
    sortedIndexes = [sortedIndexes sortedArrayUsingComparator:^NSComparisonResult(NSNumber *li, NSNumber *ri) {
        NSMutableArray<iTermTriple<NSString *, NSString *, NSNumber *>  *> *obj1 = filteredFunctionValues[li.unsignedIntegerValue];
        NSMutableArray<iTermTriple<NSString *, NSString *, NSNumber *>  *> *obj2 = filteredFunctionValues[ri.unsignedIntegerValue];
        return [@(variance(obj1)) compare:@(variance(obj2))];
    }];
    if (sortedIndexes.count == 0) {
        return nil;
    }

    // Return a function that can be called with a session to get its description.
    return ^id(PTYSession *session) {
        for (NSNumber *i in sortedIndexes.reversed) {
            iTermTriple<NSString *, NSString *, NSNumber *> *candidate = filteredFunctions[i.unsignedIntegerValue](session);
            if (candidate.thirdObject.boolValue) {
                // The value for this session is valid.
                return [iTermTuple tupleWithObject:candidate.firstObject
                                         andObject:candidate.secondObject];
            }
        }
        return nil;
    };
}

- (void)addSessionLocationToItems:(NSMutableArray<iTermOpenQuicklyItem *> *)items
                    withMatcher:(iTermMinimumSubsequenceMatcher *)matcher {
    // (feature name, display string)
    iTermTuple<NSString *, NSString *> *(^detailFunction)(PTYSession *) = [self detailFunctionForSessions:self.sessions];

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
            iTermTuple<NSString *, NSAttributedString *> *detail = [self detailForSession:session features:features];
            // "Feature: value" giving why this session was recalled.
            item.detail = detail.secondObject;
            if (attributedName.length) {
                item.title = attributedName;
            } else {
                item.title = [_delegate openQuicklyModelDisplayStringForFeatureNamed:nil
                                                                               value:[self documentForSession:session]
                                                                  highlightedIndexes:nil];
            }

            item.identifier = session.guid;
            if (detailFunction) {
                iTermTuple<NSString *, NSString *> *detailTuple = detailFunction(session);
                if (detailTuple) {
                    // "Feature: value" giving identifying info about this session to distinguish it from others. Query-independent.
                    NSAttributedString *refinement =
                    [self.delegate openQuicklyModelAttributedStringForDetail:detailTuple.secondObject
                                                                 featureName:detailTuple.firstObject];
                    if (![detailTuple.firstObject isEqual:detail.firstObject] && item.detail != nil) {
                        NSMutableAttributedString *temp = [item.detail mutableCopy];
                        NSAttributedString *emdash = [[NSAttributedString alloc] initWithString:@" — "
                                                                                     attributes:[item.detail attributesAtIndex:0 effectiveRange:nil]];
                        [temp appendAttributedString:emdash];
                        [temp appendAttributedString:refinement];
                        item.detail = temp;
                    } else {
                        item.detail = refinement;
                    }
                }
            }
            [items addObject:item];
        }
    }
}

- (iTermOpenQuicklyMenuItem *)itemForMenuItem:(NSMenuItem *)menuItem
                                      matcher:(iTermMinimumSubsequenceMatcher *)matcher
                                         path:(NSArray<NSString *> *)path {
    if (!menuItem.isEnabled || menuItem.isHidden || menuItem.isSeparatorItem) {
        return nil;
    }
    iTermOpenQuicklyMenuItem *item = [[iTermOpenQuicklyMenuItem alloc] init];
    NSMutableAttributedString *attributedName = [[NSMutableAttributedString alloc] init];
    item.score = [self scoreForMenuItem:menuItem
                                matcher:matcher
                         attributedName:attributedName];
    if (item.score <= 0) {
        return nil;
    }
    item.title = attributedName;
    item.identifier = menuItem.identifier ?: [[NSUUID UUID] UUIDString];
    item.menuItem = menuItem;

    NSDictionary *regularAttributes = @{ NSParagraphStyleAttributeName: NSParagraphStyle.defaultParagraphStyle };
    NSDictionary *boldAttributes = @{
        NSParagraphStyleAttributeName: NSParagraphStyle.defaultParagraphStyle,
        NSFontAttributeName: [NSFont boldSystemFontOfSize:[NSFont systemFontSize]]
    };
    NSMutableAttributedString *detail =
        [[NSMutableAttributedString alloc] initWithString:@"Menu item under "
                                               attributes:regularAttributes];
    NSString *combinedPath = [path componentsJoinedByString:@" > "];
    NSAttributedString *breadcrumbs = [[NSAttributedString alloc] initWithString:combinedPath
                                                                      attributes:boldAttributes];
    [detail appendAttributedString:breadcrumbs];
    item.detail = detail;

    return item;
}

- (iTermOpenQuicklyNamedMarkItem *)itemForNamedMark:(id<iTermGenericNamedMarkReading>)namedMark
                                          inSession:(PTYSession *)session
                                            matcher:(iTermMinimumSubsequenceMatcher *)matcher {
    iTermOpenQuicklyNamedMarkItem *item = [[iTermOpenQuicklyNamedMarkItem alloc] init];
    item.session = session;
    item.namedMark = namedMark;

    NSMutableAttributedString *attributedName = [[NSMutableAttributedString alloc] init];
    item.score = [self scoreForNamedMark:namedMark
                                 matcher:matcher
                          attributedName:attributedName
                         inActiveSession:session == [[iTermController sharedInstance] currentTerminal].currentSession];
    if (item.score <= 0) {
        return nil;
    }
    item.detail = [_delegate openQuicklyModelDisplayStringForFeatureNamed:nil
                                                                    value:[NSString stringWithFormat:@"Named mark “%@”", namedMark.name]
                                                       highlightedIndexes:nil];
    item.title = attributedName;
    item.identifier = namedMark.guid;
    return item;
}

- (void)addWindowLocationToItems:(NSMutableArray<iTermOpenQuicklyItem *> *)items
                     withMatcher:(iTermMinimumSubsequenceMatcher *)matcher {
    const BOOL multipleDisplays = [[NSScreen screens] count] > 1;
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {{
        iTermOpenQuicklyWindowItem *item = [[iTermOpenQuicklyWindowItem alloc] init];
        NSMutableAttributedString *attributedName = [[NSMutableAttributedString alloc] init];
        item.score = [self scoreForWindow:term
                                  matcher:matcher
                           attributedName:attributedName];
        if (item.score > 0) {
            NSMutableArray<NSString *> *features = [NSMutableArray array];
            if (multipleDisplays) {
                NSString *name = [term.window.screen it_uniqueName];
                if (name) {
                    [features addObject:[NSString stringWithFormat:@"On %@", name]];
                } else {
                    [features addObject:@"Offscreen"];
                }
            }
            if (term.window.isMiniaturized) {
                [features addObject:@"Miniaturized"];
            }
            if (term.anyFullScreen) {
                [features addObject:@"Full screen"];
            }
            if (!term.window.isOnActiveSpace && !(term.window.collectionBehavior & NSWindowCollectionBehaviorCanJoinAllSpaces)) {
                [features addObject:@"On other Space"];
            }
            if (term.isHotKeyWindow) {
                iTermProfileHotKey *profileHotkey = [[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:term];
                iTermShortcut *shortcut = profileHotkey.shortcuts.firstObject;
                if (shortcut) {
                    [features addObject:[NSString stringWithFormat:@"Hotkey %@", shortcut.stringValue]];
                } else if (profileHotkey.hasModifierActivation) {
                    const iTermHotKeyModifierActivation mod = profileHotkey.modifierActivation;
                    NSEventModifierFlags flags = 0;
                    switch (mod) {
                        case iTermHotKeyModifierActivationShift:
                            flags = NSEventModifierFlagShift;
                            break;
                        case iTermHotKeyModifierActivationOption:
                            flags = NSEventModifierFlagOption;
                            break;
                        case iTermHotKeyModifierActivationCommand:
                            flags = NSEventModifierFlagCommand;
                            break;
                        case iTermHotKeyModifierActivationControl:
                            flags = NSEventModifierFlagControl;
                            break;
                    }
                    if (flags) {
                        NSString *key = [NSString stringForModifiersWithMask:flags];
                        [features addObject:[NSString stringWithFormat:@"Hotkey %@%@", key, key]];
                    }
                }
            }
            if (features.count) {
                item.detail = [_delegate openQuicklyModelDisplayStringForFeatureNamed:nil
                                                                                value:[features componentsJoinedByString:@" — "]
                                                                   highlightedIndexes:nil];
            }
            if (attributedName.length) {
                item.title = attributedName;
            } else {
                item.title = [_delegate openQuicklyModelDisplayStringForFeatureNamed:nil
                                                                               value:[self documentForWindow:term]
                                                                  highlightedIndexes:nil];
            }
            item.identifier = term.terminalGuid;
            [items addObject:item];
        }
    }}
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

- (void)addBookmarkToItems:(NSMutableArray<iTermOpenQuicklyItem *> *)items
               withMatcher:(iTermMinimumSubsequenceMatcher *)matcher {
    if (![iTermAdvancedSettingsModel browserProfiles]) {
        return;
    }
    for (iTermTriple<NSString *, NSURL *, NSString *> *triple in [iTermBrowserBookmarkFinder bookmarksMatchingSubstring:matcher.query]) {
        iTermOpenQuicklyBookmarkItem *item = [[iTermOpenQuicklyBookmarkItem alloc] init];
        NSMutableAttributedString *attributedName = [[NSMutableAttributedString alloc] init];
        item.score = [self scoreForBookmarkTitle:triple.firstObject url:triple.secondObject matcher:matcher attributedName:attributedName];
        if (item.score > 0) {
            item.detail = [_delegate openQuicklyModelDisplayStringForFeatureNamed:nil
                                                                            value:@"Open Bookmark in Browser"
                                                               highlightedIndexes:nil];
            item.title = attributedName;
            item.identifier = [triple.secondObject absoluteString];
            item.url = triple.secondObject;
            item.bookmarkName = triple.firstObject;
            item.userID = triple.thirdObject;
            [items addObject:item];
        }
    }
}

- (void)addURLToItems:(NSMutableArray<iTermOpenQuicklyItem *> *)items
           withMatcher:(iTermMinimumSubsequenceMatcher *)matcher {
    if (![iTermAdvancedSettingsModel browserProfiles]) {
        return;
    }
    NSURL *url = [NSURL URLWithString:matcher.query];
    if ([matcher.query hasPrefix:@"https://"] && url != nil) {
        iTermOpenQuicklyURLItem *item = [[iTermOpenQuicklyURLItem alloc] init];

        NSMutableAttributedString *attributedName = [[NSMutableAttributedString alloc] init];
        item.score = [self scoreForURL:url matcher:matcher attributedName:attributedName];
        if (item.score > 0) {
            item.detail = [_delegate openQuicklyModelDisplayStringForFeatureNamed:nil
                                                                            value:@"Open URL in Browser"
                                                               highlightedIndexes:nil];
            item.title = attributedName;
            item.identifier = matcher.query;
            item.url = [NSURL URLWithString:matcher.query];
            [items addObject:item];
        }
    }
}

- (void)addChangeColorPresetToItems:(NSMutableArray<iTermOpenQuicklyItem *> *)items
                        withMatcher:(iTermMinimumSubsequenceMatcher *)matcher {
    if ([[[[[iTermController sharedInstance] currentTerminal] currentSession] profile] profileIsBrowser]) {
        // Browser does not support color presets.
        return;
    }
    iTermColorPresetDictionary *allPresets = [iTermColorPresets allColorPresets];
    NSColor *defaultColor = [NSColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1];
    const BOOL dark = [[NSApp effectiveAppearance] it_isDark];
    for (NSString *name in allPresets) {
        iTermColorPreset *preset = allPresets[name];
        
        iTermOpenQuicklyColorPresetItem *item = [[iTermOpenQuicklyColorPresetItem alloc] init];
        item.presetName = name;
        item.logoGenerator.textColor = iTermColorPresetGet(preset, KEY_FOREGROUND_COLOR, dark) ?: [NSColor colorWithRed:0.75 green:0.75 blue:0.75 alpha:1];
        item.logoGenerator.backgroundColor = iTermColorPresetGet(preset, KEY_BACKGROUND_COLOR, dark) ?: [NSColor colorWithRed:0.25 green:0.25 blue:0.25 alpha:1];
        item.logoGenerator.tabColor = iTermColorPresetGet(preset, KEY_TAB_COLOR, dark) ?: defaultColor;
        item.logoGenerator.cursorColor = iTermColorPresetGet(preset, KEY_CURSOR_COLOR, dark) ?: defaultColor;

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
        if (profile.profileType != iTermController.sharedInstance.currentTerminal.currentSession.profile.profileType) {
            // Prevent selecting a type that will fail
            continue;
        }
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

- (void)addActionsToItems:(NSMutableArray<iTermOpenQuicklyItem *> *)items
              withMatcher:(iTermMinimumSubsequenceMatcher *)matcher {
    [[[iTermActionsModel sharedInstance] actions] enumerateObjectsUsingBlock:^(iTermAction * _Nonnull action, NSUInteger idx, BOOL * _Nonnull stop) {
        iTermOpenQuicklyActionItem *actionItem = [self actionItemForAction:action
                                                                   matcher:matcher];
        if (actionItem) {
            [items addObject:actionItem];
        }
    }];
}

- (iTermOpenQuicklyActionItem *)actionItemForAction:(iTermAction *)action
                                            matcher:(iTermMinimumSubsequenceMatcher *)matcher {
    iTermOpenQuicklyActionItem *actionItem = [[iTermOpenQuicklyActionItem alloc] init];
    actionItem.action = action;
    NSMutableAttributedString *attributedName = [[NSMutableAttributedString alloc] init];
    actionItem.score = [self scoreForAction:action matcher:matcher attributedName:attributedName];
    if (actionItem.score <= 0) {
        return nil;
    }
    actionItem.detail = [_delegate openQuicklyModelDisplayStringForFeatureNamed:nil
                                                                          value:action.displayString
                                                             highlightedIndexes:nil];
    actionItem.title = attributedName;
    actionItem.identifier = [@(action.identifier) stringValue];
    return actionItem;
}

- (void)addInvocation:(NSString *)invocation 
                scope:(iTermVariableScope *)scope
              toItems:(NSMutableArray<iTermOpenQuicklyItem *> *)items
          withMatcher:(iTermMinimumSubsequenceMatcher *)matcher NS_AVAILABLE_MAC(11_0) {
    iTermOpenQuicklyInvocationItem *item = [[iTermOpenQuicklyInvocationItem alloc] init];
    item.score = 1;
    item.detail = [_delegate openQuicklyModelDisplayStringForFeatureNamed:nil
                                                                    value:@"Invoke"
                                                       highlightedIndexes:nil];
    NSMutableAttributedString *attributedName = [[NSMutableAttributedString alloc] init];
    item.score = [self scoreForInvocation:invocation matcher:matcher attributedName:attributedName];
    item.title = attributedName;
    item.identifier = invocation;
    item.scope = scope;

    [items addObject:item];
}

- (void)addNamedMarksToItems:(NSMutableArray<iTermOpenQuicklyItem *> *)items
                 withMatcher:(iTermMinimumSubsequenceMatcher *)matcher {
    for (PTYSession *session in [[iTermController sharedInstance] allSessions]) {
        for (id<iTermGenericNamedMarkReading> namedMark in session.namedMarks) {
            if (!namedMark.name.length) {
                continue;
            }
            iTermOpenQuicklyNamedMarkItem *item = [self itemForNamedMark:namedMark
                                                               inSession:session
                                                                 matcher:matcher];
            if (item) {
                [items addObject:item];
            }
        }
    }
}

- (void)addMenuItemsToItems:(NSMutableArray<iTermOpenQuicklyItem *> *)items
                withMatcher:(iTermMinimumSubsequenceMatcher *)matcher {
    [self addMenuItemsInMenu:[NSApp mainMenu] toItems:items withMatcher:matcher path:@[]];
}

- (void)addMenuItemsInMenu:(NSMenu *)menu
                   toItems:(NSMutableArray<iTermOpenQuicklyItem *> *)items
               withMatcher:(iTermMinimumSubsequenceMatcher *)matcher
                      path:(NSArray<NSString *> *)path {
    [menu update];
    for (NSMenuItem *menuItem in menu.itemArray) {
        if (menuItem.title.length > 0 && menuItem.action != nil && !menuItem.submenu) {
            iTermOpenQuicklyMenuItem *item = [self itemForMenuItem:menuItem
                                                           matcher:matcher
                                                              path:path];
            if (item) {
                [items addObject:item];
            }
        }
        if (menuItem.submenu) {
            [self addMenuItemsInMenu:menuItem.submenu toItems:items withMatcher:matcher path:[path arrayByAddingObject:menuItem.title]];
        }
    }
}

- (void)addSnippetsToItems:(NSMutableArray<iTermOpenQuicklyItem *> *)items
               withMatcher:(iTermMinimumSubsequenceMatcher *)matcher {
    NSArray<NSString *> *tags = [[iTermController sharedInstance] currentSnippetsFilter];
    [[[iTermSnippetsModel sharedInstance] snippets] enumerateObjectsUsingBlock:^(iTermSnippet * _Nonnull snippet, NSUInteger idx, BOOL * _Nonnull stop) {
        if (![snippet hasTags:tags]) {
            return;
        }
        iTermOpenQuicklySnippetItem *snippetItem = [self snippetItemForSnippet:snippet
                                                                       matcher:matcher];
        if (snippetItem) {
            [items addObject:snippetItem];
        }
    }];
}

- (iTermOpenQuicklySnippetItem *)snippetItemForSnippet:(iTermSnippet *)snippet
                                               matcher:(iTermMinimumSubsequenceMatcher *)matcher {
    iTermOpenQuicklySnippetItem *snippetItem = [[iTermOpenQuicklySnippetItem alloc] init];
    snippetItem.snippet = snippet;
    NSMutableAttributedString *attributedName = [[NSMutableAttributedString alloc] init];
    snippetItem.score = [self scoreForSnippet:snippet matcher:matcher attributedName:attributedName];
    if (snippetItem.score <= 0) {
        return nil;
    }
    snippetItem.detail = [_delegate openQuicklyModelDisplayStringForFeatureNamed:nil
                                                                           value:[NSString stringWithFormat:@"Send snippet “%@”. Press ⌥ to edit first.", snippet.displayTitle]
                                                              highlightedIndexes:nil];
    snippetItem.title = attributedName;
    snippetItem.identifier = snippet.guid;
    return snippetItem;
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
                         tabsOnly:(BOOL)tabsOnly
                      withMatcher:(iTermMinimumSubsequenceMatcher *)matcher {
    for (NSString *arrangementName in [WindowArrangements allNames]) {
        iTermOpenQuicklyArrangementItem *item;
        if (!tabsOnly) {
            item = [self arrangementItemWithName:arrangementName matcher:matcher inTabs:NO];
            if (item) {
                [items addObject:item];
            }
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
    id<iTermOpenQuicklyCommand> command = [self commandForQuery:queryString];
    if (!command) {
        command = [self commandForQuery:queryString.lowercaseString];
    }
    iTermMinimumSubsequenceMatcher *matcher =
        [[iTermMinimumSubsequenceMatcher alloc] initWithQuery:command.text];

    NSMutableArray *items = [NSMutableArray array];

    if ([queryString isEqualToString:@"/"]) {
        [self addTipsToItems:items];
    }

    if ([command supportsSessionLocation]) {
        [self addSessionLocationToItems:items withMatcher:matcher];
    }
    if ([command supportsWindowLocation]) {
        [self addWindowLocationToItems:items withMatcher:matcher];
    }
    BOOL haveCurrentWindow = [[iTermController sharedInstance] currentTerminal] != nil;
    if ([command supportsCreateNewTab]) {
        [self addCreateNewTabToItems:items withMatcher:matcher haveCurrentWindow:haveCurrentWindow];
    }
    if ([command supportsChangeProfile] && haveCurrentWindow) {
        [self addChangeProfileToItems:items withMatcher:matcher];
    }
    BOOL tabsOnly = NO;
    if ([command supportsOpenArrangement:&tabsOnly]) {
        [self addOpenArrangementToItems:items tabsOnly:tabsOnly withMatcher:matcher];
    }
    if ([command supportsScript]) {
        [self addScriptToItems:items withMatcher:matcher];
    }
    if ([command supportsColorPreset] && haveCurrentWindow) {
        [self addChangeColorPresetToItems:items withMatcher:matcher];
    }
    if ([command supportsAction] && haveCurrentWindow) {
        [self addActionsToItems:items withMatcher:matcher];
    }
    if ([command supportsSnippet] && haveCurrentWindow) {
        [self addSnippetsToItems:items withMatcher:matcher];
    }
    if ([command supportsNamedMarks]) {
        [self addNamedMarksToItems:items withMatcher:matcher];
    }
    if ([command supportsMenuItems]) {
        [self addMenuItemsToItems:items withMatcher:matcher];
    }
    if (@available(macOS 11, *)) {
#if DEBUG
        NSLog(@"Not attempting invocation for open quickly because it throws exceptions");
#else
        iTermVariableScope *scope = [self scopeForValidInvocation:queryString];
        if (scope) {
            [self addInvocation:queryString scope:scope toItems:items withMatcher:matcher];
        }
#endif
        if ([iTermAdvancedSettingsModel browserProfiles]) {
            if ([command supportsBookmarks]) {
                [self addBookmarkToItems:items withMatcher:matcher];
            }
            if ([command supportsURLs]) {
                [self addURLToItems:items withMatcher:matcher];
            }
        }
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

- (iTermVariableScope *)scopeForValidInvocation:(NSString *)invocation {
    iTermVariableScope *scope = [[[[iTermController sharedInstance] currentTerminal] currentSession] variablesScope];
    if (scope) {
        iTermParsedExpression *expression = [[iTermExpressionParser callParser] parse:invocation
                                                                                scope:scope];
        if (expression) {
            switch (expression.expressionType) {
                case iTermParsedExpressionTypeVariableReference:
                case iTermParsedExpressionTypeArrayLookup:
                case iTermParsedExpressionTypeArrayOfValues:
                case iTermParsedExpressionTypeArrayOfExpressions:
                case iTermParsedExpressionTypeNumber:
                case iTermParsedExpressionTypeReference:
                case iTermParsedExpressionTypeBoolean:
                case iTermParsedExpressionTypeError:
                case iTermParsedExpressionTypeString:
                case iTermParsedExpressionTypeNil:
                case iTermParsedExpressionTypeInterpolatedString:
                    break;

                case iTermParsedExpressionTypeFunctionCall:
                case iTermParsedExpressionTypeFunctionCalls:
                    return scope;
            }
        }
    }

    scope = [iTermVariableScope globalsScope];
    iTermParsedExpression *expression = [[iTermExpressionParser callParser] parse:invocation
                                                                            scope:scope];
    if (expression) {
        switch (expression.expressionType) {
            case iTermParsedExpressionTypeVariableReference:
            case iTermParsedExpressionTypeArrayLookup:
            case iTermParsedExpressionTypeArrayOfValues:
            case iTermParsedExpressionTypeArrayOfExpressions:
            case iTermParsedExpressionTypeNumber:
            case iTermParsedExpressionTypeReference:
            case iTermParsedExpressionTypeBoolean:
            case iTermParsedExpressionTypeError:
            case iTermParsedExpressionTypeString:
            case iTermParsedExpressionTypeNil:
            case iTermParsedExpressionTypeInterpolatedString:
                break;

            case iTermParsedExpressionTypeFunctionCall:
            case iTermParsedExpressionTypeFunctionCalls:
                return scope;
        }
    }

    return nil;
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
    } else if ([item isKindOfClass:[iTermOpenQuicklyWindowItem class]]) {
        NSString *guid = item.identifier;
        for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
            if ([term.terminalGuid isEqual:guid]) {
                return term;
            }
        }
    } else if ([item isKindOfClass:[iTermOpenQuicklyScriptItem class]]) {
        return item;
    } else if ([item isKindOfClass:[iTermOpenQuicklyColorPresetItem class]]) {
        return item;
    } else if ([item isKindOfClass:[iTermOpenQuicklyActionItem class]]) {
        return item;
    } else if ([item isKindOfClass:[iTermOpenQuicklySnippetItem class]]) {
        return item;
    } else if ([item isKindOfClass:[iTermOpenQuicklyNamedMarkItem class]]) {
        return item;
    } else if ([item isKindOfClass:[iTermOpenQuicklyMenuItem class]]) {
        return item;
    } else if ([item isKindOfClass:[iTermOpenQuicklyBookmarkItem class]]) {
        return item;
    } else if ([item isKindOfClass:[iTermOpenQuicklyURLItem class]]) {
        return item;
    }
    if (@available(macOS 11, *)) {
        if ([item isKindOfClass:[iTermOpenQuicklyInvocationItem class]]) {
            return item;
        }
    }
    return nil;
}

#pragma mark - Scoring

- (double)scoreForInvocation:(NSString *)invocation
                     matcher:(iTermMinimumSubsequenceMatcher *)matcher
              attributedName:(NSMutableAttributedString *)attributedName {
    NSMutableArray *invocationFeature = [NSMutableArray array];
    double score = [self scoreUsingMatcher:matcher
                                 documents:@[ invocation ?: @"" ]
                                multiplier:kInvocationMultiplier
                                      name:nil
                                  features:invocationFeature
                                     limit:2 * kInvocationMultiplier];
    if (invocationFeature.count) {
        [attributedName appendAttributedString:invocationFeature[0][0]];
    }
    return score;
}

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

- (double)scoreForWindow:(PseudoTerminal *)term
                 matcher:(iTermMinimumSubsequenceMatcher *)matcher
          attributedName:(NSMutableAttributedString *)attributedName {
    NSMutableArray *nameFeature = [NSMutableArray array];
    double score = [self scoreUsingMatcher:matcher
                                 documents:@[ term.window.title ?: @"" ]
                                multiplier:kProfileNameMultiplierForWindowItem
                                      name:nil
                                  features:nameFeature
                                     limit:2 * kProfileNameMultiplierForWindowItem];
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

- (double)scoreForAction:(iTermAction *)action
                 matcher:(iTermMinimumSubsequenceMatcher *)matcher
          attributedName:(NSMutableAttributedString *)attributedName {
    NSMutableArray *nameFeature = [NSMutableArray array];
    double score = [self scoreUsingMatcher:matcher
                                 documents:@[ action.title ?: @"" ]
                                multiplier:kActionMultiplier
                                      name:nil
                                  features:nameFeature
                                     limit:2 * kActionMultiplier];
    if (nameFeature.count) {
        [attributedName appendAttributedString:nameFeature[0][0]];
    }
    return score;
}

- (double)scoreForMenuItem:(NSMenuItem *)menuItem
                   matcher:(iTermMinimumSubsequenceMatcher *)matcher
            attributedName:(NSMutableAttributedString *)attributedName {
    NSMutableArray *nameFeature = [NSMutableArray array];

    const double score = [self scoreUsingMatcher:matcher
                                       documents:@[ menuItem.title, menuItem.toolTip ?: @"" ]
                                      multiplier:kMenuItemMultiplier
                                            name:nil
                                        features:nameFeature
                                           limit:kMenuItemMultiplier];
    if (nameFeature.count) {
        [attributedName appendAttributedString:nameFeature[0][0]];
    }
    return score;
}

- (double)scoreForNamedMark:(id<iTermGenericNamedMarkReading>)namedMark
                    matcher:(iTermMinimumSubsequenceMatcher *)matcher
             attributedName:(NSMutableAttributedString *)attributedName
            inActiveSession:(BOOL)inActiveSession {
    NSMutableArray *nameFeature = [NSMutableArray array];

    const double multiplier = kNamedMarkMultiplier * (inActiveSession ? 1.5 : 1.0);
    const double score = [self scoreUsingMatcher:matcher
                                       documents:@[ namedMark.name ?: @"" ]
                                      multiplier:multiplier
                                            name:nil
                                        features:nameFeature
                                           limit:multiplier];
    if (nameFeature.count) {
        [attributedName appendAttributedString:nameFeature[0][0]];
    }
    return score;
}

- (double)scoreForSnippet:(iTermSnippet *)snippet
                  matcher:(iTermMinimumSubsequenceMatcher *)matcher
           attributedName:(NSMutableAttributedString *)attributedName {
    NSMutableArray *nameFeature = [NSMutableArray array];
    double score = [self scoreUsingMatcher:matcher
                                 documents:@[ snippet.title ?: @"",
                                              [snippet trimmedValue:80] ?: @"" ]
                                multiplier:kSnippetMultiplier
                                      name:nil
                                  features:nameFeature
                                     limit:2 * kSnippetMultiplier];
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

- (double)scoreForURL:(NSURL *)url
              matcher:(iTermMinimumSubsequenceMatcher *)matcher
       attributedName:(NSMutableAttributedString *)attributedName {
    NSMutableArray *nameFeature = [NSMutableArray array];
    double score = [self scoreUsingMatcher:matcher
                                 documents:@[ url.absoluteString ]
                                multiplier:kMultiplierForURLItem
                                      name:nil
                                  features:nameFeature
                                     limit:2 * kMultiplierForURLItem];
    if (nameFeature.count) {
        [attributedName appendAttributedString:nameFeature[0][0]];
    }
    return score;
}

- (double)scoreForBookmarkTitle:(NSString *)title
                            url:(NSURL *)url
                        matcher:(iTermMinimumSubsequenceMatcher *)matcher
                 attributedName:(NSMutableAttributedString *)attributedName {
    NSMutableArray *nameFeature = [NSMutableArray array];
    double score = [self scoreUsingMatcher:matcher
                                 documents:@[ url.absoluteString, title ]
                                multiplier:kProfileNameMultiplierForBookmarkItem
                                      name:nil
                                  features:nameFeature
                                     limit:2 * kProfileNameMultiplierForBookmarkItem];
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
// features: An array that will be populated with tuples of (detail, score, feature name).
//   The detail element is a suitable-for-display NSAttributedString*s
//   describing features that matched the query, while the score element is the
//   score assigned to that feature.
// attributedName: The session's name with matching characters highlighted
//   (suitable for display) will be appended to this NSMutableAttributedString.
- (double)scoreForSession:(PTYSession *)session
                  matcher:(iTermMinimumSubsequenceMatcher *)matcher
                 features:(NSMutableArray *)features
           attributedName:(NSMutableAttributedString *)attributedName {
    __block double score = 0;
    double maxScorePerFeature = 2 + matcher.query.length / 4;
    if (session.name) {
        NSMutableArray *nameFeature = [NSMutableArray array];
        score += [self scoreUsingMatcher:matcher
                               documents:@[ [self documentForSession:session] ]
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

    score += [self scoreUsingMatcher:matcher
                           documents:[self gitBranchesInSession:session]
                          multiplier:kGitBranchMultiplier
                                name:@"Git Branch"
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

    NSString *tty = [NSString castFrom:[session.variables valueForVariableName:iTermVariableKeySessionTTY]];
    NSNumber *pid = [NSNumber castFrom:[session.variables valueForVariableName:iTermVariableKeySessionJobPid]];
    NSDictionary<NSString *, NSString *> *variables = [@{
        @"tty": tty ?: [NSNull null],
        @"pid": pid.stringValue ?: [NSNull null]
    } mapValuesWithBlock:^NSString *(NSString *key, NSString *value) {
        return [value nilIfNull];
    }];
    [variables enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull name,
                                                   NSString * _Nonnull value,
                                                   BOOL * _Nonnull stop) {
        score += [self scoreUsingMatcher:matcher
                               documents:@[ value ]
                              multiplier:kOtherVariableMultiplier
                                    name:name
                                features:features
                                   limit:maxScorePerFeature];
    }];

    // TODO: add a bonus for:
    // Doing lots of typing in a session
    // Being newly created
    // Recency of use

    return score;
}

// Given an array of features which are a tuple of (detail, score), return the
// detail for the highest scoring one.
// Returns (feature name, display string)
- (iTermTuple<NSString *, NSAttributedString *> *)detailForSession:(PTYSession *)session
                                                          features:(NSArray *)features {
    NSArray *sorted = [features sortedArrayUsingComparator:^NSComparisonResult(NSArray *tuple1, NSArray *tuple2) {
        NSNumber *score1 = tuple1[1];
        NSNumber *score2 = tuple2[1];
        return [score1 compare:score2];
    }];
    NSArray *winner = [sorted lastObject];
    return [iTermTuple tupleWithObject:winner[2] andObject:winner[0]];
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
                 multiplier:(double)multiplier
                       name:(NSString *)name
                   features:(NSMutableArray *)features
                      limit:(double)limit {
    if (multiplier == 0) {
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
                [features addObject:@[ displayString, @(score), name ?: @"" ]];
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
        score += value * multiplier;
        if (score > limit) {
            break;
        }
    }

    if (bestFeature && features) {
        id displayString = [_delegate openQuicklyModelDisplayStringForFeatureNamed:name
                                                                             value:bestFeature
                                                                highlightedIndexes:bestIndexSet];
        [features addObject:@[ displayString, @(score), name ?: @"" ]];
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
- (NSArray *)hostnamesInHosts:(NSArray<id<VT100RemoteHostReading>> *)hosts {
    NSMutableArray *names = [NSMutableArray array];
    for (id<VT100RemoteHostReading> host in hosts) {
        [names addObject:host.hostname];
    }
    return names;
}

// Returns an array of usernames from an array of VT100RemoteHost*s
- (NSArray *)usernamesInHosts:(NSArray<id<VT100RemoteHostReading>> *)hosts {
    NSMutableArray *names = [NSMutableArray array];
    for (id<VT100RemoteHostReading> host in hosts) {
        [names addObject:host.username];
    }
    return names;
}

- (NSArray<NSString *> *)gitBranchesInSession:(PTYSession *)session {
    NSString *pwd = session.directories.lastObject;
    if (!pwd) {
        return @[];
    }
    NSString *branch = [[iTermGitPollWorker sharedInstance] cachedBranchForPath:pwd];
    if (!branch) {
        return @[];
    }
    return @[branch];
}

@end
