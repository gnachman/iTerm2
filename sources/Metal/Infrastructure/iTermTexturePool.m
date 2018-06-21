//
//  iTermTexturePool.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/31/17.
//

#import "iTermTexturePool.h"

#import "iTermPowerManager.h"
#import "NSObject+iTerm.h"

static void *iTermTexturePoolAssociatedObjectKeyGeneration = "iTermTexturePoolAssociatedObjectKeyGeneration";

NS_ASSUME_NONNULL_BEGIN

@implementation iTermTexturePool {
    NSMutableArray<id<MTLTexture>> *_textures;
    vector_uint2 _size;
    NSNumber *_generation;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _generation = @0;
        _textures = [NSMutableArray array];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(powerManagerMetalAllowedDidChange:) name:iTermPowerManagerMetalAllowedDidChangeNotification object:nil];
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
            [self stampTextureWithGeneration:result];
            return result;
        } else {
            return nil;
        }
    }
}

- (void)returnTexture:(id<MTLTexture>)texture {
    @synchronized(self) {
        if (texture.width == _size.x && texture.height == _size.y) {
            NSNumber *generation = [(NSObject *)texture it_associatedObjectForKey:iTermTexturePoolAssociatedObjectKeyGeneration];
            if ([NSObject object:generation isEqualToObject:_generation]) {
                [_textures addObject:texture];
            }
        }
    }
}

- (void)powerManagerMetalAllowedDidChange:(NSNotification *)notification {
    NSNumber *allowedNumber = notification.object;
    if (!allowedNumber.boolValue) {
        [_textures removeAllObjects];
        _generation = @(_generation.integerValue + 1);
    }
}

- (void)stampTextureWithGeneration:(id<MTLTexture>)texture {
    [(NSObject *)texture it_setAssociatedObject:_generation forKey:iTermTexturePoolAssociatedObjectKeyGeneration];
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
        [pool stampTextureWithGeneration:texture];
    }
    return self;
}

- (void)dealloc {
    [_pool returnTexture:_texture];
}

@end


NS_ASSUME_NONNULL_END
