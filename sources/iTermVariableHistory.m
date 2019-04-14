//
//  iTermVariableHistory.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/5/19.
//

#import "iTermVariableHistory.h"

#import "DebugLogging.h"
#import "iTermRecordedVariable.h"
#import "iTermVariables.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

@implementation iTermVariableHistory

#pragma mark - APIs

+ (NSString *)stringForContext:(iTermVariablesSuggestionContext)context {
    NSArray<NSString *> *parts = @[];
    if (context & iTermVariablesSuggestionContextSession) {
        parts = [parts arrayByAddingObject:@"Session"];
    }
    if (context & iTermVariablesSuggestionContextTab) {
        parts = [parts arrayByAddingObject:@"Tab"];
    }
    if (context & iTermVariablesSuggestionContextWindow) {
        parts = [parts arrayByAddingObject:@"Window"];
    }
    if (context & iTermVariablesSuggestionContextApp) {
        parts = [parts arrayByAddingObject:@"App"];
    }
    if (context == iTermVariablesSuggestionContextNone) {
        parts = [parts arrayByAddingObject:@"None"];
    }
    return [parts componentsJoinedByString:@"|"];
}

+ (void)recordBuiltInVariables {
    // Session context
    NSArray<NSString *> *names = @[ iTermVariableKeySessionAutoLogID,
                                    iTermVariableKeySessionColumns,
                                    iTermVariableKeySessionCreationTimeString,
                                    iTermVariableKeySessionHostname,
                                    iTermVariableKeySessionID,
                                    iTermVariableKeySessionLastCommand,
                                    iTermVariableKeySessionPath,
                                    iTermVariableKeySessionName,
                                    iTermVariableKeySessionRows,
                                    iTermVariableKeySessionTTY,
                                    iTermVariableKeySessionUsername,
                                    iTermVariableKeySessionTermID,
                                    iTermVariableKeySessionProfileName,
                                    iTermVariableKeySessionIconName,
                                    iTermVariableKeySessionTriggerName,
                                    iTermVariableKeySessionWindowName,
                                    iTermVariableKeySessionJob,
                                    iTermVariableKeySessionPresentationName,
                                    iTermVariableKeySessionTmuxWindowTitle,
                                    iTermVariableKeySessionTmuxRole,
                                    iTermVariableKeySessionTmuxClientName,
                                    iTermVariableKeySessionAutoNameFormat,
                                    iTermVariableKeySessionAutoName,
                                    iTermVariableKeySessionTmuxWindowPane,
                                    iTermVariableKeySessionJobPid,
                                    iTermVariableKeySessionChildPid,
                                    iTermVariableKeySessionMouseReportingMode,
                                    iTermVariableKeySessionBadge,
                                    iTermVariableKeySessionTmuxStatusLeft,
                                    iTermVariableKeySessionTmuxStatusRight ];
    [names enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [self recordUseOfVariableNamed:obj inContext:iTermVariablesSuggestionContextSession];
    }];
    [self recordUseOfNonterminalVariableNamed:iTermVariableKeyGlobalScopeName
                                    inContext:iTermVariablesSuggestionContextSession
                             leadingToContext:iTermVariablesSuggestionContextApp];
    [self recordUseOfNonterminalVariableNamed:iTermVariableKeySessionTab
                                    inContext:iTermVariablesSuggestionContextSession
                             leadingToContext:iTermVariablesSuggestionContextTab];

    // Tab context
    [self recordUseOfVariableNamed:iTermVariableKeyTabTitleOverride inContext:iTermVariablesSuggestionContextTab];
    [self recordUseOfVariableNamed:iTermVariableKeyTabTitleOverrideFormat inContext:iTermVariablesSuggestionContextTab];
    [self recordUseOfVariableNamed:iTermVariableKeyTabTmuxWindow inContext:iTermVariablesSuggestionContextTab];
    [self recordUseOfVariableNamed:iTermVariableKeyTabID inContext:iTermVariablesSuggestionContextTab];
    [self recordUseOfVariableNamed:iTermVariableKeyTabWindow inContext:iTermVariablesSuggestionContextTab];

    [self recordUseOfNonterminalVariableNamed:iTermVariableKeyGlobalScopeName
                                    inContext:iTermVariablesSuggestionContextTab
                             leadingToContext:iTermVariablesSuggestionContextApp];
    [self recordUseOfNonterminalVariableNamed:iTermVariableKeyTabCurrentSession
                                    inContext:iTermVariablesSuggestionContextTab
                             leadingToContext:iTermVariablesSuggestionContextSession];
    // TODO: Add a weak link from tab to window.

    // Window context
    [self recordUseOfVariableNamed:iTermVariableKeyWindowTitleOverrideFormat inContext:iTermVariablesSuggestionContextWindow];
    [self recordUseOfNonterminalVariableNamed:iTermVariableKeyWindowCurrentTab
                                    inContext:iTermVariablesSuggestionContextWindow
                             leadingToContext:iTermVariablesSuggestionContextTab];
    [self recordUseOfNonterminalVariableNamed:iTermVariableKeyGlobalScopeName
                                    inContext:iTermVariablesSuggestionContextWindow
                             leadingToContext:iTermVariablesSuggestionContextApp];

    // App context
    [self recordUseOfVariableNamed:iTermVariableKeyApplicationPID inContext:iTermVariablesSuggestionContextApp];
    [self recordUseOfVariableNamed:iTermVariableKeyApplicationLocalhostName inContext:iTermVariablesSuggestionContextApp];
    [self recordUseOfVariableNamed:iTermVariableKeyApplicationEffectiveTheme inContext:iTermVariablesSuggestionContextApp];
}

