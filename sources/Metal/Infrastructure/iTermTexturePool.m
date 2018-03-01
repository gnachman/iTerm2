//
//  iTermTexturePool.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/31/17.
//

#import "iTermTexturePool.h"
#import "NSArray+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermTexturePool {
    NSMutableArray<id<MTLTexture>> *_textures;
    vector_uint2 _size;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _textures = [NSMutableArray array];
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p %@>", NSStringFromClass([self class]), self, self.name];
}

- (nullable id<MTLTexture>)requestTextureOfSize:(vector_uint2)size {
    @synchronized(self) {
        if (size.x != _size.x || size.y != _size.y) {
            _size = size;
            [_textures removeAllObjects];
            return nil;
        }
        if (_textures.count) {
            id<MTLTexture> result = _textures.firstObject;
            [_textures removeObjectAtIndex:0];
            return result;
        } else {
            return nil;
        }
    }
}

- (iTermPooledTexture *)pooledTextureOfSize:(vector_uint2)size
                                    creator:(id<MTLTexture> (^)(void))creator {
    id<MTLTexture> texture = [self requestTextureOfSize:size];
    if (!texture) {
        texture = creator();
    }
    return [[iTermPooledTexture alloc] initWithTexture:texture pool:self];
}

- (void)returnTexture:(id<MTLTexture>)texture {
    @synchronized(self) {
        assert(![_textures containsObject:texture]);
        if (texture.width == _size.x && texture.height == _size.y) {
            [_textures addObject:texture];
        }
    }
}

@end

@implementation iTermPooledTexture {
    __weak iTermTexturePool *_pool;
}

- (instancetype)initWithTexture:(id<MTLTexture>)texture pool:(iTermTexturePool *)pool {
    self = [super init];
    if (self) {
        _texture = texture;
        _pool = pool;
    }
    return self;
}

- (void)dealloc {
    [_pool returnTexture:_texture];
}

@end


NS_ASSUME_NONNULL_END
