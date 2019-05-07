//
//  iTermVariables.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import "iTermVariableScope.h"

#import "DebugLogging.h"
#import "iTermTuple.h"
#import "iTermVariableReference.h"
#import "iTermWeakVariables.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

NS_ASSUME_NONNULL_BEGIN

typedef iTermTriple<NSNumber *, iTermVariables *, NSString *> iTermVariablesDepthOwnerNamesTriple;

NSString *const iTermVariableKeyGlobalScopeName = @"iterm2";

#pragma mark - Global Context

NSString *const iTermVariableKeyApplicationPID = @"pid";
NSString *const iTermVariableKeyApplicationLocalhostName = @"localhostName";
NSString *const iTermVariableKeyApplicationEffectiveTheme = @"effectiveTheme";

#pragma mark - Tab Context

NSString *const iTermVariableKeyTabTitleOverride = @"titleOverride";
NSString *const iTermVariableKeyTabTitleOverrideFormat = @"titleOverrideFormat";
NSString *const iTermVariableKeyTabCurrentSession = @"currentSession";
NSString *const iTermVariableKeyTabTmuxWindow = @"tmuxWindow";
NSString *const iTermVariableKeyTabID = @"id";
NSString *const iTermVariableKeyTabWindow = @"window";

#pragma mark - Session Context

NSString *const iTermVariableKeySessionAutoLogID = @"autoLogId";
NSString *const iTermVariableKeySessionColumns = @"columns";
NSString *const iTermVariableKeySessionCreationTimeString = @"creationTimeString";
NSString *const iTermVariableKeySessionHostname = @"hostname";
NSString *const iTermVariableKeySessionID = @"id";
NSString *const iTermVariableKeySessionLastCommand = @"lastCommand";
NSString *const iTermVariableKeySessionPath = @"path";
NSString *const iTermVariableKeySessionName = @"name";
NSString *const iTermVariableKeySessionRows = @"rows";
NSString *const iTermVariableKeySessionTTY = @"tty";
NSString *const iTermVariableKeySessionUsername = @"username";
NSString *const iTermVariableKeySessionTermID = @"termid";
NSString *const iTermVariableKeySessionProfileName = @"profileName";
NSString *const iTermVariableKeySessionIconName = @"terminalIconName";
NSString *const iTermVariableKeySessionTriggerName = @"triggerName";
NSString *const iTermVariableKeySessionWindowName = @"terminalWindowName";
NSString *const iTermVariableKeySessionJob = @"jobName";
NSString *const iTermVariableKeySessionPresentationName = @"presentationName";
NSString *const iTermVariableKeySessionTmuxWindowTitle = @"tmuxWindowTitle";
NSString *const iTermVariableKeySessionTmuxWindowTitleEval = @"tmuxWindowTitleEval";
NSString *const iTermVariableKeySessionTmuxRole = @"tmuxRole";
NSString *const iTermVariableKeySessionTmuxClientName = @"tmuxClientName";
NSString *const iTermVariableKeySessionAutoNameFormat = @"autoNameFormat";
NSString *const iTermVariableKeySessionAutoName = @"autoName";
NSString *const iTermVariableKeySessionTmuxWindowPane = @"tmuxWindowPane";
NSString *const iTermVariableKeySessionJobPid = @"jobPid";
NSString *const iTermVariableKeySessionChildPid = @"pid";
NSString *const iTermVariableKeySessionTmuxStatusLeft = @"tmuxStatusLeft";
NSString *const iTermVariableKeySessionTmuxStatusRight = @"tmuxStatusRight";
NSString *const iTermVariableKeySessionMouseReportingMode = @"mouseReportingMode";
NSString *const iTermVariableKeySessionBadge = @"badge";
NSString *const iTermVariableKeySessionTab = @"tab";

#pragma mark - Window Context

