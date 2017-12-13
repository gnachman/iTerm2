#import <Metal/Metal.h>

#ifdef __cplusplus
extern "C" {
#endif
#warning TODO Find a better home for this. Also make them inline.
    extern int ImagePartDX(int part);
    extern int ImagePartDY(int part);
    extern int ImagePartFromDeltas(int dx, int dy);

    extern const int iTermTextureMapMaxCharacterParts;
    extern const int iTermTextureMapMiddleCharacterPart;

#ifdef __cplusplus
}
#endif

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermTextureArray : NSObject

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
- (void)copyTextureAtIndex:(NSInteger)index
                   toArray:(iTermTextureArray *)destination
                     index:(NSInteger)destinationIndex
                   blitter:(id<MTLBlitCommandEncoder>)blitter;
- (MTLOrigin)offsetForIndex:(NSInteger)index;

@end
