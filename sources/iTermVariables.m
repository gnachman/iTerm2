//
//  iTermVariables.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import "iTermVariables.h"

#import "DebugLogging.h"
#import "iTermTuple.h"
#import "iTermVariableReference.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

NS_ASSUME_NONNULL_BEGIN

typedef iTermTriple<NSNumber *, iTermVariables *, NSString *> iTermVariablesDepthOwnerNamesTriple;

NSString *const iTermVariableKeyGlobalScopeName = @"iterm2";

NSString *const iTermVariableKeyApplicationPID = @"pid";
NSString *const iTermVariableKeyApplicationLocalhostName = @"localhostName";
NSString *const iTermVariableKeyApplicationEffectiveTheme = @"effectiveTheme";

NSString *const iTermVariableKeyTabTitleOverride = @"titleOverride";
NSString *const iTermVariableKeyTabCurrentSession = @"currentSession";
NSString *const iTermVariableKeyTabTmuxWindow = @"tmuxWindow";

NSString *const iTermVariableKeySessionAutoLogID = @"session.autoLogId";
NSString *const iTermVariableKeySessionColumns = @"session.columns";
NSString *const iTermVariableKeySessionCreationTimeString = @"session.creationTimeString";
NSString *const iTermVariableKeySessionHostname = @"session.hostname";
NSString *const iTermVariableKeySessionID = @"session.id";
NSString *const iTermVariableKeySessionLastCommand = @"session.lastCommand";
NSString *const iTermVariableKeySessionPath = @"session.path";
NSString *const iTermVariableKeySessionName = @"session.name";
NSString *const iTermVariableKeySessionRows = @"session.rows";
NSString *const iTermVariableKeySessionTTY = @"session.tty";
NSString *const iTermVariableKeySessionUsername = @"session.username";
NSString *const iTermVariableKeySessionTermID = @"session.termid";
NSString *const iTermVariableKeySessionProfileName = @"session.profileName";
NSString *const iTermVariableKeySessionIconName = @"session.terminalIconName";
NSString *const iTermVariableKeySessionTriggerName = @"session.triggerName";
NSString *const iTermVariableKeySessionWindowName = @"session.terminalWindowName";
NSString *const iTermVariableKeySessionJob = @"session.jobName";
NSString *const iTermVariableKeySessionPresentationName = @"session.presentationName";
NSString *const iTermVariableKeySessionTmuxWindowTitle = @"session.tmuxWindowTitle";
NSString *const iTermVariableKeySessionTmuxRole = @"session.tmuxRole";
NSString *const iTermVariableKeySessionTmuxClientName = @"session.tmuxClientName";
NSString *const iTermVariableKeySessionAutoName = @"session.autoName";
NSString *const iTermVariableKeySessionTmuxWindowPane = @"session.tmuxWindowPane";
NSString *const iTermVariableKeySessionJobPid = @"session.jobPid";
NSString *const iTermVariableKeySessionChildPid = @"session.pid";
NSString *const iTermVariableKeySessionTmuxStatusLeft = @"session.tmuxStatusLeft";
NSString *const iTermVariableKeySessionTmuxStatusRight = @"session.tmuxStatusRight";
NSString *const iTermVariableKeySessionMouseReportingMode = @"session.mouseReportingMode";

NSString *const iTermVariableKeyWindowTitleOverride = @"titleOverride";
NSString *const iTermVariableKeyWindowCurrentTab = @"currentTab";

// NOTE: If you add here, also update +recordBuiltInVariables

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

