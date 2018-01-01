//
//  iTermTexturePool.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/31/17.
//

#import "iTermTexturePool.h"

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

- (void)returnTexture:(id<MTLTexture>)texture {
    @synchronized(self) {
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
