//
//  CPKScreenshot.m
//  ColorPicker
//
//  Created by George Nachman on 3/29/18.
//  Copyright © 2018 Google. All rights reserved.
//

#import "CPKScreenshot.h"

@implementation CPKScreenshot

+ (instancetype)grabFromScreen:(NSScreen *)screen colorSpace:(NSColorSpace *)colorSpace {
    NSDictionary *dict = screen.deviceDescription;
    CGDirectDisplayID displayId = [dict[@"NSScreenNumber"] unsignedIntValue];
    CGImageRef cgImage = CGDisplayCreateImage(displayId);

    NSSize size = screen.frame.size;
    size.width *= screen.backingScaleFactor;
    size.height *= screen.backingScaleFactor;

    // Capture in the display's native colorspace to avoid lossy conversion
    CGColorSpaceRef nativeColorSpaceRef = CGImageGetColorSpace(cgImage);
    NSColorSpace *nativeColorSpace = nil;
    if (nativeColorSpaceRef) {
        nativeColorSpace = [[NSColorSpace alloc] initWithCGColorSpace:nativeColorSpaceRef];
    }

    // Use the native colorspace if available, otherwise fall back to the requested one
    CPKScreenshot *screenshot = [CPKScreenshot screenshotFromCGImage:cgImage
                                                          colorSpace:nativeColorSpace ?: colorSpace ?: [NSColorSpace displayP3ColorSpace]];
    CFRelease(cgImage);

    return screenshot;
}

+ (instancetype)screenshotFromCGImage:(CGImageRef)inImage
                           colorSpace:(NSColorSpace *)nsColorSpace {
    CGColorSpaceRef colorSpace = nsColorSpace.CGColorSpace;
    if (colorSpace == NULL) {
        return nil;
    }

    // Create the bitmap context
    NSMutableData *storage = [NSMutableData data];
    CGContextRef cgctx = [self newBitmapContextForImage:inImage
                                             colorSpace:colorSpace
                                                storage:storage];
    if (cgctx == NULL) {
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
    result->_colorSpace = nsColorSpace;

    CGContextRelease(cgctx);

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
    CGContextRef context = CGBitmapContextCreate(storage.mutableBytes,
                                                 pixelsWide,
                                                 pixelsHigh,
                                                 8,      // bits per component
                                                 bitmapBytesPerRow,
                                                 colorSpace,
                                                 (CGBitmapInfo)kCGImageAlphaPremultipliedFirst);
    return context;
}

- (NSColor *)colorAtX:(NSInteger)x y:(NSInteger)y {
    unsigned char *b = (unsigned char *)_data.bytes;
    NSInteger offset = (x + y * (NSInteger)_size.width) * 4;
    if (offset < 0 || offset + 3 >= _data.length) {
        return nil;
    }
    CGFloat components[] = {
        b[offset + 1] / 255.0,
        b[offset + 2] / 255.0,
        b[offset + 3] / 255.0,
        b[offset + 0] / 255.0,
    };
    return [NSColor colorWithColorSpace:self.colorSpace
                             components:components
                                  count:4];
}

@end

