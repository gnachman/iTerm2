#import <Metal/Metal.h>

#import "iTermCharacterBitmap.h"
#import "iTermCharacterParts.h"

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermTextureArray : NSObject {
@public
    uint32_t _width;
    uint32_t _height;
    NSInteger _cellsPerRow;
}

@property (nonatomic, readonly) id <MTLTexture> texture;
@property (nonatomic, readonly) uint32_t width;
@property (nonatomic, readonly) uint32_t height;
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) CGSize atlasSize;

+ (CGSize)atlasSizeForUnitSize:(CGSize)unitSize
                   arrayLength:(NSUInteger)length
                   cellsPerRow:(out NSInteger *)cellsPerRowOut;

- (instancetype)initWithTextureWidth:(uint32_t)width
                       textureHeight:(uint32_t)height
                         arrayLength:(NSUInteger)length
                              device:(id <MTLDevice>)device;

- (BOOL)addSliceWithContentsOfFile:(NSString *)path;
- (void)addSliceWithImage:(NSImage *)image;
- (BOOL)setSlice:(NSUInteger)slice withImage:(NSImage *)nsimage;
- (void)setSlice:(NSUInteger)slice withBitmap:(iTermCharacterBitmap *)bitmap;

- (void)copyTextureAtIndex:(NSInteger)index
                   toArray:(iTermTextureArray *)destination
                     index:(NSInteger)destinationIndex
                   blitter:(id<MTLBlitCommandEncoder>)blitter;
- (MTLOrigin)offsetForIndex:(NSInteger)index;

@end

NS_CLASS_AVAILABLE(10_11, NA)
NS_INLINE MTLOrigin iTermTextureArrayOffsetForIndex(iTermTextureArray *self, const NSInteger index) {
    return MTLOriginMake(self->_width * (index % self->_cellsPerRow),
                         self->_height * (index / self->_cellsPerRow),
                         0);
}
