#import <AppKit/AppKit.h>

#import "DebugLogging.h"
#import "iTermTexture.h"
#import "iTermTextureArray.h"
#import "NSImage+iTerm.h"
#import <CoreImage/CoreImage.h>

@implementation iTermTextureArray {
    NSUInteger _count;
    NSUInteger _arrayLength;
}

+ (CGSize)atlasSizeForUnitSize:(CGSize)unitSize arrayLength:(NSUInteger)length cellsPerRow:(out NSInteger *)cellsPerRowOut {
    CGFloat pixelsNeeded = unitSize.width * unitSize.height * (double)length;
    CGFloat minimumEdgeLength = ceil(sqrt(pixelsNeeded));
    NSInteger cellsPerRow = MAX(1, ceil(minimumEdgeLength / unitSize.width));
    if (cellsPerRowOut) {
        *cellsPerRowOut = cellsPerRow;
    }
    return CGSizeMake(unitSize.width * cellsPerRow,
                      unitSize.height * ceil((double)length / (double)cellsPerRow));
}

- (instancetype)initWithTextureWidth:(uint32_t)width
                       textureHeight:(uint32_t)height
                         arrayLength:(NSUInteger)length
                         pixelFormat:(MTLPixelFormat)pixelFormat
                              device:(id <MTLDevice>)device {
    self = [super init];
    if (self) {
        _width = width;
        _height = height;
        _arrayLength = length;
        CGSize atlasSize = [iTermTextureArray atlasSizeForUnitSize:CGSizeMake(width, height)
                                                       arrayLength:length
                                                       cellsPerRow:&_cellsPerRow];

        MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];

        textureDescriptor.textureType = MTLTextureType2D;
        textureDescriptor.pixelFormat = pixelFormat;
        textureDescriptor.width = atlasSize.width;
        textureDescriptor.height = atlasSize.height;
        textureDescriptor.arrayLength = 1;

        _atlasSize = CGSizeMake(textureDescriptor.width, textureDescriptor.height);

        _texture = [device newTextureWithDescriptor:textureDescriptor];
        _texture.label = @"iTermTextureArray";
        NSInteger bytesPerSample = 1;
        if (pixelFormat == MTLPixelFormatRGBA16Float) {
            bytesPerSample = 2;
        } else if (pixelFormat == MTLPixelFormatBGRA8Unorm) {
            bytesPerSample = 1;
        } else {
            ITAssertWithMessage(NO, @"Unexpected pixel format %@", @(pixelFormat));
        }
        [iTermTexture setBytesPerRow:_atlasSize.width * 4 * bytesPerSample
                         rawDataSize:_atlasSize.width * _atlasSize.height * 4 * bytesPerSample
                     samplesPerPixel:4
                          forTexture:_texture];
    }

    return self;
}

- (void)dealloc {
    _texture = nil;
}

#pragma mark - APIs

- (BOOL)addSliceWithContentsOfFile:(NSString *)path {
    return [self setSlice:_count++ withContentsOfFile:path];
}

- (void)addSliceWithImage:(NSImage *)image {
    [self setSlice:_count++ withImage:image];
}

- (void)copyTextureAtIndex:(NSInteger)index
                   toArray:(iTermTextureArray *)destination
                     index:(NSInteger)destinationIndex
                   blitter:(id<MTLBlitCommandEncoder>)blitter {
    [blitter copyFromTexture:_texture
                 sourceSlice:0
                 sourceLevel:0
                sourceOrigin:[self offsetForIndex:index]
                  sourceSize:MTLSizeMake(_width, _height, 1)
                   toTexture:destination.texture
            destinationSlice:0
            destinationLevel:0
           destinationOrigin:[destination offsetForIndex:destinationIndex]];
}

- (MTLOrigin)offsetForIndex:(NSInteger)index {
    return iTermTextureArrayOffsetForIndex(self, index);
}

#pragma mark - Private

- (BOOL)setSlice:(NSUInteger)slice withContentsOfFile:(NSString *)path {
    return [self setSlice:slice withImage:[[NSImage alloc] initWithContentsOfFile:path]];
}

- (void)setSlice:(NSUInteger)slice withBitmap:(iTermCharacterBitmap *)bitmap {
    ITDebugAssert(slice < _arrayLength);
    MTLOrigin origin = [self offsetForIndex:slice];
    MTLRegion region = MTLRegionMake2D(origin.x, origin.y, _width, _height);

    [_texture replaceRegion:region
                mipmapLevel:0
                      slice:0
                  withBytes:bitmap.data.bytes
                bytesPerRow:bitmap.size.width * 4
              bytesPerImage:bitmap.size.height * bitmap.size.width * 4];
}

- (BOOL)setSlice:(NSUInteger)slice withImage:(NSImage *)nsimage {
    ITDebugAssert(slice < _arrayLength);

    NSBitmapImageRep *bitmap = [[nsimage it_verticallyFlippedImage] it_bitmapImageRep];
    if (!bitmap) {
        return NO;
    }
    const MTLOrigin origin = [self offsetForIndex:slice];
    const MTLRegion region = MTLRegionMake2D(origin.x, origin.y, _width, _height);
    [_texture replaceRegion:region
                mipmapLevel:0
                      slice:0
                  withBytes:bitmap.bitmapData
                bytesPerRow:bitmap.bytesPerRow
              bytesPerImage:bitmap.bytesPerRow * _height];
    return YES;
}

@end

