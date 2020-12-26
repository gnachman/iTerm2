//
//  iTermImage.m
//  iTerm2
//
//  Created by George Nachman on 8/27/16.
//
//

#import "iTermImage.h"
#import "DebugLogging.h"
#import "iTermImageDecoderDriver.h"
#import "NSData+iTerm.h"
#import "NSImage+iTerm.h"
#import "iTermXpcConnectionHelper.h"

static const CGFloat kMaxDimension = 10000;

#define DECODE_IMAGES_IN_PROCESS 0

#if defined(__has_feature)
#if __has_feature(address_sanitizer)
#undef DECODE_IMAGES_IN_PROCESS
#warning Decoding images in process because address sanitizer is enabled.
#define DECODE_IMAGES_IN_PROCESS 1
#endif
#endif

@interface iTermImage()
@property(nonatomic, strong) NSMutableArray<NSNumber *> *delays;
@property(nonatomic, readwrite) NSSize size;
@property(nonatomic, strong) NSMutableArray<NSImage *> *images;
@end

@implementation iTermImage

+ (instancetype)imageWithNativeImage:(NSImage *)nativeImage {
    iTermImage *image = [[iTermImage alloc] init];
    image.size = nativeImage.size;
    [image.images addObject:nativeImage];
    return image;
}

+ (instancetype)imageWithCompressedData:(NSData *)compressedData {
    char *bytes = (char *)compressedData.bytes;
    if (compressedData.length > 2 &&
        bytes[0] == 27 &&
        bytes[1] == 'P') {
        return [[iTermImage alloc] initWithSixelData:compressedData];
    }
#if DECODE_IMAGES_IN_PROCESS
    NSLog(@"** WARNING: Decompressing image in-process **");
    return [[iTermImage alloc] initWithData:compressedData];
#else
    iTermImage *imageFromXpc = [iTermXpcConnectionHelper imageFromData:compressedData];
    if (imageFromXpc) {
        return imageFromXpc;
    } else {
        iTermImageDecoderDriver *driver = [[iTermImageDecoderDriver alloc] init];
        NSData *jsonData = [driver jsonForCompressedImageData:compressedData
                                                         type:@"image/*"];
        if (jsonData) {
            return [[iTermImage alloc] initWithJson:jsonData];
        } else {
            return nil;
        }
    }
#endif
}

+ (instancetype)imageWithSixelData:(NSData *)sixelData {
    return [[self alloc] initWithSixelData:sixelData];
}

- (instancetype)initWithSixelData:(NSData *)sixel {
    iTermImageDecoderDriver *driver = [[iTermImageDecoderDriver alloc] init];
    NSData *jsonData = [driver jsonForCompressedImageData:sixel
                                                     type:@"image/x-sixel"];
    if (!jsonData) {
        return nil;
    }
    return [[iTermImage alloc] initWithJson:jsonData];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _delays = [[NSMutableArray alloc] init];
        _images = [[NSMutableArray alloc] init];
    }
    return self;
}

