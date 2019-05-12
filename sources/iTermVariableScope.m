//
//  iTermVariableScope.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/5/19.
//

#import "iTermVariableScope.h"

#import "iTermTuple.h"
#import "iTermVariableReference.h"
#import "iTermVariables.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermVariableDesignator {
    iTermVariables *_variables;
    NSString *_path;
}

- (instancetype)initWithVariables:(iTermVariables *)variables path:(NSString *)path {
    self = [super init];
    if (self) {
        _variables = variables;
        _path = [path copy];
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p path=%@ variables=%@>", NSStringFromClass([self class]), self, _path, _variables];
}

- (NSUInteger)hash {
    return _path.hash;
}

- (BOOL)isEqual:(id)object {
    iTermVariableDesignator *other = [iTermVariableDesignator castFrom:object];
    if (!other) {
        return NO;
    }
    return (_variables == other->_variables &&
            [_path isEqual:other->_path]);
}

- (id)copyWithZone:(nullable NSZone *)zone {
    return self;
}

@end

@interface iTermVariables(Private)
- (NSDictionary<NSString *,NSString *> *)stringValuedDictionaryInScope:(nullable NSString *)scopeName;
- (nullable id)valueForVariableName:(NSString *)name;
- (NSString *)stringValueForVariableName:(NSString *)name;
- (BOOL)hasLinkToReference:(iTermVariableReference *)reference
                      path:(NSString *)path;
- (BOOL)setValuesFromDictionary:(NSDictionary<NSString *, id> *)dict;
- (BOOL)setValue:(nullable id)value forVariableNamed:(NSString *)name weak:(BOOL)weak;
- (void)addLinkToReference:(iTermVariableReference *)reference
                      path:(NSString *)path;
@end

@implementation iTermVariableScope {
    NSMutableArray<iTermTuple<NSString *, iTermVariables *> *> *_frames;
    // References to paths without an owner. This normally only happens when a session is being
    // shut down (e.g, tab.currentSession is assigned to nil)
    NSPointerArray *_danglingReferences;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _frames = [NSMutableArray array];
        _danglingReferences = [NSPointerArray weakObjectsPointerArray];
    }
    return self;
}

- (BOOL)usePlaceholders {
    return NO;
}

- (void)addVariables:(iTermVariables *)variables toScopeNamed:(nullable NSString *)scopeName {
    [_frames insertObject:[iTermTuple tupleWithObject:scopeName andObject:variables] atIndex:0];
    [self resolveDanglingReferences];
}

- (NSArray<iTermVariables *> *)variablesInScopeNamed:(nullable NSString *)scopeName {
    return [_frames mapWithBlock:^id(iTermTuple<NSString *,iTermVariables *> *anObject) {
        if (![NSObject object:scopeName isEqualToObject:anObject.firstObject]) {
            return nil;
        }
        return anObject.secondObject;
    }];
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

- (id)valueForPath:(NSString *)firstName, ... {
    va_list args;
    va_start(args, firstName);
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *name = firstName; name != nil; name = va_arg(args, NSString*)) {
        [parts addObject:name];
    }
    va_end(args);
    return [self valueForVariableName:[parts componentsJoinedByString:@"."]];
}

- (id)valueForVariableName:(NSString *)name {
    NSString *stripped = nil;
    iTermVariables *owner = [self ownerForKey:name forWriting:NO stripped:&stripped];
    return [owner valueForVariableName:stripped];
}

- (NSString *)stringValueForVariableName:(NSString *)name {
    NSString *stripped = nil;
    iTermVariables *owner = [self ownerForKey:name forWriting:NO stripped:&stripped];
    return [owner stringValueForVariableName:name] ?: @"";
}

