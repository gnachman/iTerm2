//
//  iTermImageCache.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/16/18.
//

#import "iTermImageCache.h"
#import "NSObject+iTerm.h"

@interface iTermImageCacheKey : NSObject

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSSize size;
@property (nonatomic, readonly) NSColor *color;

- (instancetype)initWithName:(NSString *)name
                        size:(NSSize)size
                       color:(NSColor *)color NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@implementation iTermImageCacheKey

- (instancetype)initWithName:(NSString *)name
                        size:(NSSize)size
                       color:(NSColor *)color {
    self = [super init];
    if (self) {
        _name = name;
        _size = size;
        _color = color;
    }
    return self;
}

- (NSUInteger)hash {
    return iTermCombineHash(iTermCombineHash(_name.hash,
                                             _size.width * _size.height + _size.width + _size.height),
                            _color.hash);
}

- (BOOL)isEqual:(id)other {
    if (![other isKindOfClass:[iTermImageCacheKey class]]) {
        return NO;
    }
    iTermImageCacheKey *object = other;
    return ([NSObject object:_name isEqualToObject:object.name] &&
            [NSObject object:_color isEqualToObject:object.color] &&
            NSEqualSizes(_size, object.size));
}

@end

@implementation iTermImageCache {
    NSCache<iTermImageCacheKey *, NSImage *> *_cache;
}

- (instancetype)initWithByteLimit:(NSUInteger)byteLimit {
    self = [super init];
    if (self) {
        _cache = [[NSCache alloc] init];
        _cache.totalCostLimit = byteLimit;
    }
    return self;
}

- (void)addImage:(NSImage *)image
            name:(NSString *)name
            size:(NSSize)size
           color:(NSColor *)color {
    [_cache setObject:image
               forKey:[self keyForName:name size:size color:color]
                 cost:size.width * size.height * 4];
}

- (NSImage *)imageWithName:(NSString *)name
                      size:(NSSize)size
                     color:(NSColor *)color {
    return [_cache objectForKey:[self keyForName:name size:size color:color]];
}

- (void)setByteLimit:(NSUInteger)limit {
    _cache.totalCostLimit = limit;
}

- (NSUInteger)byteLimit {
    return _cache.totalCostLimit;
}

#pragma mark - Private

- (iTermImageCacheKey *)keyForName:(NSString *)name size:(NSSize)size color:(NSColor *)color {
    return [[iTermImageCacheKey alloc] initWithName:name size:size color:color];
}

@end
