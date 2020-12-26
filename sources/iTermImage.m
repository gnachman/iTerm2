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
        return [self imageWithSixelData:compressedData];
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
        NSData *jsonData = [driver jsonForCompressedImageData:compressedData];
        if (jsonData) {
            NSError *error;
            NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:jsonData error:&error];
            iTermImage *image = [unarchiver decodeObjectOfClass:[iTermImage class] forKey:@"image"];
            if (error || !image) {
                XLog(@"Error during image decode: %@", error ?: [NSNull null]);
                return nil;
            }
            return image;
        } else {
            return nil;
        }
    }
#endif
}

+ (instancetype)imageWithSixelData:(NSData *)sixelData {
    return [iTermXpcConnectionHelper imageFromSixelData:sixelData];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _delays = [[NSMutableArray alloc] init];
        _images = [[NSMutableArray alloc] init];
    }
    return self;
}

#if DECODE_IMAGES_IN_PROCESS
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
            if (frameCount.intValue > 1) {
                isGIF = YES;
            }
        }
        if (isGIF) {
            double totalDelay = 0;
            for (int i = 0; i < frameCount.intValue; ++i) {
                [bitmapImageRep setProperty:NSImageCurrentFrame withValue:[NSNumber numberWithInt:i]];
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
            [_images addObject:image];
        }
    }
    return self;
}
#endif

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    ELog(@"The main app is trying to encode an iTermImage");
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
    @try {
        _delays = [coder decodeObjectOfClasses:[NSSet setWithArray:@[[NSMutableArray class], [NSNumber class]]] forKey:@"delays"];
        _size = [coder decodeSizeForKey:@"size"];
        if (_size.width <= 0 || _size.width >= kMaxDimension ||
            _size.height <= 0 || _size.height >= kMaxDimension) {
            DLog(@"Bogus size %@", NSStringFromSize(_size));
            return nil;
        }
        _images = [NSMutableArray new];
        NSMutableArray<NSData *> *imageDatas = [coder decodeObjectOfClasses:[NSSet setWithArray:@[[NSMutableArray class], [NSData class]]] forKey:@"images"];
        for (NSData *imageData in imageDatas) {
            if (imageData.length != _size.width * _size.height * 4) {
                return nil;
            }
            NSImage *image = [NSImage imageWithRawData:imageData
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
        if ((_images.count > 1 && _delays.count != _images.count) || !_images.count || _delays.count == 1) {
            DLog(@"delays.count=%@, images.count=%@", @(_delays.count), @(_images.count));
            return nil;
        }
    } @catch (NSException * exception) {
        XLog(@"Failed to decode image: %@", exception);
        return nil;
    }
    return self;
}

@end