- (nullable iTermVariables *)ownerForKey:(NSString *)key forWriting:(BOOL)forWriting stripped:(out NSString **)stripped {
    NSArray<NSString *> *parts = [key componentsSeparatedByString:@"."];
    if (parts.count == 0) {
        return nil;
    }
    if (parts.count == 1) {
        *stripped = key;
        if (!forWriting) {
            // Check all anonymous frames in case one of them is a match.
            for (iTermTuple<NSString *,iTermVariables *> *tuple in _frames) {
                if (tuple.firstObject) {
                    continue;
                }
                if ([tuple.secondObject valueForVariableName:key]) {
                    return tuple.secondObject;
                }
            }
        }
        // Writes always go into the most recently added frame.
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

- (nullable iTermVariables *)ownerOfTerminalForPath:(NSString *)path
                                         forWriting:(BOOL)forWriting
                                           terminal:(out NSString **)terminal {
    NSArray<NSString *> *parts = [path componentsSeparatedByString:@"."];
    if (parts.count == 0) {
        return nil;
    }

    NSString *stripped;
    iTermVariables *owner = [self ownerForKey:path forWriting:forWriting stripped:&stripped];
    if (!owner) {
        return nil;
    }

    parts = [stripped componentsSeparatedByString:@"."];
    assert(parts.count > 0);
    while (parts.count > 1) {
        id value = [owner valueForVariableName:parts.firstObject];
        if (value == nil) {
            return nil;
        }
        assert([value isKindOfClass:[iTermVariables class]]);
        owner = value;
        parts = [parts subarrayFromIndex:1];
    }
    *terminal = parts[0];
    return owner;
}

- (BOOL)variableNamed:(NSString *)name isReferencedBy:(iTermVariableReference *)reference {
    NSString *tail;
    iTermVariables *variables = [self ownerForKey:name forWriting:NO stripped:&tail];
    if (!variables) {
        return NO;
    }
    return [variables hasLinkToReference:reference path:tail];
}

- (BOOL)setValuesFromDictionary:(NSDictionary<NSString *, id> *)dict {
    // Transform dict from {name: object} to {owner: {stripped_name: object}}
    NSMutableDictionary<NSValue *, NSMutableDictionary<NSString *, id> *> *valuesByOwner = [NSMutableDictionary dictionary];
    for (NSString *key in dict) {
        id object = dict[key];
        NSString *stripped = nil;
        iTermVariables *owner = [self ownerForKey:key forWriting:YES stripped:&stripped];
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

- (BOOL)setValue:(nullable id)value forPath:(NSString *)firstName, ... {
    va_list args;
    va_start(args, firstName);
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *name = firstName; name != nil; name = va_arg(args, NSString*)) {
        [parts addObject:name];
    }
    va_end(args);
    return [self setValue:value forVariableNamed:[parts componentsJoinedByString:@"."]];
}

- (BOOL)setValue:(nullable id)value forVariableNamed:(NSString *)name {
    return [self setValue:value forVariableNamed:name weak:NO];
}

- (BOOL)setValue:(nullable id)value forVariableNamed:(NSString *)name weak:(BOOL)weak {
    assert(![value isKindOfClass:[iTermVariableScope class]]);  // You meant to use iTermVariables, not iTermVariableScope.

    NSString *stripped = nil;
    iTermVariables *owner = [self ownerForKey:name forWriting:YES stripped:&stripped];
    if (!owner) {
        return NO;
    }
    const BOOL result = [owner setValue:value forVariableNamed:stripped weak:weak];
    if ([value isKindOfClass:[iTermVariables class]]) {
        [self resolveDanglingReferences];
    }
    return result;
}

// This is useful for debug logging
- (NSString *)owner {
    for (iTermTuple<NSString *, iTermVariables *> *tuple in _frames) {
        if (tuple.firstObject == nil) {
            return [[tuple.secondObject owner] description];
        }
    }
    return @"(unknown)";
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
    iTermVariables *variables = [self ownerForKey:reference.path forWriting:YES stripped:&tail];
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

- (id)unsafeCheapCopy {
    iTermVariableScope *theCopy = [[self.class alloc] init];
    theCopy->_frames = [_frames copy];
    return theCopy;
}

- (iTermVariableDesignator *)designatorForPath:(NSString *)path {
    NSString *terminal;
    iTermVariables *owner = [self ownerOfTerminalForPath:path
                                              forWriting:NO
                                                terminal:&terminal];
    return [[iTermVariableDesignator alloc] initWithVariables:owner path:terminal];
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

@implementation iTermVariablePlaceholderScope

- (BOOL)usePlaceholders {
    return YES;
}

@end

NS_ASSUME_NONNULL_END