+ (NSSet<NSString *> * _Nonnull (^)(NSString * _Nonnull))pathSourceForContext:(iTermVariablesSuggestionContext)context {
    return [self pathSourceForContext:context augmentedWith:[NSSet set]];
}

+ (NSSet<NSString *> * _Nonnull (^)(NSString * _Nonnull))pathSourceForContext:(iTermVariablesSuggestionContext)context
                                                                augmentedWith:(NSSet<NSString *> *)augmentations {
    return ^NSSet<NSString *> *(NSString *prefix) {
        return [self recordedVariableNamesInContext:context augmentedWith:augmentations prefix:prefix];
    };
}

+ (void)recordUseOfVariableNamed:(NSString *)namePossiblyContainingNonterminals
                       inContext:(iTermVariablesSuggestionContext)originalContext {
    iTermVariablesSuggestionContext context = originalContext;
    NSString *name = [self pathByConsumingNonterminalsInPath:namePossiblyContainingNonterminals
                                                     context:originalContext
                                                  contextOut:&context];
    assert(name);

    iTermRecordedVariable *record = [[iTermRecordedVariable alloc] initTerminalWithName:name];
    NSMutableSet<iTermRecordedVariable *> *records = [self mutableRecordedVariableNamesInContext:context];
    if (![records containsObject:record]) {
        DLog(@"Record %@ in context %@", name, [iTermVariableHistory stringForContext:context]);
        [records addObject:record];
        [self synchronizeRecordedNames];
    }
}

#pragma mark - Private

+ (NSMutableDictionary<NSNumber *, NSMutableSet<iTermRecordedVariable *> *> *)mutableRecordedNames {
    static NSMutableDictionary<NSNumber *, NSMutableSet<iTermRecordedVariable *> *> *records;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSDictionary *dict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"NoSyncRecordedVariables"] ?: @{};
        records = [NSMutableDictionary dictionary];
        for (id key in dict) {
            NSString *stringContext = [NSString castFrom:key];
            if (!stringContext) {
                continue;
            }
            NSNumber *context = @([stringContext integerValue]);
            NSArray<iTermRecordedVariable *> *names = [[NSArray castFrom:dict[key]] mapWithBlock:^id(id anObject) {
                return [[iTermRecordedVariable alloc] initWithDictionary:anObject];
            }];
            if (!names) {
                continue;
            }
            records[context] = [NSMutableSet setWithArray:names];
        }
    });
    return records;
}