+ (void)recordBuiltInVariables {
    // Session context
    NSArray<NSString *> *names = @[ iTermVariableKeyGlobalScopeName,
                                    iTermVariableKeySessionAutoLogID,
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
                                    iTermVariableKeySessionAutoName,
                                    iTermVariableKeySessionTmuxWindowPane,
                                    iTermVariableKeySessionJobPid,
                                    iTermVariableKeySessionChildPid,
                                    iTermVariableKeySessionMouseReportingMode,
                                    iTermVariableKeySessionTmuxStatusLeft,
                                    iTermVariableKeySessionTmuxStatusRight ];
    [names enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [self recordUseOfVariableNamed:obj inContext:iTermVariablesSuggestionContextSession];
    }];

    // Tab context
    [self recordUseOfVariableNamed:iTermVariableKeyTabTitleOverride inContext:iTermVariablesSuggestionContextTab];
    [self recordUseOfVariableNamed:iTermVariableKeyTabCurrentSession inContext:iTermVariablesSuggestionContextTab];
    [self recordUseOfVariableNamed:iTermVariableKeyTabTmuxWindow inContext:iTermVariablesSuggestionContextTab];
    [self recordUseOfVariableNamed:iTermVariableKeyGlobalScopeName inContext:iTermVariablesSuggestionContextTab];

    // Window context
    [self recordUseOfVariableNamed:iTermVariableKeyWindowTitleOverride inContext:iTermVariablesSuggestionContextWindow];
    [self recordUseOfVariableNamed:iTermVariableKeyWindowCurrentTab inContext:iTermVariablesSuggestionContextWindow];
    [self recordUseOfVariableNamed:iTermVariableKeyGlobalScopeName inContext:iTermVariablesSuggestionContextWindow];

    // App context
    [self recordUseOfVariableNamed:iTermVariableKeyApplicationPID inContext:iTermVariablesSuggestionContextApp];
    [self recordUseOfVariableNamed:iTermVariableKeyApplicationLocalhostName inContext:iTermVariablesSuggestionContextApp];
    [self recordUseOfVariableNamed:iTermVariableKeyApplicationEffectiveTheme inContext:iTermVariablesSuggestionContextApp];
}

+ (NSMutableDictionary<NSNumber *, NSMutableSet<NSString *> *> *)mutableRecordedNames {
    static NSMutableDictionary<NSNumber *, NSMutableSet<NSString *> *> *records;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSDictionary *dict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"NoSyncRecordedVariableNames"] ?: @{};
        records = [NSMutableDictionary dictionary];
        for (id key in dict) {
            NSString *stringContext = [NSString castFrom:key];
            if (!stringContext) {
                continue;
            }
            NSNumber *context = @([stringContext integerValue]);
            NSArray<NSString *> *names = [NSArray castFrom:dict[key]];
            if (!names) {
                continue;
            }
            records[context] = [NSMutableSet setWithArray:names];
        }
    });
    return records;
}

+ (void)synchronizeRecordedNames {
    NSDictionary *plist = [[self mutableRecordedNames] mapValuesWithBlock:^id(NSNumber *key, NSMutableSet<NSString *> *object) {
        return object.allObjects;
    }];
    plist = [plist mapKeysWithBlock:^id(id key, id object) {
        return [key stringValue];
    }];
    [[NSUserDefaults standardUserDefaults] setObject:plist forKey:@"NoSyncRecordedVariableNames"];
}

+ (NSMutableSet<NSString *> *)mutableRecordedVariableNamesInContext:(iTermVariablesSuggestionContext)context {
    NSMutableSet<NSString *> *set = self.mutableRecordedNames[@(context)];
    if (!set) {
        set = [NSMutableSet set];
        self.mutableRecordedNames[@(context)] = set;
    }
    return set;
}

+ (NSSet<NSString *> *)recordedVariableNamesInContext:(iTermVariablesSuggestionContext)context {
    NSSet<NSString *> *result = [NSSet set];
    for (int bit = 0; bit < 64; bit++) {
        const NSUInteger one = 1;
        NSUInteger mask = one << bit;
        if (mask & context) {
            result = [result setByAddingObjectsFromSet:self.mutableRecordedNames[@(mask)] ?: [NSSet set]];
        }
    }
    if ((context & (iTermVariablesSuggestionContextSession | iTermVariablesSuggestionContextTab)) &&
        !(context & iTermVariablesSuggestionContextApp)) {
        NSSet<NSString *> *appVariables = [self recordedVariableNamesInContext:iTermVariablesSuggestionContextApp];
        result = [NSSet setWithArray:[result.allObjects arrayByAddingObjectsFromArray:[appVariables.allObjects mapWithBlock:^id(NSString *appVariable) {
            return [@"iterm2." stringByAppendingString:appVariable];
        }]]];
    }
    return result;
}

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

