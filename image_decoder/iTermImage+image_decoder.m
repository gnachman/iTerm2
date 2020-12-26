#if !__has_feature(objc_arc)
#error ARC required
#endif
//
//  iTermSerializableImage.m
//  iTerm2
//
//  Created by George Nachman on 8/28/16.
//
//

#import "iTermImage+image_decoder.h"
#import <apr-1/apr_base64.h>

@interface NSData(ImageDecoder)
@end

@implementation NSData(ImageDecoder)

// Get rid of this and use base64EncodedDataWithOptions when 10.8 support is dropped.
- (NSString *)imageDecoder_base64String {
    // Subtract because the result includes the trailing null. Take MAX in case it returns 0 for
    // some reason.
    int length = MAX(0, apr_base64_encode_len((int)self.length) - 1);
    NSMutableData *buffer = [NSMutableData dataWithLength:length];
    if (buffer) {
        apr_base64_encode_binary(buffer.mutableBytes,
                                 self.bytes,
                                 (int)self.length);
    }
    return [[NSString alloc] initWithData:buffer encoding:NSUTF8StringEncoding];
}

@end

@implementation iTermImage

- (instancetype)init {
    self = [super init];
    if (self) {
        _delays = [NSMutableArray array];
        _images = [NSMutableArray array];
    }
    return self;
}

- (CGContextRef)newBitmapContextWithStorage:(NSMutableData *)data {
    NSSize size = self.size;
    NSInteger bytesPerRow = size.width * 4;
    NSUInteger storageNeeded = bytesPerRow * size.height;
    [data setLength:storageNeeded];

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate((void *)data.bytes,
                                                 size.width,
                                                 size.height,
                                                 8,
                                                 bytesPerRow,
                                                 colorSpace,
                                                 (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);
    if (!context) {
        return NULL;
    }

    return context;
}

- (NSData *)dataForImage:(NSImage *)image {
    NSMutableData *storage = [NSMutableData data];
    CGContextRef context = [self newBitmapContextWithStorage:storage];
    CGContextDrawImage(context, NSMakeRect(0, 0, self.size.width, self.size.height),
                       [image CGImageForProposedRect:NULL context:nil hints:nil]);
    CGContextRelease(context);
    return storage;
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [coder encodeObject:self.delays forKey:@"delays"];
    [coder encodeSize:self.size forKey:@"size"];
    NSMutableArray<NSData *> *imageDatas = [NSMutableArray new];
    for (NSImage *image in self.images) {
        NSData *imageData = [self dataForImage:image];
        [imageDatas addObject:imageData];
    }
    [coder encodeObject:imageDatas forKey:@"images"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    // This process will not have to decode any images.
    return nil;
}

@end
