//
//  iTermURLStore.m
//  iTerm2
//
//  Created by George Nachman on 3/19/17.
//
//

#import "iTermURLStore.h"

#import "DebugLogging.h"

@implementation iTermURLStore {
    // { "url": NSURL.absoluteString, "params": NSString } -> @(NSInteger)
    NSMutableDictionary<NSDictionary *, NSNumber *> *_store;

    // @(unsigned short) -> { "url": NSURL, "params": NSString }
    NSMutableDictionary<NSNumber *, NSDictionary *> *_reverseStore;

    // Internally, the code is stored as a 64-bit integer so we don't have to think about overflow.
    // The value that's exported is truncated to 16 bits and will never equal zero.
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

+ (unsigned short)truncatedCodeForCode:(NSInteger)code {
    return (code % USHRT_MAX) + 1;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _store = [NSMutableDictionary dictionary];
        _reverseStore = [NSMutableDictionary dictionary];
    }
    return self;
}

- (unsigned short)codeForURL:(NSURL *)url withParams:(NSString *)params {
    NSDictionary *key = @{ @"url": url.absoluteString, @"params": params };
    NSNumber *number = _store[key];
    unsigned short truncatedCode;
    if (number == nil) {
        if (_reverseStore.count == USHRT_MAX - 1) {
            DLog(@"Ran out of URL storage. Refusing to allocate a code.");
            return 0;
        }
        while (_reverseStore[@(_nextCode)]) {
            _nextCode++;
        }
        number = @(_nextCode);
        _nextCode++;
        _store[key] = number;
        truncatedCode = [iTermURLStore truncatedCodeForCode:number.integerValue];
        _reverseStore[@(truncatedCode)] = @{ @"url": url, @"params": params };
        return truncatedCode;
    } else {
        return [iTermURLStore truncatedCodeForCode:number.integerValue];
    }
}

- (NSURL *)urlForCode:(unsigned short)code {
    if (code == 0) {
        // Safety valve in case something goes awry. There should never be an entry at 0.
        return nil;
    }
    return _reverseStore[@(code)][@"url"];
}

- (NSString *)paramsForCode:(unsigned short)code {
    if (code == 0) {
        // Safety valve in case something goes awry. There should never be an entry at 0.
        return nil;
    }
    return _reverseStore[@(code)][@"params"];
}

- (NSString *)paramWithKey:(NSString *)key forCode:(unsigned short)code {
    NSString *params = [self paramsForCode:code];
    if (!params) {
        return nil;
    }

    NSArray<NSString *> *parts = [params componentsSeparatedByString:@" "];
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
    return _store;
}

- (void)loadFromDictionary:(NSDictionary *)dictionary {
    [dictionary enumerateKeysAndObjectsUsingBlock:^(NSDictionary * _Nonnull key, NSNumber * _Nonnull obj, BOOL * _Nonnull stop) {
        if (![key isKindOfClass:[NSDictionary class]] ||
            ![obj isKindOfClass:[NSNumber class]]) {
            ELog(@"Unexpected types when loading dictionary: %@ -> %@", key.class, obj.class);
            return;
        }
        NSURL *url = [NSURL URLWithString:key[@"url"]];
        if (url == nil) {
            XLog(@"Bogus key not a URL: %@", url);
            return;
        }
        _store[key] = obj;

        unsigned short truncated = [iTermURLStore truncatedCodeForCode:obj.integerValue];
        _reverseStore[@(truncated)] = @{ @"url": url, @"params": key[@"params"] ?: @"" };
        _nextCode = MAX(_nextCode, obj.integerValue + 1);
    }];
}

@end