+ (void)synchronizeRecordedNames {
    NSDictionary *plist = [[self mutableRecordedNames] mapValuesWithBlock:^id(NSNumber *key, NSMutableSet<iTermRecordedVariable *> *object) {
        return [object.allObjects mapWithBlock:^id(iTermRecordedVariable *anObject) {
            return [anObject dictionaryValue];
        }];
    }];
    plist = [plist mapKeysWithBlock:^id(id key, id object) {
        return [key stringValue];
    }];
    [[NSUserDefaults standardUserDefaults] setObject:plist forKey:@"NoSyncRecordedVariables"];
}

+ (NSMutableSet<iTermRecordedVariable *> *)mutableRecordedVariableNamesInContext:(iTermVariablesSuggestionContext)context {
    NSMutableSet<iTermRecordedVariable *> *set = self.mutableRecordedNames[@(context)];
    if (!set) {
        set = [NSMutableSet set];
        self.mutableRecordedNames[@(context)] = set;
    }
    return set;
}

+ (NSSet<NSString *> *(^)(NSString *))pathSourceForContext:(iTermVariablesSuggestionContext)context
                                                 excluding:(NSSet<NSString *> *)exclusions
                                             allowUserVars:(BOOL)allowUserVars {
    return ^NSSet<NSString *> *(NSString *prefix) {
        return [self recordedVariableNamesInContext:context
                                      augmentedWith:[NSSet set]
                                          excluding:exclusions
                                             prefix:prefix
                                      allowUserVars:allowUserVars];
    };
}

+ (NSSet<NSString *> *)recordedVariableNamesInContext:(iTermVariablesSuggestionContext)context
                                        augmentedWith:(NSSet<NSString *> *)augmentations
                                               prefix:(NSString *)prefix {
    return [self recordedVariableNamesInContext:context
                                  augmentedWith:augmentations
                                      excluding:[NSSet set]
                                         prefix:prefix
                                  allowUserVars:YES];
}

+ (NSSet<NSString *> *)recordedVariableNamesInContext:(iTermVariablesSuggestionContext)context
                                        augmentedWith:(NSSet<NSString *> *)augmentations
                                            excluding:(NSSet<NSString *> *)exclusions
                                               prefix:(NSString *)prefix
                                        allowUserVars:(BOOL)allowUserVars {
    NSMutableSet<NSString *> *terminalCandidates = [[self recordedTerminalVariableNamesInContext:context] mutableCopy];
    [terminalCandidates unionSet:augmentations];

    NSMutableSet<NSString *> *results = [NSMutableSet set];
    for (NSString *candidate in [terminalCandidates copy]) {
        if (!allowUserVars && [candidate hasPrefix:@"user."]) {
            continue;
        }
        NSSet<NSString *> *paths = [self recordedVariableNamesInContext:context fromCandidate:candidate prefix:prefix];
        [results unionSet:paths];
    }

    // This catches session.tab.currentSession for prefix session.tab.c
    NSSet<NSString *> *nonterminalCandidates = [self recordedNonterminalVariableNamesInContext:context];
    for (NSString *candidate in nonterminalCandidates) {
        NSSet<NSString *> *paths = [self recordedVariableNamesInContext:context fromCandidate:candidate prefix:prefix];
        for (NSString *path in paths) {
            if ([path isEqualToString:candidate]) {
                [results addObject:[path stringByAppendingString:@"."]];
            } else {
                [results addObject:path];
            }
        }
    }

    // This catches session.tab for prefix session.t
    for (NSString *nonterminalName in nonterminalCandidates) {
        if (!allowUserVars && [nonterminalName isEqualToString:@"user"]) {
            continue;
        }
        if ([nonterminalName hasPrefix:prefix]) {
            [results addObject:[nonterminalName stringByAppendingString:@"."]];
        }
    }

    [results minusSet:exclusions];

    return results;
}

