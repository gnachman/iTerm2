//
//  iTermGraphEncoder.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/26/20.
//

#import "iTermGraphEncoder.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSData+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermTuple.h"

NSInteger iTermGenerationAlwaysEncode = NSIntegerMax;

@implementation iTermGraphEncoder {
    NSMutableDictionary<NSString *, id> *_pod;
    NSString *_identifier;
    NSInteger _generation;
    NSString *_key;
    // This is append-only, otherwise rolling back a transaction breaks.
    NSMutableArray<iTermEncoderGraphRecord *> *_children;
    iTermEncoderGraphRecord *_record;
}

- (instancetype)initWithKey:(NSString *)key
                 identifier:(NSString *)identifier
                 generation:(NSInteger)generation {
    assert(identifier);
    self = [super init];
    if (self) {
        _key = key;
        _identifier = identifier;
        if (generation != iTermGenerationAlwaysEncode) {
            _generation = generation;
        } else {
            _generation = 0;
        }
        _pod = [NSMutableDictionary dictionary];
        _children = [NSMutableArray array];
        _state = iTermGraphEncoderStateLive;
    }
    return self;
}

- (instancetype)initWithRecord:(iTermEncoderGraphRecord *)record {
    iTermGraphEncoder *encoder = [self initWithKey:record.key
                                        identifier:record.identifier
                                        generation:record.generation];
    if (!encoder) {
        return nil;
    }
    encoder->_pod = [record.pod mutableCopy];
    encoder->_children = [record.graphRecords mutableCopy];
    return encoder;
}

- (void)encodeString:(NSString *)string forKey:(NSString *)key {
    assert(_state == iTermGraphEncoderStateLive);
    _pod[key] = string.copy;
}

- (void)encodeNumber:(NSNumber *)number forKey:(NSString *)key {
    assert(_state == iTermGraphEncoderStateLive);
    _pod[key] = number;
}

- (void)encodeData:(NSData *)data forKey:(NSString *)key {
    assert(_state == iTermGraphEncoderStateLive);
    _pod[key] = data.copy;
}

- (BOOL)encodePropertyList:(id)plist withKey:(NSString *)key timer:(nonnull iTermTreeTimer *)timer {
    assert(_state == iTermGraphEncoderStateLive);
    __block BOOL ok = NO;
    [timer enter:[NSString stringWithFormat:@"Encode property list %@ to data", key] block:^(iTermTreeTimer *timer) {
        NSError *error;
        NSData *data = [NSData it_dataWithSecurelyArchivedObject:plist error:&error];
        if (error) {
            DLog(@"Failed to serialize property list %@: %@", plist, error);
            ok = NO;
            return;
        }
        _pod[key] = data;
        ok = YES;
    }];
    return ok;
}

- (void)encodeDate:(NSDate *)date forKey:(NSString *)key {
    assert(_state == iTermGraphEncoderStateLive);
    _pod[key] = date;
}

- (void)encodeNullForKey:(NSString *)key {
    assert(_state == iTermGraphEncoderStateLive);
    _pod[key] = [NSNull null];
}

- (BOOL)encodeObject:(id)obj key:(NSString *)key timer:(nonnull iTermTreeTimer *)timer {
    if ([obj conformsToProtocol:@protocol(iTermGraphEncodable)] &&
        [(id<iTermGraphEncodable>)obj graphEncoderShouldIgnore]) {
        return NO;
    }
    if ([obj isKindOfClass:[NSString class]]) {
        [self encodeString:obj forKey:key];
        return YES;
    }
    if ([obj isKindOfClass:[NSData class]]) {
        [self encodeData:obj forKey:key];
        return YES;
    }
    if ([obj isKindOfClass:[NSDate class]]) {
        [self encodeData:obj forKey:key];
        return YES;
    }
    if ([obj isKindOfClass:[NSNumber class]]) {
        [self encodeNumber:obj forKey:key];
        return YES;
    }
    if ([obj isKindOfClass:[NSNull class]]) {
        [self encodeNullForKey:key];
        return YES;
    }
    NSError *error = nil;
    [NSData it_dataWithSecurelyArchivedObject:obj error:&error];
    if (!error) {
        _pod[key] = obj;
        return YES;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        NSArray *array = obj;
        [self encodeArrayWithKey:key
                      generation:_generation
                     identifiers:[NSArray stringSequenceWithRange:NSMakeRange(0, array.count)]
                         options:0
                           timer:timer
                           block:^BOOL (NSString * _Nonnull identifier,
                                        NSInteger index,
                                        iTermGraphEncoder * _Nonnull subencoder,
                                        iTermTreeTimer *timer,
                                        BOOL *stop) {
            [subencoder encodeObject:array[index] key:@"__arrayValue" timer:timer];
            return YES;
        }];
        return YES;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = obj;
        [self encodeDictionary:dict withKey:key timer:timer generation:_generation];
        return YES;
    }
    assert(NO);
}

- (void)encodeDictionary:(NSDictionary *)dict
                 withKey:(NSString *)key
                   timer:(iTermTreeTimer *)timer
              generation:(NSInteger)generation {
    [self encodeChildWithKey:@"__dict"
                  identifier:key
                  generation:generation
                       timer:timer
                       block:^BOOL(iTermGraphEncoder * _Nonnull subencoder,
                                   iTermTreeTimer *timer) {
        [dict enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            [subencoder encodeObject:obj key:key timer:timer];
        }];
        return YES;
    }];
}

- (void)encodeGraph:(iTermEncoderGraphRecord *)record timer:(nonnull iTermTreeTimer *)timer {
    assert(_state == iTermGraphEncoderStateLive);
    [_children addObject:record];
}