NSString *const iTermVariableKeyWindowTitleOverrideFormat = @"titleOverrideFormat";
NSString *const iTermVariableKeyWindowTitleOverride = @"titleOverride";
NSString *const iTermVariableKeyWindowCurrentTab = @"currentTab";

// NOTE: If you add here, also update +recordBuiltInVariables

#pragma mark -

@implementation iTermVariables {
    NSMutableDictionary<NSString *, id> *_values;
    __weak iTermVariables *_parent;
    NSString *_parentName;
    iTermVariablesSuggestionContext _context;
    NSMutableDictionary<NSString *, NSPointerArray *> *_resolvedLinks;
    NSMutableDictionary<NSString *, NSPointerArray *> *_unresolvedLinks;
}

+ (instancetype)globalInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextApp
                                                     owner:NSApp];
    });
    return instance;
}


- (instancetype)initWithContext:(iTermVariablesSuggestionContext)context owner:(nonnull id)owner {
    self = [super init];
    if (self) {
        _owner = owner;
        _context = context;
        _values = [NSMutableDictionary dictionary];
        _resolvedLinks = [NSMutableDictionary dictionary];
        _unresolvedLinks = [NSMutableDictionary dictionary];

        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            [iTermVariableHistory recordBuiltInVariables];
        });
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p owner=%@>", self.class, self, self.owner];
}

#pragma mark - APIs

- (BOOL)setValue:(nullable id)value forVariableNamed:(NSString *)name {
    return [self setValue:value forVariableNamed:name weak:NO];
}

- (BOOL)setValue:(nullable id)value forVariableNamed:(NSString *)name weak:(BOOL)weak {
    iTermVariables *owner = [self setValue:value forVariableNamed:name withSideEffects:YES weak:weak];
    return owner != nil;
}

- (BOOL)setValuesFromDictionary:(NSDictionary<NSString *, id> *)dict {
    NSMutableArray<iTermVariablesDepthOwnerNamesTriple *> *mutations;
    for (NSString *name in dict) {
        id value = dict[name];
        iTermVariables *owner = nil;
        owner = [self setValue:value forVariableNamed:name withSideEffects:NO weak:NO];
        if (owner) {
            NSInteger depth = [[name componentsSeparatedByString:@"."] count];
            [mutations addObject:[iTermTriple tripleWithObject:@(depth) andObject:owner object:name]];
        }
    }
    if (!mutations.count) {
        return NO;
    }

    [self didReferenceVariables:mutations];
    return YES;
}

- (nullable id)discouragedValueForVariableName:(NSString *)name {
    return [self valueForVariableName:name];
}

- (nullable id)rawValueForVariableName:(NSString *)name {
    return _values[name];
}

- (id)valueByUnwrappingWeakVariables:(id)value {
    iTermWeakVariables *weakVariables = [iTermWeakVariables castFrom:value];
    if (weakVariables) {
        return weakVariables.variables;
    } else {
        return value;
    }
}

- (nullable id)valueForVariableName:(NSString *)name {
    if (_values[name]) {
        return [self valueByUnwrappingWeakVariables:_values[name]];
    }
    NSArray<NSString *> *parts = [name componentsSeparatedByString:@"."];
    if (parts.count <= 1) {
        return nil;
    }

    id value = _values[parts.firstObject];
    iTermVariables *child = [iTermVariables castFrom:[self valueByUnwrappingWeakVariables:value]];
    if (!child) {
        return nil;
    }
    return [child valueForVariableName:[[parts subarrayFromIndex:1] componentsJoinedByString:@"."]];
}

- (NSString *)stringValueForVariableName:(NSString *)name {
    id obj = [self valueForVariableName:name];
    if (!obj) {
        return @"";
    }
    if ([obj isKindOfClass:[NSString class]]) {
        return obj;
    }
    NSNumber *number = [NSNumber castFrom:obj];
    if (number) {
        return [number stringValue];
    }
    return [NSJSONSerialization it_jsonStringForObject:obj] ?: @"";
}

