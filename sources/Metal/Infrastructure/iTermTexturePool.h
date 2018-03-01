//
//  iTermTexturePool.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/31/17.
//

#import <Foundation/Foundation.h>
#import <simd/simd.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermPooledTexture;

// Pools textures of a particular size.
//
// Suggested usage:
//   iTermTexturePool *pool = [[iTermTexturePool alloc] init];
//   pool.name = @"Foo pool";
//   iTermPooledTexture *pooledTexture = [pool pooledTextureOfSize:size creator:^id<MTLTexture> { ... return newTexture; }];
//   [tState.textures addObject:pooledTexture];
//   ... use pooledTexture.texture.
//
// When tState is dealloced the iTermPooledTexture gets dealloced and added back to the pool.
NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermTexturePool : NSObject
@property (nonatomic, copy) NSString *name;

- (nullable id<MTLTexture>)requestTextureOfSize:(vector_uint2)size;
- (iTermPooledTexture *)pooledTextureOfSize:(vector_uint2)size
                                    creator:(id<MTLTexture> (^)(void))creator;

// Only use this if you don't use iTermPooledTexture.
- (void)returnTexture:(id<MTLTexture>)texture;
@end

// Store this wrapper object in your renderer's transient state. It returns its texture to the
// pool on dealloc.
NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermPooledTexture : NSObject

@property (nonatomic, strong, readonly) id<MTLTexture> texture;

- (instancetype)initWithTexture:(id<MTLTexture>)texture
                           pool:(iTermTexturePool *)pool NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end


NS_ASSUME_NONNULL_END

