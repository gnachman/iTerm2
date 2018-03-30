//
//  CPKScreenshot.m
//  ColorPicker
//
//  Created by George Nachman on 3/29/18.
//  Copyright © 2018 Google. All rights reserved.
//

#import "CPKScreenshot.h"

@implementation CPKScreenshot

+ (instancetype)grabFromScreen:(NSScreen *)screen {
    NSDictionary *dict = screen.deviceDescription;
    CGDirectDisplayID displayId = [dict[@"NSScreenNumber"] unsignedIntValue];
    CGImageRef cgImage = CGDisplayCreateImage(displayId);

    NSSize size = screen.frame.size;
    size.width *= screen.backingScaleFactor;
    size.height *= screen.backingScaleFactor;

    CPKScreenshot *screenshot = [CPKScreenshot screenshotFromCGImage:cgImage];
    CFRelease(cgImage);

    return screenshot;
}

+ (instancetype)screenshotFromCGImage:(CGImageRef)inImage; {
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    if (colorSpace == NULL) {
        return nil;
    }

    // Create the bitmap context
    NSMutableData *storage = [NSMutableData data];
    CGContextRef cgctx = [self newBitmapContextForImage:inImage
                                             colorSpace:colorSpace
                                                storage:storage];
    if (cgctx == NULL) {
        CGColorSpaceRelease(colorSpace);
        return nil;
    }

    CGRect rect = CGRectMake(0,
                             0,
                             CGImageGetWidth(inImage),
                             CGImageGetHeight(inImage));
    CGContextDrawImage(cgctx, rect, inImage);

    CPKScreenshot *result = [[CPKScreenshot alloc] init];
    result.data = [NSData dataWithBytes:CGBitmapContextGetData(cgctx)
                                 length:CGBitmapContextGetBytesPerRow(cgctx) * CGBitmapContextGetHeight(cgctx)];
    result.size = rect.size;

    CGContextRelease(cgctx);
    CGColorSpaceRelease(colorSpace);

    return result;
}

+ (CGContextRef)newBitmapContextForImage:(CGImageRef)inImage
                              colorSpace:(CGColorSpaceRef)colorSpace
                                 storage:(NSMutableData *)storage {
    const int pixelsWide = (int)CGImageGetWidth(inImage);
    const int pixelsHigh = (int)CGImageGetHeight(inImage);

    const int bitmapBytesPerRow = pixelsWide * 4;
    const int bitmapByteCount     = (bitmapBytesPerRow * pixelsHigh);

    storage.length = bitmapByteCount;
    CGContextRef context = CGBitmapContextCreate (storage.mutableBytes,
                                                  pixelsWide,
                                                  pixelsHigh,
                                                  8,      // bits per component
                                                  bitmapBytesPerRow,
                                                  colorSpace,
                                                  kCGImageAlphaPremultipliedFirst);
    return context;
}

- (NSColor *)colorAtX:(NSInteger)x y:(NSInteger)y {
    unsigned char *b = (unsigned char *)_data.bytes;
    b += y * (int)_size.width * 4;
    b += x * 4;
    return [NSColor colorWithSRGBRed:b[1] / 255.0
                               green:b[2] / 255.0
                                blue:b[3] / 255.0
                               alpha:b[0] / 255.0];
}

@end