- (void)addLinkToReference:(iTermVariableReference *)reference
                      path:(NSString *)path {
    NSArray<NSString *> *parts = [path componentsSeparatedByString:@"."];
    id value = _values[parts.firstObject];
    if (value) {
        [self addWeakReferenceToLinkTable:_resolvedLinks toObject:reference forKey:parts.firstObject];
        [reference addLinkToVariables:self localPath:parts.firstObject];
        iTermVariables *sub = [iTermVariables castFrom:[self valueByUnwrappingWeakVariables:value]];
        if (sub && parts.count > 1) {
            [sub addLinkToReference:reference path:[[parts subarrayFromIndex:1] componentsJoinedByString:@"."]];
        }
    } else {
        [self addWeakReferenceToLinkTable:_unresolvedLinks toObject:reference forKey:parts.firstObject];
    }
}

- (BOOL)hasLinkToReference:(iTermVariableReference *)reference
                      path:(NSString *)path {
    NSArray<NSString *> *parts = [path componentsSeparatedByString:@"."];
    id value = _values[parts.firstObject];
    if (!value) {
        return [_unresolvedLinks[path].allObjects containsObject:reference];
    }
    iTermVariables *sub = [iTermVariables castFrom:[self valueByUnwrappingWeakVariables:value]];
    if (sub && parts.count > 1) {
        return [sub hasLinkToReference:reference path:[[parts subarrayFromIndex:1] componentsJoinedByString:@"."]];
    }
    return [_resolvedLinks[path].allObjects containsObject:reference];
}

- (void)removeLinkToReference:(iTermVariableReference *)reference
                         path:(NSString *)path {
    [self removeWeakReferenceFromLinkTable:_resolvedLinks toObject:reference forKey:path];
    [self removeWeakReferenceFromLinkTable:_unresolvedLinks toObject:reference forKey:path];
}

- (NSArray<NSString *> *)allNames {
    return _values.allKeys;
}

#pragma mark - Private

- (void)didChangeNonterminalValueWithPath:(NSString *)name {
    NSArray<iTermVariableReference *> *refs = [self strongArrayFromWeakArray:_resolvedLinks[name]];
    [_resolvedLinks removeObjectForKey:name];
    for (iTermVariableReference *ref in refs) {
        [ref invalidate];
    }

    refs = [self strongArrayFromWeakArray:_unresolvedLinks[name]];
    [_unresolvedLinks removeObjectForKey:name];
    for (iTermVariableReference *ref in refs) {
        [ref invalidate];
    }
}

// This is useful for debugging purposes.
- (NSString *)linksDescription {
    return [[_resolvedLinks.allKeys mapWithBlock:^NSString *(NSString *key) {
        NSArray<iTermVariableReference *> *refs = [self strongArrayFromWeakArray:self->_resolvedLinks[key]];
        NSString *refsString = [[refs mapWithBlock:^id(iTermVariableReference *ref) {
            return [NSString stringWithFormat:@"%@=%p", ref.path, (__bridge void *)ref.onChangeBlock];
        }] componentsJoinedByString:@", "];
        return [NSString stringWithFormat:@"%@ -> %@", key, refsString];
    }] componentsJoinedByString:@"\n"];
}

- (void)didChangeTerminalValueWithPath:(NSString *)name {
    NSArray<iTermVariableReference *> *refs = [self strongArrayFromWeakArray:_resolvedLinks[name]];
    for (iTermVariableReference *ref in refs) {
        [ref valueDidChange];
    }

    refs = [self strongArrayFromWeakArray:_unresolvedLinks[name]];
    [_unresolvedLinks removeObjectForKey:name];
    for (iTermVariableReference *ref in refs) {
        [ref invalidate];
    }
}

- (NSArray *)strongArrayFromWeakArray:(NSPointerArray *)weakArray {
    NSMutableArray *result = [NSMutableArray array];
    for (NSInteger i = 0; i < weakArray.count; i++) {
        void *pointer = [weakArray pointerAtIndex:i];
        if (!pointer) {
            continue;
        }
        [result addObject:(__bridge id _Nonnull)(pointer)];
    }
    return result;
}

