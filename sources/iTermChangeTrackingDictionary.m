//
//  iTermChangeTrackingDictionary.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/25/23.
//

#import "iTermChangeTrackingDictionary.h"
#import "iTerm2SharedARC-Swift.h"

@implementation iTermChangeTrackingDictionary {
    NSMutableDictionary *_impl;
    NSMutableDictionary<id, NSNumber *> *_generations;
    NSInteger _generation;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _impl = [NSMutableDictionary dictionary];
        _generations = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSDictionary *)dictionary {
    return [_impl copy];
}

- (NSUInteger)count {
    return _impl.count;
}

- (id)objectForKey:(id)aKey {
    return _impl[aKey];
}

- (void)setObject:(id)anObject forKey:(id<NSCopying>)aKey {
    _impl[aKey] = anObject;
    _generations[aKey] = @(_generations[aKey].integerValue + 1);
    _generation += 1;
}

- (id)objectForKeyedSubscript:(id)key {
    return _impl[key];
}

- (void)setObject:(id)obj forKeyedSubscript:(id<NSCopying>)key {
    [self setObject:obj forKey:key];
}

- (void)removeObjectForKey:(id)key {
    [self setObject:nil forKey:key];
}

- (void)enumerateKeysAndObjectsUsingBlock:(void (^ NS_NOESCAPE)(id _Nonnull,
                                                                id _Nonnull,
                                                                BOOL * _Nonnull))block {
    [_impl enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        block(key, obj, stop);
    }];
}

- (NSArray *)allKeys {
    return [_impl allKeys];
}

- (NSInteger)generationForKey:(id)key {
    return [_generations[key] integerValue];
}

// MARK: - iTermGraphCodable

- (BOOL)encodeGraphWithEncoder:(iTermGraphEncoder *)encoder {
    [encoder encodeChildWithKey:@"changeTrackingDictionary"
                     identifier:@""
                     generation:_generation
                          block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
        [_impl enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            [subencoder encodeChildWithKey:@""
                                identifier:[key jsonEncoded]
                                generation:_generations[key].integerValue
                                     block:^BOOL(iTermGraphEncoder * _Nonnull subsubencoder) {
                [subsubencoder encodeObject:obj key:@""];
                return YES;
            }];
        }];
        return YES;
    }];
    return YES;
}

- (void)loadFromRecord:(iTermEncoderGraphRecord *)record
              keyClass:(Class)keyClass
            valueClass:(Class)valueClass {
    iTermEncoderGraphRecord *root = [record childRecordWithKey:@"changeTrackingDictionary" identifier:@""];

    [root.index enumerateKeysAndObjectsUsingBlock:^(iTermTuple<NSString *,NSString *> * _Nonnull key,
                                                    iTermEncoderGraphRecord * _Nonnull subrecord,
                                                    BOOL * _Nonnull stop) {
        if (![key.firstObject isEqual:@""]) {
            return;
        }
        const NSInteger generation = subrecord.generation;
        id dictionaryKey = [keyClass fromJsonEncodedString:subrecord.identifier];
        id dictionaryValue = [subrecord objectWithKey:@"" class:valueClass];
        if (dictionaryKey && dictionaryValue) {
            _impl[dictionaryKey] = dictionaryValue;
            _generations[dictionaryKey] = @(generation);
        }
    }];
}
@end