+ (void)recordUseOfVariableNamed:(NSString *)name
                       inContext:(iTermVariablesSuggestionContext)context {
    NSMutableSet<NSString *> *names = [self mutableRecordedVariableNamesInContext:context];
    if (![names containsObject:name]) {
        DLog(@"Record %@ in context %@", name, [self stringForContext:context]);
        [names addObject:name];
        [self synchronizeRecordedNames];
    }
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
            [iTermVariables recordBuiltInVariables];
        });
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p owner=%@>", self.class, self, self.owner];
}

#pragma mark - APIs

- (BOOL)setValue:(nullable id)value forVariableNamed:(NSString *)name {
    iTermVariables *owner = [self setValue:value forVariableNamed:name withSideEffects:YES];
    return owner != nil;
}

- (BOOL)setValuesFromDictionary:(NSDictionary<NSString *, id> *)dict {
    NSMutableArray<iTermVariablesDepthOwnerNamesTriple *> *mutations;
    for (NSString *name in dict) {
        id value = dict[name];
        iTermVariables *owner = nil;
        owner = [self setValue:value forVariableNamed:name withSideEffects:NO];
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

- (id)discouragedValueForVariableName:(NSString *)name {
    return [self valueForVariableName:name];
}

- (id)valueForVariableName:(NSString *)name {
    if (_values[name]) {
        return _values[name];
    }
    NSArray<NSString *> *parts = [name componentsSeparatedByString:@"."];
    if (parts.count <= 1) {
        return nil;
    }
    iTermVariables *child = [iTermVariables castFrom:_values[parts.firstObject]];
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
        iTermVariables *sub = [iTermVariables castFrom:value];
        if (sub && parts.count > 1) {
            [sub addLinkToReference:reference path:[[parts subarrayFromIndex:1] componentsJoinedByString:@"."]];
        }
    } else {
        [self addWeakReferenceToLinkTable:_unresolvedLinks toObject:reference forKey:parts.firstObject];
    }
}

- (void)removeLinkToReference:(iTermVariableReference *)reference
                         path:(NSString *)path {
    [self removeWeakReferenceFromLinkTable:_resolvedLinks toObject:reference forKey:path];
    [self removeWeakReferenceFromLinkTable:_unresolvedLinks toObject:reference forKey:path];
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

- (iTermVariables *)setValue:(id)value forVariableNamed:(NSString *)name withSideEffects:(BOOL)sideEffects {
    assert(name.length > 0);

    // If name refers to a variable of a child, go down a level.
    NSArray<NSString *> *parts = [name componentsSeparatedByString:@"."];
    if (parts.count > 1) {
        iTermVariables *child = [iTermVariables castFrom:_values[parts.firstObject]];
        if (!child) {
            return nil;
        }
        return [child setValue:value
              forVariableNamed:[[parts subarrayFromIndex:1] componentsJoinedByString:@"."]
               withSideEffects:sideEffects];
    }

    const BOOL changed = ![NSObject object:value isEqualToObject:_values[name]];
    if (!changed) {
        return nil;
    }
    iTermVariables *child = [iTermVariables castFrom:value];
    if (child) {
        child->_parentName = [name copy];
        child->_parent = self;
    }
    if (value && ![NSNull castFrom:value]) {
        if ([value isKindOfClass:[iTermVariables class]]) {
            _values[name] = value;
            [self didChangeNonterminalValueWithPath:name];
        } else {
            DLog(@"Set variable %@ = %@ (%@)", name, value, self);
            const BOOL wasVariables = [_values[name] isKindOfClass:[iTermVariables class]];
            _values[name] = [value copy];
            if (wasVariables) {
                [self didChangeNonterminalValueWithPath:name];
            } else {
                [self didChangeTerminalValueWithPath:name];
            }
        }
    } else {
        DLog(@"Unset variable %@ (%@)", name, self);
        const BOOL wasVariables = [_values[name] isKindOfClass:[iTermVariables class]];
        [_values removeObjectForKey:name];
        if (wasVariables) {
            [self didChangeNonterminalValueWithPath:name];
        } else {
            [self didChangeTerminalValueWithPath:name];
        }
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

- (void)recordUseOfVariables:(NSSet<NSString *> *)names {
    if (_context != iTermVariablesSuggestionContextNone) {
        [names enumerateObjectsUsingBlock:^(NSString * _Nonnull name, BOOL * _Nonnull stop) {
            if (![self->_values[name] isKindOfClass:[iTermVariables class]]) {
                [iTermVariables recordUseOfVariableNamed:name inContext:self->_context];
            }
        }];
    }

    if (_parent && _parentName) {
        [_parent recordUseOfVariables:[self namesByPrependingParentName:names]];
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

@implementation iTermVariableScope {
    NSMutableArray<iTermTuple<NSString *, iTermVariables *> *> *_frames;
    // References to paths without an owner. This normally only happens when a session is being
    // shut down (e.g, tab.currentSession is assigned to nil)
    NSPointerArray *_danglingReferences;
}

+ (instancetype)globalsScope {
    iTermVariableScope *scope = [[iTermVariableScope alloc] init];
    [scope addVariables:[iTermVariables globalInstance] toScopeNamed:nil];
    return scope;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _frames = [NSMutableArray array];
        _danglingReferences = [NSPointerArray weakObjectsPointerArray];
    }
    return self;
}

- (void)addVariables:(iTermVariables *)variables toScopeNamed:(nullable NSString *)scopeName {
    [_frames insertObject:[iTermTuple tupleWithObject:scopeName andObject:variables] atIndex:0];
    [self resolveDanglingReferences];
}

- (void)enumerateVariables:(void (^)(NSString * _Nonnull, iTermVariables * _Nonnull))block {
    [_frames enumerateObjectsUsingBlock:^(iTermTuple<NSString *,iTermVariables *> * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        block(obj.firstObject, obj.secondObject);
    }];
}

- (NSDictionary<NSString *, NSString *> *)dictionaryWithStringValues {
    NSMutableDictionary<NSString *, NSString *> *result = [NSMutableDictionary dictionary];
    [self enumerateVariables:^(NSString * _Nonnull scopeName, iTermVariables * _Nonnull variables) {
        [result it_mergeFrom:[variables stringValuedDictionaryInScope:scopeName]];
    }];
    return result;
}

- (id)valueForVariableName:(NSString *)name {
    NSString *stripped = nil;
    iTermVariables *owner = [self ownerForKey:name stripped:&stripped];
    return [owner valueForVariableName:stripped];
}

- (NSString *)stringValueForVariableName:(NSString *)name {
    NSString *stripped = nil;
    iTermVariables *owner = [self ownerForKey:name stripped:&stripped];
    return [owner stringValueForVariableName:name] ?: @"";
}

- (iTermVariables *)ownerForKey:(NSString *)key stripped:(out NSString **)stripped {
    NSArray<NSString *> *parts = [key componentsSeparatedByString:@"."];
    if (parts.count == 0) {
        return nil;
    }
    if (parts.count == 1) {
        *stripped = key;
        return [_frames objectPassingTest:^BOOL(iTermTuple<NSString *,iTermVariables *> *element, NSUInteger index, BOOL *stop) {
            return element.firstObject == nil;
        }].secondObject;
    }
    __block NSString *strippedOut = nil;
    iTermVariables *owner = [_frames objectPassingTest:^BOOL(iTermTuple<NSString *,iTermVariables *> *element, NSUInteger index, BOOL *stop) {
        if (element.firstObject == nil && [element.secondObject valueForVariableName:parts[0]]) {
            strippedOut = key;
            return YES;
        } else {
            strippedOut = [[parts subarrayFromIndex:1] componentsJoinedByString:@"."];
            return [element.firstObject isEqualToString:parts[0]];
        }
    }].secondObject;
    *stripped = strippedOut;
    return owner;
}

- (BOOL)setValuesFromDictionary:(NSDictionary<NSString *, id> *)dict {
    // Transform dict from {name: object} to {owner: {stripped_name: object}}
    NSMutableDictionary<NSValue *, NSMutableDictionary<NSString *, id> *> *valuesByOwner = [NSMutableDictionary dictionary];
    for (NSString *key in dict) {
        id object = dict[key];
        NSString *stripped = nil;
        iTermVariables *owner = [self ownerForKey:key stripped:&stripped];
        NSValue *value = [NSValue valueWithNonretainedObject:owner];
        NSMutableDictionary *inner = valuesByOwner[value];
        if (!inner) {
            inner = [NSMutableDictionary dictionary];
            valuesByOwner[value] = inner;
        }
        inner[stripped] = object;
    }
    __block BOOL changed = NO;
    [valuesByOwner enumerateKeysAndObjectsUsingBlock:^(NSValue * _Nonnull ownerValue, NSDictionary<NSString *,id> * _Nonnull setDict, BOOL * _Nonnull stop) {
        iTermVariables *owner = [ownerValue nonretainedObjectValue];
        if ([owner setValuesFromDictionary:setDict]) {
            changed = YES;
        }
    }];
    if ([dict.allValues anyWithBlock:^BOOL(id anObject) {
        return [anObject isKindOfClass:[iTermVariables class]];
    }]) {
        [self resolveDanglingReferences];
    }
    return changed;
}

- (BOOL)setValue:(nullable id)value forVariableNamed:(NSString *)name {
    NSString *stripped = nil;
    iTermVariables *owner = [self ownerForKey:name stripped:&stripped];
    if (!owner) {
        return NO;
    }
    const BOOL result = [owner setValue:value forVariableNamed:stripped];
    if ([value isKindOfClass:[iTermVariables class]]) {
        [self resolveDanglingReferences];
    }
    return result;
}

- (void)resolveDanglingReferences {
    NSPointerArray *refs = _danglingReferences;
    if (refs.count == 0) {
        return;
    }
    _danglingReferences = [NSPointerArray weakObjectsPointerArray];
    for (NSInteger i = 0; i < refs.count; i++) {
        iTermVariableReference *ref = [refs pointerAtIndex:i];
        if (ref) {
            [self addLinksToReference:ref];
            if (ref.value) {
                [ref valueDidChange];
            }
        }
    }
}

- (void)addLinksToReference:(iTermVariableReference *)reference {
    NSString *tail;
    iTermVariables *variables = [self ownerForKey:reference.path stripped:&tail];
    if (!variables) {
        [_danglingReferences addPointer:(__bridge void * _Nullable)(reference)];
        return;
    }
    [variables addLinkToReference:reference path:tail];
}

- (iTermVariableRecordingScope *)recordingCopy {
    iTermVariableRecordingScope *theCopy = [[iTermVariableRecordingScope alloc] initWithScope:self];
    [_frames enumerateObjectsUsingBlock:^(iTermTuple<NSString *,iTermVariables *> * _Nonnull tuple, NSUInteger idx, BOOL * _Nonnull stop) {
        [theCopy addVariables:tuple.secondObject toScopeNamed:tuple.firstObject];
    }];
    return theCopy;
}

- (id)copyWithZone:(nullable NSZone *)zone {
    iTermVariableScope *theCopy = [[self.class alloc] init];
    [_frames enumerateObjectsUsingBlock:^(iTermTuple<NSString *,iTermVariables *> * _Nonnull tuple, NSUInteger idx, BOOL * _Nonnull stop) {
        [theCopy addVariables:tuple.secondObject toScopeNamed:tuple.firstObject];
    }];
    return theCopy;
}

@end

@implementation iTermVariableRecordingScope {
    NSMutableSet<NSString *> *_names;
    iTermVariableScope *_scope;
}

- (instancetype)initWithScope:(iTermVariableScope *)scope {
    self = [super init];
    if (self) {
        _scope = scope;
    }
    return self;
}

- (id)valueForVariableName:(NSString *)name {
    if (!_names) {
        _names = [NSMutableSet set];
    }

    [_names addObject:name];
    id value = [super valueForVariableName:name];
    if (self.neverReturnNil) {
        return value ?: @"";
    } else {
        return value;
    }
}

- (NSArray<iTermVariableReference *> *)recordedReferences {
    return [_names.allObjects mapWithBlock:^id(NSString *path) {
        return [[iTermVariableReference alloc] initWithPath:path scope:self->_scope];
    }];
}
@end

NS_ASSUME_NONNULL_END