- (void)addWeakReferenceToLinkTable:(NSMutableDictionary<NSString *, NSPointerArray *> *)linkTable
                           toObject:(iTermVariableReference *)reference
                             forKey:(NSString *)localPath {
    NSPointerArray *array = linkTable[localPath];
    if (!array) {
        array = [NSPointerArray weakObjectsPointerArray];
        linkTable[localPath] = array;
    }
    [array addPointer:(__bridge void * _Nullable)(reference)];
}

- (void)removeWeakReferenceFromLinkTable:(NSMutableDictionary<NSString *, NSPointerArray *> *)linkTable
                                toObject:(iTermVariableReference *)reference
                                  forKey:(NSString *)localPath {
    NSPointerArray *array = linkTable[localPath];
    for (NSInteger i = (NSInteger)array.count - 1; i >= 0; i--) {
        void *pointer = [array pointerAtIndex:i];
        if (pointer == (__bridge void *)(reference)) {
            [array removePointerAtIndex:i];
        }
    }
    [array compact];
    if (array.count == 0) {
        [linkTable removeObjectForKey:localPath];
    }
}

- (nullable iTermVariables *)setValue:(id)value forVariableNamed:(NSString *)name withSideEffects:(BOOL)sideEffects weak:(BOOL)weak {
    if (name.length == 0) {
        return nil;
    }

    // If name refers to a variable of a child, go down a level.
    NSArray<NSString *> *parts = [name componentsSeparatedByString:@"."];
    if (parts.count > 1) {
        iTermVariables *child = [iTermVariables castFrom:[self valueByUnwrappingWeakVariables:_values[parts.firstObject]]];
        if (!child) {
            return nil;
        }
        return [child setValue:value
              forVariableNamed:[[parts subarrayFromIndex:1] componentsJoinedByString:@"."]
               withSideEffects:sideEffects
                          weak:weak];
    }

    const BOOL changed = ![NSObject object:value isEqualToObject:[self valueByUnwrappingWeakVariables:_values[name]]];
    if (!changed) {
        return nil;
    }
    iTermVariables *child = [iTermVariables castFrom:value];
    if (child && !weak) {
        child->_parentName = [name copy];
        child->_parent = self;
    }
    if (value && ![NSNull castFrom:value]) {
        if ([value isKindOfClass:[iTermVariables class]]) {
            if (weak) {
                _values[name] = [[iTermWeakVariables alloc] initWithVariables:value];
            } else {
                _values[name] = value;
            }
            DLog(@"Assigned %@ = %@ for %@", name, value, self);
            [self didChangeNonterminalValueWithPath:name];
        } else {
            DLog(@"Set variable %@ = %@ (%@)", name, value, self);
            const BOOL wasVariables = [[self valueByUnwrappingWeakVariables:_values[name]] isKindOfClass:[iTermVariables class]];
            _values[name] = [value copy];
            DLog(@"Assigned %@ = %@ for %@", name, value, self);
            if (wasVariables) {
                [self didChangeNonterminalValueWithPath:name];
            } else {
                [self didChangeTerminalValueWithPath:name];
            }
        }
    } else {
        DLog(@"Unset variable %@ (%@)", name, self);
        DLog(@"Assigned %@ = %@ for %@", name, nil, self);
        const BOOL wasVariables = [[self valueByUnwrappingWeakVariables:_values[name]] isKindOfClass:[iTermVariables class]];
        [_values removeObjectForKey:name];
        if (wasVariables) {
            [self didChangeNonterminalValueWithPath:name];
        } else {
            [self didChangeTerminalValueWithPath:name];
        }
    }

    if ([value isKindOfClass:[iTermVariables class]] || [value isKindOfClass:[iTermWeakVariables class]]) {
        // Don't record the use of nonterminals.
        return self;
    }
    [self didReferenceVariables:@[ [iTermTriple tripleWithObject:@1 andObject:self object:name] ]];
    return self;
}

