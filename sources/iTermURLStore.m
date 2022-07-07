//
//  iTermURLStore.m
//  iTerm2
//
//  Created by George Nachman on 3/19/17.
//
//

#import "iTermURLStore.h"

#import "DebugLogging.h"
#import "NSObject+iTerm.h"
#import "iTermTuple.h"

#import <Cocoa/Cocoa.h>

@implementation iTermURLStore {
    // { "url": NSURL.absoluteString, "params": NSString } -> @(NSInteger)
    NSMutableDictionary<iTermTuple<NSString *, NSString *> *, NSNumber *> *_store;

    // @(unsigned int) -> { "url": NSURL, "params": NSString }
    NSMutableDictionary<NSNumber *, iTermTuple<NSURL *, NSString *> *> *_reverseStore;

    NSCountedSet<NSNumber *> *_referenceCounts;

    // Will never be zero.
    NSInteger _nextCode;
}

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static id instance;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

+ (unsigned int)successor:(unsigned int)n {
    if (n == UINT_MAX - 1) {
        return 1;
    }
    return n + 1;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _store = [NSMutableDictionary dictionary];
        _reverseStore = [NSMutableDictionary dictionary];
        _referenceCounts = [NSCountedSet set];
        _nextCode = 1;
    }
    return self;
}

- (void)retainCode:(unsigned int)code {
    @synchronized (self) {
        _generation++;
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSApp invalidateRestorableState];
        });
        [_referenceCounts addObject:@(code)];
    }
}

- (void)releaseCode:(unsigned int)code {
    @synchronized (self) {
        _generation++;
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSApp invalidateRestorableState];
        });
        [_referenceCounts removeObject:@(code)];
        if (![_referenceCounts containsObject:@(code)]) {
            iTermTuple<NSURL *, NSString *> *tuple = _reverseStore[@(code)];
            [_reverseStore removeObjectForKey:@(code)];
            NSString *url = [tuple.firstObject absoluteString];
            NSString *params = tuple.secondObject;
            if (url) {
                [_store removeObjectForKey:[iTermTuple tupleWithObject:url andObject:params]];
            }
        }
    }
}

- (unsigned int)codeForURL:(NSURL *)url withParams:(NSString *)params {
    @synchronized (self) {
        if (!url.absoluteString || !params) {
            DLog(@"codeForURL:%@ withParams:%@ returning 0 because of nil value", url.absoluteString, params);
            return 0;
        }
        iTermTuple<NSString *, NSString *> *key = [iTermTuple tupleWithObject:url.absoluteString andObject:params];
        NSNumber *number = _store[key];
        if (number) {
            return number.unsignedIntValue;
        }
        if (_reverseStore.count == USHRT_MAX - 1) {
            DLog(@"Ran out of URL storage. Refusing to allocate a code.");
            return 0;
        }
        // Advance _nextCode to the next unused code. This will not normally happen - only on wraparound.
        while (_reverseStore[@(_nextCode)]) {
            _nextCode = [iTermURLStore successor:_nextCode];
        }

        // Save it and advance.
        number = @(_nextCode);
        _nextCode = [iTermURLStore successor:_nextCode];

        // Record the code/URL+params relation.
        _store[key] = number;
        _reverseStore[number] = [iTermTuple tupleWithObject:url andObject:params];

        dispatch_async(dispatch_get_main_queue(), ^{
            [NSApp invalidateRestorableState];
        });
        _generation++;
        return number.unsignedIntValue;
    }
}

- (NSURL *)urlForCode:(unsigned int)code {
    @synchronized (self) {
        if (code == 0) {
            // Safety valve in case something goes awry. There should never be an entry at 0.
            return nil;
        }
        return _reverseStore[@(code)].firstObject;
    }
}

- (NSString *)paramsForCode:(unsigned int)code {
    @synchronized (self) {
        if (code == 0) {
            // Safety valve in case something goes awry. There should never be an entry at 0.
            return nil;
        }
        return _reverseStore[@(code)].secondObject;
    }
}

- (NSString *)paramWithKey:(NSString *)key forCode:(unsigned int)code {
    NSString *params = [self paramsForCode:code];
    if (!params) {
        return nil;
    }
    return iTermURLStoreGetParamForKey(params, key);
}

static NSString *iTermURLStoreGetParamForKey(NSString *params, NSString *key) {
    NSArray<NSString *> *parts = [params componentsSeparatedByString:@":"];
    for (NSString *part in parts) {
        NSInteger i = [part rangeOfString:@"="].location;
        if (i != NSNotFound) {
            NSString *partKey = [part substringToIndex:i];
            if ([partKey isEqualToString:key]) {
                return [part substringFromIndex:i + 1];
            }
        }
    }
    return nil;
}