+ (NSString *)pathByConsumingNonterminalsInPath:(NSString *)prefix
                                        context:(iTermVariablesSuggestionContext)context
                                     contextOut:(out iTermVariablesSuggestionContext *)contextPtr {
    NSSet<NSString *> *candidates = [self recordedTerminalVariableNamesInContext:context];
    if ([candidates containsObject:prefix]) {
        *contextPtr = context;
        return prefix;
    }
    for (NSString *candidate in candidates) {
        NSString *result = [self pathByConsumingNonterminalsInPath:prefix candidate:candidate context:context contextOut:contextPtr];
        if (result) {
            return result;
        }
    }
    *contextPtr = context;
    return prefix;
}

// Consume leading terminals from prefix beginning with candidate. For example, given the prefix
// "tab.currentSession.tab.foo" in the context of a session and candidate
// "tab", return "foo" in the context of a tab.
+ (NSString *)pathByConsumingNonterminalsInPath:(NSString *)prefix
                                      candidate:(NSString *)candidate
                                        context:(iTermVariablesSuggestionContext)context
                                     contextOut:(out iTermVariablesSuggestionContext *)contextPtr {
    NSArray<NSString *> *candidateParts = [candidate componentsSeparatedByString:@"."];
    NSArray<NSString *> *prefixParts = [prefix componentsSeparatedByString:@"."];
    NSMutableArray<NSString *> *accum = [NSMutableArray array];
    while (prefixParts.count > 0 && candidateParts.count > 0) {
        NSString *currentPrefixPart = prefixParts.firstObject;
        NSString *currentPathPart = candidateParts.firstObject;
        if (![currentPathPart it_hasPrefix:currentPrefixPart]) {
            return nil;
        }
        [accum addObject:currentPathPart];
        prefixParts = [prefixParts subarrayFromIndex:1];
        candidateParts = [candidateParts subarrayFromIndex:1];
    }
    if (candidateParts.count >= prefixParts.count) {
        // Candidate is "foo.barBaz" and prefix is "foo.bar". Not a match.
        return nil;
    }

    // Candidate is "foo", prefix is "foo.bar.baz". Return one of:
    //   - "foo.bar.baz" (if foo is terminal)
    //   - "bar.baz" (if foo is nonterminal and bar is terminal)
    //   - "baz" (if foo and bar are nonterminal)
    NSString *accumulatedPath = [accum componentsJoinedByString:@"."];
    iTermVariablesSuggestionContext currentContext = context;
    const BOOL isNonterminal = [self pathIsNonterminal:accumulatedPath inContext:&currentContext];
    if (!isNonterminal) {
        // Return "foo.bar.baz" because "foo" is terminal.
        *contextPtr = context;
        return prefix;
    }

    // "foo" is a nonterminal. Try to consume more nonterminals from "bar.baz".
    NSString *updatedPrefix = [prefixParts componentsJoinedByString:@"."];
    return [self pathByConsumingNonterminalsInPath:updatedPrefix context:currentContext contextOut:contextPtr];
}

+ (NSSet<NSString *> *)recordedVariableNamesInContext:(iTermVariablesSuggestionContext)context
                                        fromCandidate:(NSString *)candidate
                                               prefix:(NSString *)prefix {
    NSArray<NSString *> *candidateParts = [candidate componentsSeparatedByString:@"."];
    NSArray<NSString *> *prefixParts = [prefix componentsSeparatedByString:@"."];
    NSMutableArray<NSString *> *accum = [NSMutableArray array];
    while (prefixParts.count > 0 && candidateParts.count > 0) {
        NSString *currentPrefixPart = prefixParts.firstObject;
        NSString *currentPathPart = candidateParts.firstObject;
        if (![currentPathPart it_hasPrefix:currentPrefixPart]) {
            return [NSSet set];
        }
        [accum addObject:currentPathPart];
        prefixParts = [prefixParts subarrayFromIndex:1];
        candidateParts = [candidateParts subarrayFromIndex:1];
    }
    if (candidateParts.count >= prefixParts.count) {
        // Candidate is same length or longer than prefix. Use it but don't expand it.
        return [NSSet setWithObject:candidate];
    }

    // Prefix is longer than candidate. That's OK if the path ends in a nonterminal.
    NSString *accumulatedPath = [accum componentsJoinedByString:@"."];
    iTermVariablesSuggestionContext currentContext = context;
    const BOOL isNonterminal = [self pathIsNonterminal:accumulatedPath inContext:&currentContext];
    if (!isNonterminal) {
        // Prefix is longer than path and traverses a nonterminal so we have to stop.
        return [NSSet set];
    }

    NSString *updatedPrefix = [prefixParts componentsJoinedByString:@"."];
    NSSet<NSString *> *innerNames = [self recordedVariableNamesInContext:currentContext
                                                           augmentedWith:[NSSet set]
                                                                  prefix:updatedPrefix];
    NSString *commonPrefix = [accumulatedPath stringByAppendingString:@"."];
    return [NSSet setWithArray:[innerNames.allObjects mapWithBlock:^id(NSString *innerName) {
        return [commonPrefix stringByAppendingString:innerName];
    }]];
}