// TODO: This is way more complex than it needs to be. It used to batch notify owners of changes but
// I removed the delegate interface. I don't think the batching logic is needed any more, but this
// commit is already too large.
- (void)didReferenceVariables:(NSArray<iTermVariablesDepthOwnerNamesTriple *> *)mutations {
    [self enumerateMutationsByOwnersByDepth:mutations block:^(iTermVariables *owner, NSSet<NSString *> *nameSet) {
        [owner recordUseOfVariables:nameSet];
    }];
}

- (void)enumerateMutationsByOwnersByDepth:(NSArray<iTermVariablesDepthOwnerNamesTriple *> *)mutations
                                    block:(void (^)(iTermVariables *owner, NSSet<NSString *> *names))block {
    [self enumerateMutationsByDepth:mutations block:^(NSArray<iTermVariablesDepthOwnerNamesTriple *> *isodepthTriples) {
        [self enumerateOwners:isodepthTriples block:^(iTermVariables *owner, NSArray<NSString *> *names) {
            NSSet *uniqueNames =  [NSSet setWithArray:[names mapWithBlock:^id(NSString *anObject) {
                return [[anObject componentsSeparatedByString:@"."] lastObject];
            }]];
            block(owner, uniqueNames);
        }];
    }];
}

// Calls the block for each distinct depth, from deepest to shallowest
- (void)enumerateMutationsByDepth:(NSArray<iTermVariablesDepthOwnerNamesTriple *> *)mutations
                            block:(void (^)(NSArray<iTermVariablesDepthOwnerNamesTriple *> *isodepthTriple))block {
    NSDictionary<NSNumber *, NSArray<iTermVariablesDepthOwnerNamesTriple *> *> *byDepth;
    byDepth = [mutations classifyWithBlock:^id(iTermVariablesDepthOwnerNamesTriple *triple) {
        return triple.firstObject;
    }];

    // Iterate from deepest to shallowest
    NSArray<NSNumber *> *sortedDepths = [byDepth.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (NSNumber *number in [sortedDepths reverseObjectEnumerator]) {
        block(byDepth[number]);
    }
}

- (void)enumerateOwners:(NSArray<iTermVariablesDepthOwnerNamesTriple *> *)mutations
                  block:(void (^)(iTermVariables *owner, NSArray<NSString *> *names))block {
    NSDictionary<NSValue *, NSArray<iTermVariablesDepthOwnerNamesTriple *> *> *byOwner;
    byOwner = [mutations classifyWithBlock:^id(iTermVariablesDepthOwnerNamesTriple *triple) {
        return [NSValue valueWithNonretainedObject:triple.secondObject];
    }];
    [byOwner enumerateKeysAndObjectsUsingBlock:^(NSValue * _Nonnull ownerValue, NSArray<iTermVariablesDepthOwnerNamesTriple *> * _Nonnull triples, BOOL * _Nonnull stop) {
        NSArray<NSString *> *names = [triples mapWithBlock:^id(iTermVariablesDepthOwnerNamesTriple *anObject) {
            return anObject.thirdObject;
        }];
        iTermVariables *owner = ownerValue.nonretainedObjectValue;
        block(owner, names);
    }];
}

+ (NSSet<NSString *> *)namesToRecordFromSet:(NSSet<NSString *> *)names inContext:(iTermVariablesSuggestionContext)context {
    static NSMutableDictionary<NSNumber *, NSMutableSet *> *seen;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        seen = [NSMutableDictionary dictionary];
        seen[@(iTermVariablesSuggestionContextSession)] = [NSMutableSet set];
        seen[@(iTermVariablesSuggestionContextTab)] = [NSMutableSet set];
        seen[@(iTermVariablesSuggestionContextWindow)] = [NSMutableSet set];
        seen[@(iTermVariablesSuggestionContextApp)] = [NSMutableSet set];
    });
    // Make a copy to avoid modifying during enumeration.
    NSMutableSet *set = [seen[@(context)] mutableCopy];
    ITAssertWithMessage(set, @"Bogus context %@", @(context));
    NSMutableSet<NSString *> *result = [names mutableCopy];
    [result minusSet:set];
    [set unionSet:result];
    seen[@(context)] = set;
    return result;
}

