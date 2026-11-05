//
//  iTermProfileReadRecorder.m
//  iTerm2SharedARC
//

#import "iTermProfileReadRecorder.h"

#import "iTerm2SharedARC-Swift.h"
#import "NSObject+iTerm.h"

@implementation iTermProfileReadRecorder {
    NSDictionary *_profile;
    NSMutableSet<NSString *> *_keysReadOutsideColorsSection;
}

- (instancetype)initWithProfile:(NSDictionary *)profile {
    self = [super init];
    if (self) {
        _profile = [profile copy];
        _keysReadOutsideColorsSection = [NSMutableSet set];
    }
    return self;
}

#pragma mark - NSDictionary primitives

- (NSUInteger)count {
    return _profile.count;
}

- (id)objectForKey:(id)aKey {
    if (!_inColorsSection && [aKey isKindOfClass:[NSString class]]) {
        [_keysReadOutsideColorsSection addObject:aKey];
        if (!_firstLeakBacktrace && [[iTermProfileReloadScopes colorsScopeKeys] containsObject:aKey]) {
            _firstLeakBacktrace = [NSThread callStackSymbols];
        }
    }
    return _profile[aKey];
}

- (NSEnumerator *)keyEnumerator {
    return [_profile keyEnumerator];
}

#pragma mark - Bulk access that does not count as reading

// Everything below forwards to the wrapped profile explicitly so that what counts as a read is
// defined here rather than by whether Foundation happens to implement a method in terms of
// -objectForKey: or -getObjects:andKeys:count:. Whole-dictionary operations are not reads: they
// are how a profile is copied, compared, or bridged, not how a setting is looked up.

- (void)getObjects:(id __unsafe_unretained [])objects
           andKeys:(id __unsafe_unretained [])keys
             count:(NSUInteger)count {
    [_profile getObjects:objects andKeys:keys count:count];
}

- (NSArray *)allKeys {
    return _profile.allKeys;
}

- (NSArray *)allValues {
    return _profile.allValues;
}

- (NSArray *)allKeysForObject:(id)anObject {
    return [_profile allKeysForObject:anObject];
}

- (NSArray *)objectsForKeys:(NSArray *)keys notFoundMarker:(id)marker {
    return [_profile objectsForKeys:keys notFoundMarker:marker];
}

- (void)enumerateKeysAndObjectsUsingBlock:(void (NS_NOESCAPE ^)(id key, id obj, BOOL *stop))block {
    [_profile enumerateKeysAndObjectsUsingBlock:block];
}

- (void)enumerateKeysAndObjectsWithOptions:(NSEnumerationOptions)opts
                                usingBlock:(void (NS_NOESCAPE ^)(id key, id obj, BOOL *stop))block {
    [_profile enumerateKeysAndObjectsWithOptions:opts usingBlock:block];
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained [])buffer
                                    count:(NSUInteger)len {
    return [_profile countByEnumeratingWithState:state objects:buffer count:len];
}

- (BOOL)isEqual:(id)object {
    iTermProfileReadRecorder *other = [iTermProfileReadRecorder castFrom:object];
    if (other) {
        return [_profile isEqual:other->_profile];
    }
    return [_profile isEqual:object];
}

- (BOOL)isEqualToDictionary:(NSDictionary *)otherDictionary {
    return [self isEqual:otherDictionary];
}

- (NSUInteger)hash {
    return _profile.hash;
}

- (id)copyWithZone:(NSZone *)zone {
    return [_profile copyWithZone:zone];
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    return [_profile mutableCopyWithZone:zone];
}

- (NSString *)description {
    return _profile.description;
}

- (NSString *)descriptionWithLocale:(id)locale {
    return [_profile descriptionWithLocale:locale];
}

- (NSString *)descriptionWithLocale:(id)locale indent:(NSUInteger)level {
    return [_profile descriptionWithLocale:locale indent:level];
}

#pragma mark - Results

- (NSSet<NSString *> *)colorsScopeKeysReadOutsideColorsSection {
    NSMutableSet<NSString *> *result = [_keysReadOutsideColorsSection mutableCopy];
    [result intersectSet:[iTermProfileReloadScopes colorsScopeKeys]];
    return result;
}

@end
