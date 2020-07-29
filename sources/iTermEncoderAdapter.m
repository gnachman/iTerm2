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
    [_encoder encodeObject:obj key:key];
}

- (void)setObject:(id)obj forKey:(NSString *)key {
    [_encoder encodeObject:obj key:key];
}

- (void)encodeDictionaryWithKey:(NSString *)key
                     generation:(NSInteger)generation
                          block:(BOOL (^)(id<iTermEncoderAdapter> encoder))block {
    [_encoder encodeChildWithKey:key identifier:@"" generation:generation block:^BOOL (iTermGraphEncoder * _Nonnull subencoder) {
        return block([[iTermGraphEncoderAdapter alloc] initWithGraphEncoder:subencoder]);
    }];
}

- (void)encodeArrayWithKey:(NSString *)key
               identifiers:(NSArray<NSString *> *)identifiers
                generation:(NSInteger)generation
                     block:(BOOL (^)(id<iTermEncoderAdapter> encoder,
                                     NSString *identifier))block {
    [_encoder encodeArrayWithKey:key
                      generation:generation
                     identifiers:identifiers
                           block:^BOOL(NSString * _Nonnull identifier,
                                       NSInteger index,
                                       iTermGraphEncoder * _Nonnull subencoder) {
        return block([[iTermGraphEncoderAdapter alloc] initWithGraphEncoder:subencoder], identifier);
    }];
}

@end

@implementation iTermMutableDictionaryEncoderAdapter: NSObject

- (instancetype)initWithMutableDictionary:(NSMutableDictionary *)mutableDictionary {
    self = [super init];
    if (self) {
        _mutableDictionary = mutableDictionary;
    }
    return self;
}

- (void)setObject:(id)obj forKeyedSubscript:(NSString *)key {
    _mutableDictionary[key] = obj;
}

- (void)setObject:(id)obj forKey:(NSString *)key {
    _mutableDictionary[key] = obj;
}

- (void)encodeDictionaryWithKey:(NSString *)key
                     generation:(NSInteger)generation
                          block:(BOOL (^)(id<iTermEncoderAdapter> encoder))block {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if (block([[iTermMutableDictionaryEncoderAdapter alloc] initWithMutableDictionary:dict])) {
        _mutableDictionary[key] = dict;
    }
}

- (void)encodeArrayWithKey:(NSString *)key
               identifiers:(NSArray<NSString *> *)identifiers
                generation:(NSInteger)generation
                     block:(BOOL (^)(id<iTermEncoderAdapter> _Nonnull,
                                     NSString * _Nonnull))block {
    _mutableDictionary[key] = [identifiers mapWithBlock:^id(NSString *identifier) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        if (!block([[iTermMutableDictionaryEncoderAdapter alloc] initWithMutableDictionary:dict],
                   identifier)) {
            return nil;
        }
        return dict;
    }];
}

@end
