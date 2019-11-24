//
//  main.m
//  image_decoder
//
//  Created by George Nachman on 8/27/16.
//
//

#import <Cocoa/Cocoa.h>
#include <syslog.h>
#import "iTermSerializableImage.h"
#include "sixel.h"

@implementation NSImage(ImageDecoder)
+ (instancetype)imageWithRawData:(NSData *)data
                            size:(NSSize)size
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

    NSImage *theImage = [[NSImage alloc] initWithSize:size];
    [theImage addRepresentation:bitmapImageRep];

    return theImage;
}
@end

static const NSUInteger kMaxBytes = 20 * 1024 * 1024;

static NSDictionary *GIFProperties(CGImageSourceRef source, size_t i) {
    CFDictionaryRef const properties = CGImageSourceCopyPropertiesAtIndex(source, i, NULL);
    if (properties) {
        CFDictionaryRef const gifProperties = CFDictionaryGetValue(properties,
                                                                   kCGImagePropertyGIFDictionary);
        NSDictionary *result = [(__bridge NSDictionary *)gifProperties copy];
        return result;
    } else {
        return nil;
    }
}

static NSTimeInterval DelayInGifProperties(NSDictionary *gifProperties) {
    NSTimeInterval delay = 0.01;
    if (gifProperties) {
        NSNumber *number = (id)CFDictionaryGetValue((CFDictionaryRef)gifProperties,
                                                    kCGImagePropertyGIFUnclampedDelayTime);
        if (number == NULL || [number doubleValue] == 0) {
            number = (id)CFDictionaryGetValue((CFDictionaryRef)gifProperties,
                                              kCGImagePropertyGIFDelayTime);
        }
        if ([number doubleValue] > 0) {
            delay = number.doubleValue;
        }
    }

    return delay;
}

static NSImage *DecodeSixelData(sixel_decoder_t *decoder, NSData *data) {
    unsigned char *pixels = NULL;
    int width = 0;
    int height = 0;
    unsigned char *palette = NULL;  // argb
    int ncolors = 0;
    if (data.length >= INT_MAX) {
        return nil;
    }
    SIXELSTATUS status = sixel_decode_raw((unsigned char *)[[data mutableCopy] mutableBytes],
                                          (int)data.length,
                                          &pixels,
                                          &width,
                                          &height,
                                          &palette,
                                          &ncolors,
                                          NULL);
    if (status != SIXEL_OK || ncolors <= 0) {
        return nil;
    }

    const int limit = ncolors - 1;
    NSMutableData *rgbaData = [NSMutableData dataWithLength:width * height * 4];
    unsigned char *rgba = rgbaData.mutableBytes;
    const int stride = 3;
    for (int i = 0; i < width * height; i++) {
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
    sixel_decoder_t *decoder;
    SIXELSTATUS status = sixel_decoder_new(&decoder, NULL);
    if (status != SIXEL_OK) {
        return nil;
    }
    NSArray<NSString *> *paramParts = [paramString componentsSeparatedByString:@";"];
    [paramParts enumerateObjectsUsingBlock:^(NSString * _Nonnull value, NSUInteger index, BOOL * _Nonnull stop) {
        sixel_decoder_setopt(decoder,
                             (int)index,
                             value.UTF8String);
    }];

    NSImage *image = DecodeSixelData(decoder, payload);
    sixel_decoder_unref(decoder);

    return image;
}

int main(int argc, const char * argv[]) {
    syslog(LOG_DEBUG, "image_decoder started");
    @autoreleasepool {
        NSString *type;
        if (argc > 1) {
            type = [[NSString alloc] initWithUTF8String:argv[1]];
        } else {
            type = @"image/*";
        }

        iTermSerializableImage *serializableImage = [[iTermSerializableImage alloc] init];
        NSFileHandle *fileHandle = [[NSFileHandle alloc] initWithFileDescriptor:0];
        NSData *data = nil;
        @try {
            syslog(LOG_DEBUG, "Reading image on fd 0");
            data = [fileHandle readDataToEndOfFile];
        } @catch (NSException *exception) {
            syslog(LOG_ERR, "Failed to read: %s", [[exception debugDescription] UTF8String]);
            exit(1);
        }

        NSImage *image;
        if ([type isEqualToString:@"image/x-sixel"]) {
            image = ImageFromSixelData(data);
        } else {
            image = [[NSImage alloc] initWithData:data];
        }
        if (!image) {
            syslog(LOG_ERR, "data did not produce valid image");
            exit(1);
        }

        CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)data,
                                                              (CFDictionaryRef)@{});
        size_t count = CGImageSourceGetCount(source);
        NSImageRep *rep = [[image representations] firstObject];
        NSSize imageSize = NSMakeSize(rep.pixelsWide, rep.pixelsHigh);

        if (imageSize.width == 0 && imageSize.height == 0) {
            // PDFs can hit this case.
            if (image.size.width != 0 && image.size.height != 0) {
                imageSize = image.size;
            } else {
                syslog(LOG_ERR, "extracted image was 0x0");
                exit(1);
            }
        }
        serializableImage.size = imageSize;

        BOOL isGIF = NO;
        if (count > 1) {
            syslog(LOG_DEBUG, "multiple frames found");
            NSMutableArray *frameProperties = [NSMutableArray array];
            isGIF = YES;
            for (size_t i = 0; i < count; ++i) {
                NSDictionary *gifProperties = GIFProperties(source, i);
                // TIFF and PDF files may have multiple pages, so make sure it's an animated GIF.
                if (gifProperties) {
                    [frameProperties addObject:gifProperties];
                } else {
                    isGIF = NO;
                    break;
                }
            }
            if (isGIF) {
                syslog(LOG_DEBUG, "is an animated gif");
                double totalDelay = 0;
                NSUInteger totalSize = 0;
                for (size_t i = 0; i < count; ++i) {
                    CGImageRef imageRef = CGImageSourceCreateImageAtIndex(source, i, NULL);
                    NSImage *image = [[NSImage alloc] initWithCGImage:imageRef
                                                                 size:NSMakeSize(CGImageGetWidth(imageRef),
                                                                                 CGImageGetHeight(imageRef))];
                    if (!image) {
                        syslog(LOG_ERR, "could not get image from gif frame");
                        exit(1);
                    }
                    NSUInteger bytes = image.size.width * image.size.height * 4;
                    if (totalSize + bytes > kMaxBytes) {
                        break;
                    }
                    totalSize += bytes;

                    [serializableImage.images addObject:image];
                    CFRelease(imageRef);
                    NSTimeInterval delay = DelayInGifProperties(frameProperties[i]);
                    totalDelay += delay;
                    [serializableImage.delays addObject:@(totalDelay)];
                }
            }
        }
        if (!isGIF) {
            syslog(LOG_DEBUG, "adding decoded image");
            [serializableImage.images addObject:image];
        }

        syslog(LOG_DEBUG, "converting json");
        NSData *jsonValue = [serializableImage jsonValue];
        syslog(LOG_DEBUG, "writing data out");
        fileHandle = [[NSFileHandle alloc] initWithFileDescriptor:1];
        [fileHandle writeData:jsonValue];
        syslog(LOG_DEBUG, "done");
    }
    return 0;
}