- (NSDictionary *)dictionaryValue {
    @synchronized (self) {
        NSMutableArray<NSNumber *> *encodedRefcounts = [NSMutableArray array];
        [_referenceCounts enumerateObjectsUsingBlock:^(NSNumber * _Nonnull obj, BOOL * _Nonnull stop) {
            [encodedRefcounts addObject:obj];
            [encodedRefcounts addObject:@([_referenceCounts countForObject:obj])];
        }];

        return @{ @"store": _store,
                  @"refcounts3": encodedRefcounts };
    }
}

- (iTermTuple<NSString *, NSString *> *)migratedKey:(id)unknownKey {
    NSDictionary *dict = [NSDictionary castFrom:unknownKey];
    if (dict) {
        return [iTermTuple tupleWithObject:dict[@"url"] andObject:dict[@"param"]];
    }
    return [iTermTuple castFrom:unknownKey];
}

- (void)loadFromDictionary:(NSDictionary *)dictionary {
    @synchronized (self) {
        NSDictionary *store = dictionary[@"store"];
        NSData *refcounts = dictionary[@"refcounts"];  // deprecated
        NSData *refcounts2 = dictionary[@"refcounts2"];  // deprecated
        NSArray<NSNumber *> *refcounts3 = dictionary[@"refcounts3"];

        if (!store || (!refcounts && !refcounts2 && !refcounts3)) {
            DLog(@"URLStore restoration dictionary missing value");
            DLog(@"store=%@", store);
            DLog(@"refcounts=%@", refcounts);
            DLog(@"refcounts2=%@", refcounts2);
            DLog(@"refcounts3=%@", refcounts3);
            return;
        }
        [store enumerateKeysAndObjectsUsingBlock:^(id unknownKey, NSNumber * _Nonnull obj, BOOL * _Nonnull stop) {
            iTermTuple<NSString *, NSString *> *key = [self migratedKey:unknownKey];

            if (!key ||
                ![obj isKindOfClass:[NSNumber class]]) {
                ELog(@"Unexpected types when loading dictionary: %@ -> %@", key.class, obj.class);
                return;
            }
            NSURL *url = [NSURL URLWithString:key.firstObject];
            if (url == nil) {
                XLog(@"Bogus key not a URL: %@", url);
                return;
            }
            self->_store[key] = obj;

            self->_reverseStore[obj] = [iTermTuple tupleWithObject:url andObject:key.secondObject ?: @""];
            self->_nextCode = [iTermURLStore successor:MAX(obj.unsignedIntValue, self->_nextCode)];
        }];

        NSError *error = nil;
        if (refcounts2) {
            _referenceCounts = [NSKeyedUnarchiver unarchivedObjectOfClasses:[NSSet setWithArray:@[ [NSCountedSet class], [NSNumber class] ]]
                                                                   fromData:refcounts2
                                                                      error:&error] ?: [[NSCountedSet alloc] init];
            if (error) {
                _referenceCounts = [self legacyDecodedRefcounts:dictionary];
                NSLog(@"Failed to decode refcounts from data %@", refcounts2);
                return;
            }
        }
        if (refcounts3) {
            const NSInteger count = refcounts3.count;
            for (NSInteger i = 0; i + 1 < count; i += 2) {
                NSNumber *obj = refcounts3[i];
                NSInteger rc = [refcounts3[i+1] integerValue];
                for (NSInteger j = 0; j < rc; j++) {
                    [_referenceCounts addObject:obj];
                }
            }
        }
    }
}

- (NSCountedSet *)legacyDecodedRefcounts:(NSDictionary *)dictionary {
    NSData *refcounts = dictionary[@"refcounts"];
    if (!refcounts) {
        return [[NSCountedSet alloc] init];
    }
    // TODO: Remove this after the old format is no longer around. Probably safe to do around mid 2023.
    NSError *error = nil;
    NSKeyedUnarchiver *decoder = [[NSKeyedUnarchiver alloc] initForReadingFromData:refcounts error:&error];
    if (error) {
        NSLog(@"Failed to decode refcounts from data %@", refcounts);
        return [[NSCountedSet alloc] init];
    }
    return [[NSCountedSet alloc] initWithCoder:decoder] ?: [[NSCountedSet alloc] init];
}

@end