- (void)mergeDictionary:(NSDictionary *)dictionary {
    [_pod it_mergeFrom:dictionary];
}

- (BOOL)encodeChildWithKey:(NSString *)key
                identifier:(NSString *)identifier
                generation:(NSInteger)generation
                     timer:(iTermTreeTimer *)timer
                     block:(BOOL (^ NS_NOESCAPE)(iTermGraphEncoder *subencoder,
                                                 iTermTreeTimer *timer))block {
    assert(_state == iTermGraphEncoderStateLive);
    __block BOOL result = NO;
    [timer enter:[NSString stringWithFormat:@"Encode child %@[%@]", key, identifier] block:^(iTermTreeTimer *timer) {
        iTermGraphEncoder *encoder = [[iTermGraphEncoder alloc] initWithKey:key
                                                                 identifier:identifier
                                                                 generation:generation];
        if (!block(encoder, timer)) {
            return;
        }
        [self encodeGraph:encoder.record timer:timer];
        result = YES;
    }];
    return result;
}

- (void)encodeChildrenWithKey:(NSString *)key
                  identifiers:(NSArray<NSString *> *)identifiers
                   generation:(NSInteger)generation
                        timer:(iTermTreeTimer *)timer
                        block:(BOOL (^)(NSString *identifier,
                                        NSUInteger idx,
                                        iTermGraphEncoder *subencoder,
                                        iTermTreeTimer *timer,
                                        BOOL *stop))block {
    if (identifiers.count > 16 && _children.count == 0) {
        _children = [[NSMutableArray alloc] initWithCapacity:identifiers.count];
    }
    [timer enter:[NSString stringWithFormat:@"Encode children of %@ with %@ identifiers", key, @(identifiers.count)] block:^(iTermTreeTimer *timer) {
        [identifiers enumerateObjectsUsingBlock:^(NSString * _Nonnull identifier,
                                                  NSUInteger idx,
                                                  BOOL * _Nonnull stop) {
            // transaction is slow because it makes a copy in case of rollback.
            // Do I need a transactio nfor each identifier?
            [self transaction:^BOOL{
                return [self encodeChildWithKey:key
                                     identifier:identifier
                                     generation:generation
                                          timer:timer
                                          block:^BOOL(iTermGraphEncoder * _Nonnull subencoder,
                                                      iTermTreeTimer *timer) {
                    return block(identifier, idx, subencoder, timer, stop);
                }];
            }];
        }];
    }];
}

- (void)encodeArrayWithKey:(NSString *)key
                generation:(NSInteger)generation
               identifiers:(NSArray<NSString *> *)identifiers
                   options:(iTermGraphEncoderArrayOptions)options
                     timer:(iTermTreeTimer *)timer
                     block:(BOOL (^ NS_NOESCAPE)(NSString *identifier,
                                                 NSInteger index,
                                                 iTermGraphEncoder *subencoder,
                                                 iTermTreeTimer *timer,
                                                 BOOL *stop))block {
    [timer enter:[NSString stringWithFormat:@"Encode array %@", key] block:^(iTermTreeTimer *timer) {
        if (identifiers.count != [NSSet setWithArray:identifiers].count) {
            ITBetaAssert(NO, @"Identifiers for %@ contains a duplicate: %@", key, identifiers);
        }
        [self encodeChildWithKey:@"__array"
                      identifier:key
                      generation:generation
                           timer:timer
                           block:^BOOL(iTermGraphEncoder * _Nonnull subencoder,
                                       iTermTreeTimer *timer) {
            NSMutableArray<NSString *> *savedIdentifiers = [NSMutableArray array];
            [subencoder encodeChildrenWithKey:@""
                                  identifiers:identifiers
                                   generation:iTermGenerationAlwaysEncode
                                        timer:timer
                                        block:^BOOL (NSString * _Nonnull identifier,
                                                     NSUInteger idx,
                                                     iTermGraphEncoder * _Nonnull subencoder,
                                                     iTermTreeTimer *timer,
                                                     BOOL * _Nonnull stop) {
                const BOOL result = block(identifier, idx, subencoder, timer, stop);
                if (result) {
                    [savedIdentifiers addObject:identifier];
                }
                return result;
            }];
            NSArray<NSString *> *orderedIdentifiers = savedIdentifiers;
            if (options & iTermGraphEncoderArrayOptionsReverse) {
                orderedIdentifiers = orderedIdentifiers.reversed;
            }
            orderedIdentifiers = [orderedIdentifiers arrayByRemovingDuplicatesStably];
            [subencoder encodeString:[orderedIdentifiers componentsJoinedByString:@"\t"] forKey:@"__order"];
            return YES;
        }];
    }];
}

- (iTermEncoderGraphRecord *)record {
    switch (_state) {
        case iTermGraphEncoderStateLive:
            _record = [iTermEncoderGraphRecord withPODs:_pod
                                                 graphs:_children
                                             generation:_generation
                                                    key:_key
                                             identifier:_identifier
                                                  rowid:nil];
            _state = iTermGraphEncoderStateCommitted;
            return _record;

        case iTermGraphEncoderStateCommitted:
            return _record;

        case iTermGraphEncoderStateRolledBack:
            return nil;
    }
}

- (void)transaction:(BOOL (^)(void))block {
    NSMutableDictionary<NSString *, id> *savedPOD = [_pod mutableCopy];
    const NSUInteger savedCount = _children.count;
    const BOOL commit = block();
    if (commit) {
        return;
    }
    _pod = savedPOD;
    if (savedCount < _children.count) {
        DLog(@"Roll back from %@ to %@", @(_children.count), @(savedCount));
        [_children removeObjectsInRange:NSMakeRange(savedCount, _children.count - savedCount)];
    }
}

@end
