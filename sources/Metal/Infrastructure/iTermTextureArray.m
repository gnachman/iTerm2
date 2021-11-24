#import <AppKit/AppKit.h>

#import "DebugLogging.h"
#import "iTermTexture.h"
#import "iTermTextureArray.h"
#import "NSArray+iTerm.h"
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

- (instancetype)initWithImages:(NSArray<NSImage *> *)images device:(id <MTLDevice>)device {
    if (images.count == 0) {
        return nil;
    }
    MTKTextureLoader *loader = [[MTKTextureLoader alloc] initWithDevice:device];
    NSDictionary *options = @{ MTKTextureLoaderOptionTextureStorageMode: @(MTLStorageModeShared) };
    NSArray<id<MTLTexture>> *textures = [images mapWithBlock:^id(NSImage *image) {
        return [loader newTextureWithCGImage:image.CGImage options:options error:nil];
    }];
    if (textures.count != images.count) {
        return nil;
    }

    self = [self initWithTextureWidth:textures[0].width
                        textureHeight:textures[0].height
                          arrayLength:images.count
                          pixelFormat:textures[0].pixelFormat
                               device:device];
    if (self) {
        [textures enumerateObjectsUsingBlock:^(id<MTLTexture> texture, NSUInteger idx, BOOL * _Nonnull stop) {
            [self setSlice:idx texture:texture];
        }];
    }

    return self;
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
        } else if (pixelFormat == MTLPixelFormatBGRA8Unorm ||
                   pixelFormat == MTLPixelFormatRGBA8Unorm) {
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
    [self setSlice:slice bitmap:bitmap];
    return YES;
}

- (void)setSlice:(NSUInteger)slice bitmap:(NSBitmapImageRep *)bitmap {
    const MTLOrigin origin = [self offsetForIndex:slice];
    const MTLRegion region = MTLRegionMake2D(origin.x, origin.y, _width, _height);
    [_texture replaceRegion:region
                mipmapLevel:0
                      slice:0
                  withBytes:bitmap.bitmapData
                bytesPerRow:bitmap.bytesPerRow
              bytesPerImage:bitmap.bytesPerRow * _height];
}

