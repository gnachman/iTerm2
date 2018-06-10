//
//  iTermVariables.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import "iTermVariables.h"

#import "iTermTuple.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

NS_ASSUME_NONNULL_BEGIN

typedef iTermTriple<NSNumber *, iTermVariables *, NSString *> iTermVariablesDepthOwnerNamesTriple;

static NSString *const iTermVariablesGlobalScopePrefix = @"iterm2.";

NSString *const iTermVariableKeyApplicationPID = @"iterm2.pid";
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
NSString *const iTermVariableKeyTermID = @"session.termid";
#warning TODO document these and verify they get updated
NSString *const iTermVariableKeySessionBackingProfileName = @"session.backingProfileName";
NSString *const iTermVariableKeySessionProfileName = @"session.profileName";
NSString *const iTermVariableKeySessionIconName = @"session.terminalIconName";
NSString *const iTermVariableKeySessionTriggerName = @"session.triggerName";
NSString *const iTermVariableKeySessionWindowName = @"session.terminalWindowName";
NSString *const iTermVariableKeySessionJob = @"session.jobName";
NSString *const iTermVariableKeySessionPresentationName = @"session.presentationName";
NSString *const iTermVariableKeySessionTmuxWindowTitle = @"session.tmuxWindowTitle";
NSString *const iTermVariableKeySessionAutoName = @"session.autoName";

static NSMutableSet<NSString *> *iTermVariablesGetMutableSet() {
    static NSMutableSet<NSString *> *userDefined;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *systemDefined =
            @[ iTermVariableKeyApplicationPID,
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
               iTermVariableKeyTermID ];
        userDefined = [NSMutableSet setWithArray:systemDefined];
    });
    return userDefined;
}

NSArray<NSString *> *iTermVariablesGetAll(void) {
    return [iTermVariablesGetMutableSet() allObjects];
}

#warning TODO: remove this hack and use the variables in scope for suggestions
static void iTermVariablesAdd(NSString *variable) {
    [iTermVariablesGetMutableSet() addObject:variable];
}

@implementation iTermVariables {
    NSMutableDictionary<NSString *, id> *_values;
    __weak iTermVariables *_parent;
    NSString *_parentName;
}

+ (instancetype)globalInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _values = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - APIs

- (NSDictionary<NSString *,NSString *> *)legacyDictionary {
    if (self == [iTermVariables globalInstance]) {
        return self.legacyDictionaryExcludingGlobals;
    }

    iTermVariables *globals = [iTermVariables globalInstance];
    NSDictionary<NSString *, NSString *> *globalsDict = [globals legacyDictionaryExcludingGlobalsAnd:self];
    globalsDict = [globalsDict mapKeysWithBlock:^NSString *(NSString *key, NSString *object) {
        return [iTermVariablesGlobalScopePrefix stringByAppendingString:key];
    }];
    return [self.legacyDictionaryExcludingGlobals dictionaryByMergingDictionary:globalsDict];
}

- (NSDictionary<NSString *,NSString *> *)legacyDictionaryExcludingGlobals {
    return [self legacyDictionaryExcludingGlobalsAnd:nil];
}

- (id (^)(NSString *))functionCallSource {
    return ^id (NSString *name) {
        return [self valueForVariableName:name];
    };
}

- (BOOL)setValue:(nullable id)value forVariableNamed:(NSString *)name {
    NSString *globalName = [self nameByRemovingGlobalPrefix:name];
    if (globalName) {
        return [[iTermVariables globalInstance] setValue:value
                                        forVariableNamed:globalName];
    }

    iTermVariables *owner = [self setValue:value forVariableNamed:name withSideEffects:YES];
    return owner != nil;
}

- (BOOL)setValuesFromDictionary:(NSDictionary<NSString *, id> *)dict {
    NSMutableArray<iTermVariablesDepthOwnerNamesTriple *> *mutations;
    for (NSString *name in dict) {
        id value = dict[name];
        iTermVariables *owner = nil;
        NSString *globalName = [self nameByRemovingGlobalPrefix:name];
        NSInteger depth = 0;
        if (globalName) {
            owner = [[iTermVariables globalInstance] setValue:value
                                             forVariableNamed:globalName
                                              withSideEffects:NO];
            depth = -1;
        } else {
            owner = [self setValue:value forVariableNamed:name withSideEffects:NO];
            if (owner) {
                depth = [[name componentsSeparatedByString:@"."] count];
            }
        }
        if (owner) {
            [mutations addObject:[iTermTriple tripleWithObject:@(depth) andObject:owner object:name]];
        }
    }
    if (!mutations.count) {
        return NO;
    }

    [self batchNotifyOwnerForMutationsByDepth:mutations];
    return YES;
}

- (id)valueForVariableName:(NSString *)name {
    NSString *globalName = [self nameByRemovingGlobalPrefix:name];
    if (globalName) {
        return [[iTermVariables globalInstance] valueForVariableName:globalName];
    }

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

#pragma mark - Private

- (NSString *)nameByRemovingGlobalPrefix:(NSString *)name {
    if ([name hasPrefix:iTermVariablesGlobalScopePrefix]) {
        return [name substringFromIndex:[iTermVariablesGlobalScopePrefix length]];
    } else {
        return nil;
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
        } else {
            _values[name] = [value copy];
        }
        iTermVariablesAdd(name);
    } else {
        [_values removeObjectForKey:name];
    }

    [self batchNotifyOwnerForMutationsByDepth:@[ [iTermTriple tripleWithObject:@1 andObject:self object:name] ]];
    return self;
}

- (void)batchNotifyOwnerForMutationsByDepth:(NSArray<iTermVariablesDepthOwnerNamesTriple *> *)mutations {
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    [self enumerateMutationsByOwnersByDepth:mutations block:^(iTermVariables *owner, NSSet<NSString *> *nameSet) {
        [owner notifyDelegateChainOfChangedNames:nameSet group:group];
    }];
    dispatch_group_leave(group);
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

- (void)notifyDelegateChainOfChangedNames:(NSSet<NSString *> *)names
                                    group:(dispatch_group_t)group {
    [self.delegate variables:self didChangeValuesForNames:names group:group];
    if (_parent && _parentName) {
        [_parent notifyDelegateChainOfChangedNames:[self namesByPrependingParentName:names] group:group];
    }
}

- (NSSet<NSString *> *)namesByPrependingParentName:(NSSet<NSString *> *)names {
    NSString *parentName = _parentName;
    return [NSSet setWithArray:[names.allObjects mapWithBlock:^id(NSString *anObject) {
        return [NSString stringWithFormat:@"%@.%@", parentName, anObject];
    }]];;
}

- (NSDictionary<NSString *,NSString *> *)legacyDictionaryExcludingGlobalsAnd:(nullable iTermVariables *)exclusion {
    iTermVariables *globals = [iTermVariables globalInstance];
    NSMutableDictionary<NSString *, NSString *> *result = [NSMutableDictionary dictionary];
    for (NSString *name in _values) {
        id value = _values[name];
        iTermVariables *child = [iTermVariables castFrom:value];
        if (child) {
            if (child == globals || child == exclusion) {
                continue;
            }
            [result it_mergeFrom:[child.legacyDictionaryExcludingGlobals mapKeysWithBlock:^id(NSString *key, NSString *object) {
                return [NSString stringWithFormat:@"%@.%@", name, key];
            }]];
        } else {
            result[name] = value;
        }
    }
    return result;
}

@end

NS_ASSUME_NONNULL_END
