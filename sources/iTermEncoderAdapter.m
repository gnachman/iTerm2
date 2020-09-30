//
//  iTermEncoderAdapter.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import "iTermEncoderAdapter.h"
#import "NSArray+iTerm.h"

@implementation iTermGraphEncoderAdapter

- (instancetype)initWithGraphEncoder:(iTermGraphEncoder *)encoder {
    self = [super init];
    if (self) {
        _encoder = encoder;
    }
    return self;
}

- (void)setObject:(id)obj forKeyedSubscript:(NSString *)key {
    if (!obj) {
        return;
    }
    [_encoder encodeObject:obj key:key];
}

- (void)setObject:(id)obj forKey:(NSString *)key {
    if (!obj) {
        return;
    }
    [_encoder encodeObject:obj key:key];
}

- (BOOL)encodePropertyList:(id)plist withKey:(NSString *)key {
    return [_encoder encodePropertyList:plist withKey:key];
}

- (BOOL)encodeDictionaryWithKey:(NSString *)key
                     generation:(NSInteger)generation
                          block:(BOOL (^ NS_NOESCAPE)(id<iTermEncoderAdapter> encoder))block {
    return [_encoder encodeChildWithKey:key identifier:@"" generation:generation block:^BOOL (iTermGraphEncoder * _Nonnull subencoder) {
        return block([[iTermGraphEncoderAdapter alloc] initWithGraphEncoder:subencoder]);
    }];
}

- (void)encodeArrayWithKey:(NSString *)key
               identifiers:(NSArray<NSString *> *)identifiers
                generation:(NSInteger)generation
                     block:(BOOL (^ NS_NOESCAPE)(id<iTermEncoderAdapter> encoder,
                                                 NSInteger index,
                                                 NSString *identifier,
                                                 BOOL *stop))block {
    [self encodeArrayWithKey:key
                 identifiers:identifiers
                  generation:generation
                     options:0
                       block:block];
}

- (void)encodeArrayWithKey:(NSString *)key
               identifiers:(NSArray<NSString *> *)identifiers
                generation:(NSInteger)generation
                   options:(iTermGraphEncoderArrayOptions)options
                     block:(BOOL (^ NS_NOESCAPE)(id<iTermEncoderAdapter> encoder,
                                                 NSInteger i,
                                                 NSString *identifier,
                                                 BOOL *stop))block {
    [_encoder encodeArrayWithKey:key
                      generation:generation
                     identifiers:identifiers
                         options:options
                           block:^BOOL(NSString * _Nonnull identifier,
                                       NSInteger index,
                                       iTermGraphEncoder * _Nonnull subencoder,
                                       BOOL *stop) {
        return block([[iTermGraphEncoderAdapter alloc] initWithGraphEncoder:subencoder], index, identifier, stop);
    }];
}

- (void)mergeDictionary:(NSDictionary *)dictionary {
    [_encoder mergeDictionary:dictionary];
}

@end

@implementation iTermMutableDictionaryEncoderAdapter: NSObject

+ (instancetype)encoder {
    return [[self alloc] initWithMutableDictionary:[NSMutableDictionary dictionary]];
}

- (instancetype)initWithMutableDictionary:(NSMutableDictionary *)mutableDictionary {
    self = [super init];
    if (self) {
        _mutableDictionary = mutableDictionary;
    }
    return self;
}

- (instancetype)init {
    return [self initWithMutableDictionary:[NSMutableDictionary dictionary]];
}

- (void)setObject:(id)obj forKeyedSubscript:(NSString *)key {
    if (!obj) {
        return;
    }
    _mutableDictionary[key] = obj;
}

- (void)setObject:(id)obj forKey:(NSString *)key {
    if (!obj) {
        return;
    }
    _mutableDictionary[key] = obj;
}

- (BOOL)encodePropertyList:(id)plist withKey:(NSString *)key {
    _mutableDictionary[key] = plist;
    return YES;
}

- (BOOL)encodeDictionaryWithKey:(NSString *)key
                           generation:(NSInteger)generation
                                block:(BOOL (^ NS_NOESCAPE)(id<iTermEncoderAdapter> encoder))block {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if (!block([[iTermMutableDictionaryEncoderAdapter alloc] initWithMutableDictionary:dict])) {
        return NO;
    }
    _mutableDictionary[key] = dict;
    return YES;
}

- (void)encodeArrayWithKey:(NSString *)key
               identifiers:(NSArray<NSString *> *)identifiers
                generation:(NSInteger)generation
                     block:(BOOL (^ NS_NOESCAPE)(id<iTermEncoderAdapter> _Nonnull,
                                                 NSInteger index,
                                                 NSString * _Nonnull,
                                                 BOOL *stop))block {
    [self encodeArrayWithKey:key
                 identifiers:identifiers
                  generation:generation
                     options:0
                       block:block];
}

- (void)encodeArrayWithKey:(NSString *)key
               identifiers:(NSArray<NSString *> *)identifiers
                generation:(NSInteger)generation
                   options:(iTermGraphEncoderArrayOptions)options
                     block:(BOOL (^ NS_NOESCAPE)(id<iTermEncoderAdapter> encoder,
                                                 NSInteger i,
                                                 NSString *identifier,
                                                 BOOL *stop))block {
    NSArray *array = [identifiers mapEnumeratedWithBlock:^id(NSUInteger index,
                                                             NSString *identifier,
                                                             BOOL *stop) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        if (!block([[iTermMutableDictionaryEncoderAdapter alloc] initWithMutableDictionary:dict],
                   index,
                   identifier,
                   stop)) {
            return nil;
        }
        return dict;
    }];
    if (options & iTermGraphEncoderArrayOptionsReverse) {
        _mutableDictionary[key] = [array reversed];
    } else {
        _mutableDictionary[key] = array;
    }
}

- (void)mergeDictionary:(NSDictionary *)dictionary {
    [dictionary enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        self[key] = obj;
    }];
}

@end
