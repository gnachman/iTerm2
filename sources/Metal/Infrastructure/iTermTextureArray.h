#import <Metal/Metal.h>

@interface iTermTextureArray : NSObject

@property (nonatomic, readonly) id <MTLTexture> texture;
@property (nonatomic, readonly) uint32_t width;
@property (nonatomic, readonly) uint32_t height;
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) CGSize atlasSize;

- (instancetype)initWithTextureWidth:(uint32_t)width
                       textureHeight:(uint32_t)height
                         arrayLength:(NSUInteger)length
                              device:(id <MTLDevice>)device;

- (BOOL)addSliceWithContentsOfFile:(NSString *)path;
- (void)addSliceWithImage:(NSImage *)image;
- (BOOL)setSlice:(NSUInteger)slice withImage:(NSImage *)nsimage;
- (void)copyTextureAtIndex:(NSInteger)index
                   toArray:(iTermTextureArray *)destination
                     index:(NSInteger)destinationIndex
                   blitter:(id<MTLBlitCommandEncoder>)blitter;
- (MTLOrigin)offsetForIndex:(NSInteger)index;

@end