/// Only use from `iTerm2SandboxedWorker`
- (instancetype)initWithData:(NSData *)data {
    self = [self init];
    if (self) {
        NSImage *image = [[NSImage alloc] initWithData:data];
        NSImageRep *rep = [[image representations] firstObject];
        NSSize imageSize = NSMakeSize(rep.pixelsWide, rep.pixelsHigh);

        if (imageSize.width == 0 && imageSize.height == 0) {
            // PDFs can hit this case.
            if (image.size.width != 0 && image.size.height != 0) {
                imageSize = image.size;
            } else {
                return nil;
            }
        }
        _size = imageSize;

        BOOL isGIF = NO;
        NSNumber *frameCount;
        NSBitmapImageRep *bitmapImageRep = (NSBitmapImageRep *)rep;
        if ([bitmapImageRep isKindOfClass:[NSBitmapImageRep class]]) {
            frameCount = [bitmapImageRep valueForProperty:NSImageFrameCount];
            if (frameCount != nil) {
                isGIF = YES;
            }
        }
        if (isGIF) {
            double totalDelay = 0;
            for (size_t i = 0; i < frameCount.unsignedIntValue; ++i) {
                [bitmapImageRep setProperty:NSImageCurrentFrame withValue:[NSNumber numberWithUnsignedInt:i]];
                NSData *repData = [bitmapImageRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                NSImage *frame = [[NSImage alloc] initWithData:repData];
                if (!frame) {
                    return nil;
                }
                [_images addObject:frame];
                NSTimeInterval delay = [((NSNumber *)[bitmapImageRep valueForProperty:NSImageCurrentFrameDuration]) doubleValue];
                totalDelay += delay;
                [_delays addObject:@(totalDelay)];
            }
        } else {
#if !DECODE_IMAGES_IN_PROCESS
            if ([rep isKindOfClass:[NSPDFImageRep class]]) {
                return nil;
            }
#endif
            [_images addObject:image];
        }
    }
    return self;
}

- (instancetype)initWithJson:(NSData *)json {
    DLog(@"Initialize iTermImage");
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
    if (!dict) {
        DLog(@"nil json");
        return nil;
    }
    if (![dict isKindOfClass:[NSDictionary class]]) {
        DLog(@"json root of class %@", [dict class]);
        return nil;
    }

    self = [self init];
    if (self) {
        NSArray *delays = dict[@"delays"];
        if (![delays isKindOfClass:[NSArray class]]) {
            DLog(@"delays of class %@", [delays class]);
            return nil;
        }

        NSArray *size = dict[@"size"];
        if (![size isKindOfClass:[NSArray class]]) {
            DLog(@"size of class %@", [size class]);
            return nil;
        }
        if (size.count != 2) {
            DLog(@"size has %@ elements", @(size.count));
            return nil;
        }

        NSArray *imageData = dict[@"images"];
        if (![imageData isKindOfClass:[NSArray class]]) {
            DLog(@"imageData of class %@", [imageData class]);
            return nil;
        }

        if (delays.count != 0 && delays.count != imageData.count) {
            DLog(@"delays.count=%@, imageData.count=%@", @(delays.count), @(imageData.count));
            return nil;
        }

        _size = NSMakeSize([size[0] doubleValue], [size[1] doubleValue]);
        if (_size.width <= 0 || _size.width >= kMaxDimension ||
            _size.height <= 0 || _size.height >= kMaxDimension) {
            DLog(@"Bogus size %@", NSStringFromSize(_size));
            return nil;
        }

        for (id delay in delays) {
            if (![delay isKindOfClass:[NSNumber class]]) {
                DLog(@"Bogus delay of class %@", [delay class]);
                return nil;
            }
            [_delays addObject:delay];
        }

        for (NSString *imageString in imageData) {
            if (![imageString isKindOfClass:[NSString class]]) {
                DLog(@"Bogus image string of class %@", [imageString class]);
            }

            NSData *data = [NSData dataWithBase64EncodedString:imageString];
            if (!data || data.length > kMaxDimension * kMaxDimension * 4) {
                DLog(@"Could not decode base64 encoded image string");
                return nil;
            }

            if (data.length < _size.width * _size.height * 4) {
                DLog(@"data too small %@ < %@", @(data.length), @(_size.width * _size.height * 4));
                return nil;
            }

            NSImage *image = [NSImage imageWithRawData:data
                                                  size:_size
                                         bitsPerSample:8
                                       samplesPerPixel:4
                                              hasAlpha:YES
                                        colorSpaceName:NSDeviceRGBColorSpace];
            if (!image) {
                DLog(@"Failed to create NSImage from data");
                return nil;
            }
            [_images addObject:image];
        }
    }
    DLog(@"Successfully inited iTermImage");

    return self;
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [coder encodeObject:self.delays forKey:@"delays"];
    [coder encodeSize:self.size forKey:@"size"];
    [coder encodeObject:self.images forKey:@"images"];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
    @try {
        _delays = [coder decodeObjectOfClasses:[NSSet setWithArray:@[[NSMutableArray class], [NSNumber class]]] forKey:@"delays"];
        _size = [coder decodeSizeForKey:@"size"];
        _images = [coder decodeObjectOfClasses:[NSSet setWithArray:@[[NSMutableArray class], [NSImage class]]] forKey:@"images"];
    } @catch (NSException * exception) {
        XLog(@"Failed to decode image: %@", exception);
        return nil;
    }
    return self;
}

@end