- (void)recordUseOfVariables:(NSSet<NSString *> *)allNames {
    if (_context != iTermVariablesSuggestionContextNone) {
        NSSet<NSString *> *names = [iTermVariables namesToRecordFromSet:allNames inContext:_context];
        if (names.count == 0) {
            return;
        }
        [names enumerateObjectsUsingBlock:^(NSString * _Nonnull name, BOOL * _Nonnull stop) {
            if (![[self valueByUnwrappingWeakVariables:self->_values[name]] isKindOfClass:[iTermVariables class]]) {
                [iTermVariableHistory recordUseOfVariableNamed:name inContext:self->_context];
            }
        }];
    }

    if (_parent && _parentName) {
        [_parent recordUseOfVariables:[self namesByPrependingParentName:allNames]];
    }
}

- (NSSet<NSString *> *)namesByPrependingParentName:(NSSet<NSString *> *)names {
    NSString *parentName = _parentName;
    return [NSSet setWithArray:[names.allObjects mapWithBlock:^id(NSString *anObject) {
        return [NSString stringWithFormat:@"%@.%@", parentName, anObject];
    }]];;
}

- (NSDictionary<NSString *,NSString *> *)stringValuedDictionary {
    return [self stringValuedDictionaryInScope:nil];
}

- (NSDictionary<NSString *,NSString *> *)stringValuedDictionaryInScope:(nullable NSString *)scopeName {
    NSMutableDictionary<NSString *, NSString *> *result = [NSMutableDictionary dictionary];
    for (NSString *name in _values) {
        id value = _values[name];
        if ([value isKindOfClass:[iTermWeakVariables class]]) {
            // Avoid cycles.
            continue;
        }
        iTermVariables *child = [iTermVariables castFrom:value];
        if (child) {
            [result it_mergeFrom:[child.stringValuedDictionary mapKeysWithBlock:^id(NSString *key, NSString *object) {
                if (scopeName) {
                    return [NSString stringWithFormat:@"%@.%@.%@", scopeName, name, key];
                } else {
                    return [NSString stringWithFormat:@"%@.%@", name, key];
                }
            }]];
        } else {
            NSString *scopedName = name;
            if (scopeName) {
                scopedName = [NSString stringWithFormat:@"%@.%@", scopeName, name];
            }
            result[scopedName] = [self stringValueForVariableName:name];
        }
    }
    return result;
}

- (NSDictionary<NSString *, id> *)dictionaryInScope:(nullable NSString *)scopeName {
    NSMutableDictionary<NSString *, NSString *> *result = [NSMutableDictionary dictionary];
    for (NSString *name in _values) {
        id value = _values[name];
        // Weak variables are intentionally not unwrapped here to avoid getting stuck in a cycle.
        iTermVariables *child = [iTermVariables castFrom:value];
        if (child) {
            [result it_mergeFrom:[[child dictionaryInScope:nil] mapKeysWithBlock:^id(NSString *key, id object) {
                if (scopeName) {
                    return [NSString stringWithFormat:@"%@.%@.%@", scopeName, name, key];
                } else {
                    return [NSString stringWithFormat:@"%@.%@", name, key];
                }
            }]];
        } else {
            NSString *scopedName = name;
            if (scopeName) {
                scopedName = [NSString stringWithFormat:@"%@.%@", scopeName, name];
            }
            result[scopedName] = value;
        }
    }
    return result;
}

- (NSDictionary *)dictionaryValue {
    return [self dictionaryInScope:nil];
}

@end


NS_ASSUME_NONNULL_END
