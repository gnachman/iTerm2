//
//  iTermImage+Sixel.m
//  iTerm2SandboxedWorker
//
//  Created by Benedek Kozma on 2020. 12. 26..
//

#import "iTermImage+Sixel.h"
#import "iTermImage+Private.h"
#include "sixel.h"
#import "iTermSixelSize.h"

@implementation NSImage(ImageDecoder)

+ (instancetype)imageWithRawData:(NSData *)data
                            size:(NSSize)size
                      scaledSize:(NSSize)scaledSize
                   bitsPerSample:(NSInteger)bitsPerSample
                 samplesPerPixel:(NSInteger)samplesPerPixel
                        hasAlpha:(BOOL)hasAlpha
                  colorSpaceName:(NSString *)colorSpaceName {
    assert(data.length == size.width * size.height * bitsPerSample * samplesPerPixel / 8);
    NSBitmapImageRep *bitmapImageRep =
    [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nil  // allocate the pixel buffer for us
                                            pixelsWide:size.width
                                            pixelsHigh:size.height
                                         bitsPerSample:bitsPerSample
                                       samplesPerPixel:samplesPerPixel
                                              hasAlpha:hasAlpha
                                              isPlanar:NO
                                        colorSpaceName:colorSpaceName
                                           bytesPerRow:bitsPerSample * samplesPerPixel * size.width / 8
                                          bitsPerPixel:bitsPerSample * samplesPerPixel];  // 0 means OS infers it
    
    memmove([bitmapImageRep bitmapData], data.bytes, data.length);
    
    NSImage *theImage = [[NSImage alloc] initWithSize:scaledSize];
    [theImage addRepresentation:bitmapImageRep];
    
    return theImage;
}

@end

static NSImage *DecodeSixelData(NSData *data) {
    unsigned char *pixels = NULL;
    int width = 0;
    int height = 0;
    unsigned char *palette = NULL;  // argb
    int ncolors = 0;
    if (data.length >= INT_MAX) {
        return nil;
    }
    // Refuse oversized buffers inside libsixel, before it commits memory for them.
    sixel_allocator_t *allocator = NULL;
    if (SIXEL_FAILED(sixel_allocator_new(&allocator,
                                         iTermSixelMalloc,
                                         iTermSixelCalloc,
                                         iTermSixelRealloc,
                                         free))) {
        return nil;
    }
    SIXELSTATUS status = sixel_decode_raw((unsigned char *)[[data mutableCopy] mutableBytes],
                                          (int)data.length,
                                          &pixels,
                                          &width,
                                          &height,
                                          &palette,
                                          &ncolors,
                                          allocator);
    sixel_allocator_unref(allocator);
    size_t pixelCount = 0;
    size_t byteCount = 0;
    if (status != SIXEL_OK || ncolors <= 0 || !iTermSixelRGBASize(width, height, &pixelCount, &byteCount)) {
        // Computing width * height * 4 in int could overflow and undersize the buffer below.
        free(palette);
        free(pixels);
        return nil;
    }

    const int limit = ncolors - 1;
    NSMutableData *rgbaData = [NSMutableData dataWithLength:byteCount];
    if (!rgbaData) {
        free(palette);
        free(pixels);
        return nil;
    }
    unsigned char *rgba = rgbaData.mutableBytes;
    const int stride = 3;
    for (size_t i = 0; i < pixelCount; i++) {
        const unsigned char index = MAX(0, MIN(pixels[i], limit));
        rgba[i * 4 + 0] = palette[index * stride + 0];
        rgba[i * 4 + 1] = palette[index * stride + 1];
        rgba[i * 4 + 2] = palette[index * stride + 2];
        rgba[i * 4 + 3] = 0xff;
    }
    free(palette);
    free(pixels);
    return [NSImage imageWithRawData:rgbaData
                                size:NSMakeSize(width, height)
                          scaledSize:NSMakeSize(width, height)
                       bitsPerSample:8
                     samplesPerPixel:4
                            hasAlpha:YES
                      colorSpaceName:NSDeviceRGBColorSpace];
}


static NSImage *ImageFromSixelData(NSData *data) {
    NSData *newlineData = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange range = [data rangeOfData:newlineData options:0 range:NSMakeRange(0, data.length)];
    if (range.location == NSNotFound) {
        return nil;
    }
    NSData *params = [data subdataWithRange:NSMakeRange(0, range.location)];
    NSData *payload = [data subdataWithRange:NSMakeRange(NSMaxRange(range), data.length - NSMaxRange(range))];
    NSString *paramString = [[NSString alloc] initWithData:params encoding:NSUTF8StringEncoding];
    if (!paramString) {
        return nil;
    }
    // The DCS parameters used to be passed to sixel_decoder_setopt() with each parameter's
    // position as the option letter, which made no sense, and sixel_decode_raw() never consults a
    // decoder anyway.
    return DecodeSixelData(payload);
}

@implementation iTermImage(Sixel)

- (instancetype)initWithSixelData:(NSData *)data {
    self = [self init];
    if (self) {
        NSImage *image = ImageFromSixelData(data);
        if (!image) {
            return nil;
        }
        [self.images addObject:image];
        self.size = image.size;
        self.scaledSize = image.size;
    }
    return self;
}

@end
