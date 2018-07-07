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

static const CGFloat kMaxDimension = 10000;

@interface iTermImage()
@property(nonatomic, retain) NSMutableArray<NSNumber *> *delays;
@property(nonatomic, readwrite) NSSize size;
@property(nonatomic, retain) NSMutableArray<NSImage *> *images;
@end

#if DEBUG
static NSDictionary *GIFProperties(CGImageSourceRef source, size_t i) {
    CFDictionaryRef const properties = CGImageSourceCopyPropertiesAtIndex(source, i, NULL);
    if (properties) {
        NSDictionary *gifProperties = (NSDictionary *)CFDictionaryGetValue(properties,
                                                                           kCGImagePropertyGIFDictionary);
        gifProperties = [[gifProperties copy] autorelease];
        CFRelease(properties);
        return gifProperties;
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
#endif

@implementation iTermImage

+ (instancetype)imageWithNativeImage:(NSImage *)nativeImage {
    iTermImage *image = [[iTermImage alloc] init];
    image.size = nativeImage.size;
    [image.images addObject:nativeImage];
    return [image autorelease];
}

+ (instancetype)imageWithCompressedData:(NSData *)compressedData {
#if DEBUG
    NSLog(@"** WARNING: Decompressing image in-process **");
    return [[[iTermImage alloc] initWithData:compressedData] autorelease];
#else
    iTermImageDecoderDriver *driver = [[[iTermImageDecoderDriver alloc] init] autorelease];
    NSData *jsonData = [driver jsonForCompressedImageData:compressedData];
    if (jsonData) {
        return [[[iTermImage alloc] initWithJson:jsonData] autorelease];
    } else {
        return nil;
    }
#endif
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _delays = [[NSMutableArray alloc] init];
        _images = [[NSMutableArray alloc] init];
    }
    return self;
}

#if DEBUG
- (instancetype)initWithData:(NSData *)data {
    self = [self init];
    if (self) {
        NSImage *image = [[[NSImage alloc] initWithData:data] autorelease];
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
                if (source) {
                    CFRelease(source);
                }
                [self release];
                return nil;
            }
        }
        _size = imageSize;

        BOOL isGIF = NO;
        if (count > 1) {
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
                double totalDelay = 0;
                for (size_t i = 0; i < count; ++i) {
                    CGImageRef imageRef = CGImageSourceCreateImageAtIndex(source, i, NULL);
                    NSImage *image = [[[NSImage alloc] initWithCGImage:imageRef
                                                                  size:NSMakeSize(CGImageGetWidth(imageRef),
                                                                                  CGImageGetHeight(imageRef))] autorelease];
                    if (!image) {
                        if (imageRef) {
                            CFRelease(imageRef);
                        }
                        return nil;
                    }
                    [_images addObject:image];
                    CFRelease(imageRef);
                    NSTimeInterval delay = DelayInGifProperties(frameProperties[i]);
                    totalDelay += delay;
                    [_delays addObject:@(totalDelay)];
                }
            }
        }
        if (!isGIF) {
            [_images addObject:image];
        }
        CFRelease(source);
    }
    return self;
}
#endif

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

- (void)dealloc {
    [_images release];
    [_delays release];
    [super dealloc];
}

@end
