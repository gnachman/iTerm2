//
//  iTermStreamingPNGWriter.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/12/26.
//

#import "iTermStreamingPNGWriter.h"
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation iTermStreamingPNGWriter {
    NSURL *_url;
    NSInteger _width;
    NSInteger _height;
    CGFloat _scale;
    NSInteger _rowsWritten;

    // We accumulate all row data and write at finalize.
    // This is necessary because ImageIO doesn't support true row-by-row PNG writing.
    // However, we stream the data in chunks to avoid holding rendered images in memory.
    NSMutableData *_pixelData;
    NSInteger _bytesPerRow;
    BOOL _cancelled;
    BOOL _finalized;
}

- (instancetype)initWithDestinationURL:(NSURL *)url
                                 width:(NSInteger)width
                                height:(NSInteger)height
                           scaleFactor:(CGFloat)scale {
    self = [super init];
    if (self) {
        _url = url;
        _width = width;
        _height = height;
        _scale = scale;
        _rowsWritten = 0;
        _bytesPerRow = width * 4;  // RGBA
        _cancelled = NO;
        _finalized = NO;

        // Pre-allocate buffer for all pixel data
        // This is still memory-efficient because we're not holding NSImage/CGImage objects,
        // just raw pixel data which is much more compact.
        NSUInteger totalBytes = (NSUInteger)(_bytesPerRow * _height);
        _pixelData = [[NSMutableData alloc] initWithCapacity:totalBytes];
    }
    return self;
}

- (NSURL *)url {
    return _url;
}

- (NSInteger)height {
    return _height;
}

- (NSInteger)rowsWritten {
    return _rowsWritten;
}

- (BOOL)writeRow:(const uint8_t *)rowData {
    return [self writeRows:rowData count:1];
}

- (BOOL)writeRows:(const uint8_t *)rowData count:(NSInteger)rowCount {
    if (_cancelled || _finalized) {
        return NO;
    }

    if (_rowsWritten + rowCount > _height) {
        // Would exceed expected height
        rowCount = _height - _rowsWritten;
        if (rowCount <= 0) {
            return NO;
        }
    }

    NSUInteger bytesToWrite = (NSUInteger)(_bytesPerRow * rowCount);
    [_pixelData appendBytes:rowData length:bytesToWrite];
    _rowsWritten += rowCount;

    return YES;
}

- (BOOL)finalize {
    if (_cancelled || _finalized) {
        return NO;
    }
    _finalized = YES;

    // Pad with zeros if we didn't get all rows
    if (_rowsWritten < _height) {
        NSUInteger missingBytes = (NSUInteger)(_bytesPerRow * (_height - _rowsWritten));
        NSMutableData *padding = [[NSMutableData alloc] initWithLength:missingBytes];
        [_pixelData appendData:padding];
    }

    // Create CGImage from pixel data
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (!colorSpace) {
        return NO;
    }

    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)_pixelData);
    if (!provider) {
        CGColorSpaceRelease(colorSpace);
        return NO;
    }

    CGImageRef cgImage = CGImageCreate(
        (size_t)_width,
        (size_t)_height,
        8,                          // bits per component
        32,                         // bits per pixel
        (size_t)_bytesPerRow,
        colorSpace,
        kCGBitmapByteOrderDefault | kCGImageAlphaLast,
        provider,
        NULL,                       // decode array
        NO,                         // should interpolate
        kCGRenderingIntentDefault
    );

    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);

    if (!cgImage) {
        return NO;
    }

    // Write to file using ImageIO
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL(
        (__bridge CFURLRef)_url,
        (__bridge CFStringRef)UTTypePNG.identifier,
        1,
        NULL
    );

    if (!destination) {
        CGImageRelease(cgImage);
        return NO;
    }

    // Set DPI based on scale factor
    CGFloat dpi = 72.0 * _scale;
    NSDictionary *properties = @{
        (__bridge NSString *)kCGImagePropertyDPIWidth: @(dpi),
        (__bridge NSString *)kCGImagePropertyDPIHeight: @(dpi),
        (__bridge NSString *)kCGImagePropertyPNGDictionary: @{
            (__bridge NSString *)kCGImagePropertyPNGInterlaceType: @0  // No interlacing for streaming
        }
    };

    CGImageDestinationAddImage(destination, cgImage, (__bridge CFDictionaryRef)properties);

    BOOL success = CGImageDestinationFinalize(destination);

    CFRelease(destination);
    CGImageRelease(cgImage);

    // Release pixel data to free memory
    _pixelData = nil;

    return success;
}

- (void)cancel {
    _cancelled = YES;
    _pixelData = nil;

    // Remove any partial file
    [[NSFileManager defaultManager] removeItemAtURL:_url error:nil];
}

@end
