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

int main(int argc, const char * argv[]) {
    syslog(LOG_DEBUG, "image_decoder started");
    @autoreleasepool {
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

        NSImage *image = [[NSImage alloc] initWithData:data];
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