+ (BOOL)pathIsNonterminal:(NSString *)path inContext:(inout iTermVariablesSuggestionContext *)contextPtr {
    NSSet<iTermRecordedVariable *> *vars = [self recordedVariablesInContext:*contextPtr];
    iTermRecordedVariable *record = [[vars allObjects] objectPassingTest:^BOOL(iTermRecordedVariable *record, NSUInteger index, BOOL *stop) {
        return [record.name isEqualToString:path];
    }];
    if (record.isTerminal) {
        return NO;
    }
    *contextPtr = record.nonterminalContext;
    return YES;
}

+ (NSSet<iTermRecordedVariable *> *)recordedVariablesInContext:(iTermVariablesSuggestionContext)context {
    NSSet<iTermRecordedVariable *> *result = [NSSet set];
    for (int bit = 0; bit < 64; bit++) {
        const NSUInteger one = 1;
        NSUInteger mask = one << bit;
        if (mask & context) {
            NSSet<iTermRecordedVariable *> *records = self.mutableRecordedNames[@(mask)] ?: [NSSet set];
            result = [result setByAddingObjectsFromSet:records];
        }
    }
    if ((context & (iTermVariablesSuggestionContextSession | iTermVariablesSuggestionContextTab)) &&
        !(context & iTermVariablesSuggestionContextApp)) {
        NSSet<iTermRecordedVariable *> *appVariables = [self recordedVariablesInContext:iTermVariablesSuggestionContextApp];
        result = [NSSet setWithArray:[result.allObjects arrayByAddingObjectsFromArray:[appVariables.allObjects mapWithBlock:^id(iTermRecordedVariable *appVariable) {
            return [appVariable recordByPrependingPath:@"iterm2."];
        }]]];
    }
    return result;
}

+ (NSSet<NSString *> *)recordedTerminalVariableNamesInContext:(iTermVariablesSuggestionContext)context {
    return [NSSet setWithArray:[[[self recordedVariablesInContext:context] allObjects] mapWithBlock:^id(iTermRecordedVariable *record) {
        if (!record.isTerminal) {
            return nil;
        }
        return record.name;
    }]];
}

+ (NSSet<NSString *> *)recordedNonterminalVariableNamesInContext:(iTermVariablesSuggestionContext)context {
    return [NSSet setWithArray:[[[self recordedVariablesInContext:context] allObjects] mapWithBlock:^id(iTermRecordedVariable *record) {
        if (record.isTerminal) {
            return nil;
        }
        return record.name;
    }]];
}

+ (void)recordUseOfNonterminalVariableNamed:(NSString *)name
                                  inContext:(iTermVariablesSuggestionContext)context
                           leadingToContext:(iTermVariablesSuggestionContext)leadingToContext {
    iTermRecordedVariable *record = [[iTermRecordedVariable alloc] initNonterminalWithName:name context:leadingToContext];
    NSMutableSet<iTermRecordedVariable *> *records = [self mutableRecordedVariableNamesInContext:context];
    if (![records containsObject:record]) {
        DLog(@"Record %@ in context %@", name, [iTermVariableHistory stringForContext:context]);
        [records addObject:record];
        [self synchronizeRecordedNames];
    }
}

@end
