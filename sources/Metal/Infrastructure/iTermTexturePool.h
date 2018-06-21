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

// Pools textures of a particular size.
NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermTexturePool : NSObject
- (nullable id<MTLTexture>)requestTextureOfSize:(vector_uint2)size;
- (void)returnTexture:(id<MTLTexture>)texture;
- (void)stampTextureWithGeneration:(id<MTLTexture>)texture;
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