static NSUInteger iTermTextureBytesPerSampleForMetalPixelFormat(MTLPixelFormat pixelFormat) {
    switch (pixelFormat) {
        case MTLPixelFormatA8Unorm:
        case MTLPixelFormatR8Unorm:
        case MTLPixelFormatR8Unorm_sRGB:
        case MTLPixelFormatR8Snorm:
        case MTLPixelFormatR8Uint:
        case MTLPixelFormatR8Sint:
            return 1;

        case MTLPixelFormatR16Unorm:
        case MTLPixelFormatR16Snorm:
        case MTLPixelFormatR16Uint:
        case MTLPixelFormatR16Sint:
        case MTLPixelFormatR16Float:
        case MTLPixelFormatRG8Unorm:
        case MTLPixelFormatRG8Unorm_sRGB:
        case MTLPixelFormatRG8Snorm:
        case MTLPixelFormatRG8Uint:
        case MTLPixelFormatRG8Sint:
        case MTLPixelFormatB5G6R5Unorm:
        case MTLPixelFormatA1BGR5Unorm:
        case MTLPixelFormatABGR4Unorm:
        case MTLPixelFormatBGR5A1Unorm:
            return 2;

        case MTLPixelFormatR32Uint:
        case MTLPixelFormatR32Sint:
        case MTLPixelFormatR32Float:
        case MTLPixelFormatRG16Unorm:
        case MTLPixelFormatRG16Snorm:
        case MTLPixelFormatRG16Uint:
        case MTLPixelFormatRG16Sint:
        case MTLPixelFormatRG16Float:
        case MTLPixelFormatRGBA8Unorm:
        case MTLPixelFormatRGBA8Unorm_sRGB:
        case MTLPixelFormatRGBA8Snorm:
        case MTLPixelFormatRGBA8Uint:
        case MTLPixelFormatRGBA8Sint:
        case MTLPixelFormatBGRA8Unorm:
        case MTLPixelFormatBGRA8Unorm_sRGB:
        case MTLPixelFormatRGB10A2Unorm:
        case MTLPixelFormatRGB10A2Uint:
        case MTLPixelFormatRG11B10Float:
        case MTLPixelFormatRGB9E5Float:
        case MTLPixelFormatBGR10A2Unorm:
        case MTLPixelFormatBGR10_XR:
        case MTLPixelFormatBGR10_XR_sRGB:
            return 4;

        case MTLPixelFormatRG32Uint:
        case MTLPixelFormatRG32Sint:
        case MTLPixelFormatRG32Float:
        case MTLPixelFormatRGBA16Unorm:
        case MTLPixelFormatRGBA16Snorm:
        case MTLPixelFormatRGBA16Uint:
        case MTLPixelFormatRGBA16Sint:
        case MTLPixelFormatRGBA16Float:
        case MTLPixelFormatBGRA10_XR:
        case MTLPixelFormatBGRA10_XR_sRGB:
            return 8;

            /* Normal 128 bit formats */

        case MTLPixelFormatRGBA32Uint:
        case MTLPixelFormatRGBA32Sint:
        case MTLPixelFormatRGBA32Float:
            return 16;

            // Unsupported (compressed, not rgb, etc.)
        case MTLPixelFormatBC1_RGBA:
        case MTLPixelFormatBC1_RGBA_sRGB:
        case MTLPixelFormatBC2_RGBA:
        case MTLPixelFormatBC2_RGBA_sRGB:
        case MTLPixelFormatBC3_RGBA:
        case MTLPixelFormatBC3_RGBA_sRGB:
        case MTLPixelFormatBC4_RUnorm:
        case MTLPixelFormatBC4_RSnorm:
        case MTLPixelFormatBC5_RGUnorm:
        case MTLPixelFormatBC5_RGSnorm:
        case MTLPixelFormatBC6H_RGBFloat:
        case MTLPixelFormatBC6H_RGBUfloat:
        case MTLPixelFormatBC7_RGBAUnorm:
        case MTLPixelFormatBC7_RGBAUnorm_sRGB:
        case MTLPixelFormatPVRTC_RGB_2BPP:
        case MTLPixelFormatPVRTC_RGB_2BPP_sRGB:
        case MTLPixelFormatPVRTC_RGB_4BPP:
        case MTLPixelFormatPVRTC_RGB_4BPP_sRGB:
        case MTLPixelFormatPVRTC_RGBA_2BPP:
        case MTLPixelFormatPVRTC_RGBA_2BPP_sRGB:
        case MTLPixelFormatPVRTC_RGBA_4BPP:
        case MTLPixelFormatPVRTC_RGBA_4BPP_sRGB:
        case MTLPixelFormatEAC_R11Unorm:
        case MTLPixelFormatEAC_R11Snorm:
        case MTLPixelFormatEAC_RG11Unorm:
        case MTLPixelFormatEAC_RG11Snorm:
        case MTLPixelFormatEAC_RGBA8:
        case MTLPixelFormatEAC_RGBA8_sRGB:
        case MTLPixelFormatETC2_RGB8:
        case MTLPixelFormatETC2_RGB8_sRGB:
        case MTLPixelFormatETC2_RGB8A1:
        case MTLPixelFormatETC2_RGB8A1_sRGB:
        case MTLPixelFormatASTC_4x4_sRGB:
        case MTLPixelFormatASTC_5x4_sRGB:
        case MTLPixelFormatASTC_5x5_sRGB:
        case MTLPixelFormatASTC_6x5_sRGB:
        case MTLPixelFormatASTC_6x6_sRGB:
        case MTLPixelFormatASTC_8x5_sRGB:
        case MTLPixelFormatASTC_8x6_sRGB:
        case MTLPixelFormatASTC_8x8_sRGB:
        case MTLPixelFormatASTC_10x5_sRGB:
        case MTLPixelFormatASTC_10x6_sRGB:
        case MTLPixelFormatASTC_10x8_sRGB:
        case MTLPixelFormatASTC_10x10_sRGB:
        case MTLPixelFormatASTC_12x10_sRGB:
        case MTLPixelFormatASTC_12x12_sRGB:
        case MTLPixelFormatASTC_4x4_LDR:
        case MTLPixelFormatASTC_5x4_LDR:
        case MTLPixelFormatASTC_5x5_LDR:
        case MTLPixelFormatASTC_6x5_LDR:
        case MTLPixelFormatASTC_6x6_LDR:
        case MTLPixelFormatASTC_8x5_LDR:
        case MTLPixelFormatASTC_8x6_LDR:
        case MTLPixelFormatASTC_8x8_LDR:
        case MTLPixelFormatASTC_10x5_LDR:
        case MTLPixelFormatASTC_10x6_LDR:
        case MTLPixelFormatASTC_10x8_LDR:
        case MTLPixelFormatASTC_10x10_LDR:
        case MTLPixelFormatASTC_12x10_LDR:
        case MTLPixelFormatASTC_12x12_LDR:
        case MTLPixelFormatASTC_4x4_HDR:
        case MTLPixelFormatASTC_5x4_HDR:
        case MTLPixelFormatASTC_5x5_HDR:
        case MTLPixelFormatASTC_6x5_HDR:
        case MTLPixelFormatASTC_6x6_HDR:
        case MTLPixelFormatASTC_8x5_HDR:
        case MTLPixelFormatASTC_8x6_HDR:
        case MTLPixelFormatASTC_8x8_HDR:
        case MTLPixelFormatASTC_10x5_HDR:
        case MTLPixelFormatASTC_10x6_HDR:
        case MTLPixelFormatASTC_10x8_HDR:
        case MTLPixelFormatASTC_10x10_HDR:
        case MTLPixelFormatASTC_12x10_HDR:
        case MTLPixelFormatASTC_12x12_HDR:
        case MTLPixelFormatGBGR422:
        case MTLPixelFormatBGRG422:
        case MTLPixelFormatDepth16Unorm:
        case MTLPixelFormatDepth32Float:
        case MTLPixelFormatStencil8:
        case MTLPixelFormatDepth24Unorm_Stencil8:
        case MTLPixelFormatDepth32Float_Stencil8:
        case MTLPixelFormatX32_Stencil8:
        case MTLPixelFormatX24_Stencil8:
        case MTLPixelFormatInvalid:
            break;
    }
    ITAssertWithMessage(NO, @"Bad pixel format %@", @(pixelFormat));
    return 0;
}

- (void)setSlice:(NSUInteger)slice texture:(id<MTLTexture>)sourceTexture {
    const MTLOrigin origin = [self offsetForIndex:slice];
    const MTLRegion region = MTLRegionMake2D(origin.x, origin.y, _width, _height);

    const NSUInteger bytesPerSample = iTermTextureBytesPerSampleForMetalPixelFormat(sourceTexture.pixelFormat);
    const NSUInteger bytesPerRow = sourceTexture.width * bytesPerSample;

    const NSUInteger length = bytesPerRow * _height;
    NSMutableData *temp = [NSMutableData dataWithLength:length];
    unsigned char *bytes = (unsigned char *)temp.mutableBytes;

    [sourceTexture getBytes:bytes
                bytesPerRow:bytesPerRow
                 fromRegion:MTLRegionMake2D(0, 0, _width, _height)
                mipmapLevel:0];

    [_texture replaceRegion:region
                mipmapLevel:0
                      slice:0
                  withBytes:temp.bytes
                bytesPerRow:bytesPerRow
              bytesPerImage:bytesPerRow * _height];
}

@end

