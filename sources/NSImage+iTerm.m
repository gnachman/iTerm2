//
//  NSImage+iTerm.m
//  iTerm
//
//  Created by George Nachman on 7/20/14.
//
//

#import "NSAppearance+iTerm.h"

#import "DebugLogging.h"
#import "NSColor+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSObject+iTerm.h"

#ifndef MAC_OS_X_VERSION_10_16
@interface NSImage(ImageFuture)
+ (NSImage *)imageWithSystemSymbolName:(NSString *)name accessibilityDescription:(NSString *)accessibilityDescription NS_AVAILABLE_MAC(10_16);
@end
#endif

@implementation NSImage (iTerm)

- (NSImage *)it_imageFillingSize:(NSSize)size {
    const CGFloat imageAspectRatio = self.size.width / self.size.height;
    const CGFloat containerAspectRatio = size.width / size.height;
    NSRect sourceRect;
    if (imageAspectRatio < containerAspectRatio) {
        // image is taller than container.
        sourceRect.origin.x = 0;
        sourceRect.size.width = self.size.width;
        sourceRect.size.height = self.size.width / containerAspectRatio;
        sourceRect.origin.y = (self.size.height - sourceRect.size.height) / 2.0;
    } else {
        // container is taller than image
        sourceRect.origin.y = 0;
        sourceRect.size.height = self.size.height;
        sourceRect.size.width = containerAspectRatio * self.size.height;
        sourceRect.origin.x = (self.size.width - sourceRect.size.width) / 2.0;
    }
    return [NSImage imageOfSize:size drawBlock:^{
        [self drawInRect:NSMakeRect(0, 0, size.width, size.height)
                fromRect:sourceRect
               operation:NSCompositingOperationCopy
                fraction:1];
    }];
}

+ (NSImage *)imageOfSize:(NSSize)size color:(NSColor *)color {
    return [self imageOfSize:size drawBlock:^{
        [color set];
        NSRectFill(NSMakeRect(0, 0, size.width, size.height));
    }];
}

+ (instancetype)imageOfSize:(NSSize)size drawBlock:(void (^ NS_NOESCAPE)(void))block {
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image it_drawWithBlock:block];
    return image;
}

- (void)it_drawWithBlock:(void (^)(void))block {
    if (self.size.width == 0 || self.size.height == 0) {
        return;
    }
    [self lockFocus];

    [NSAppearance it_performBlockWithCurrentAppearanceSetToAppearanceForCurrentTheme:^{
        block();
    }];

    [self unlockFocus];
}

+ (NSData *)dataWithFourBytesPerPixelFromDataWithOneBytePerPixel:(NSData *)input {
    NSMutableData *output = [NSMutableData dataWithLength:input.length * 4];
    unsigned char *ob = (unsigned char *)output.mutableBytes;
    unsigned char *ib = (unsigned char *)input.bytes;
    for (int i = 0; i < input.length; i++) {
        const int j = i * 4;
        ob[j + 0] = ib[i];
        ob[j + 1] = ib[i];
        ob[j + 2] = ib[i];
        ob[j + 3] = 255;
    }
    return output;
}

+ (instancetype)imageWithRawData:(NSData *)data
                            size:(NSSize)size
                   bitsPerSample:(NSInteger)bitsPerSample
                 samplesPerPixel:(NSInteger)samplesPerPixel
                        hasAlpha:(BOOL)hasAlpha
                  colorSpaceName:(NSString *)colorSpaceName {
    if (samplesPerPixel == 1) {
        return [self imageWithRawData:[self dataWithFourBytesPerPixelFromDataWithOneBytePerPixel:data]
                                 size:size
                        bitsPerSample:8
                      samplesPerPixel:4
                             hasAlpha:YES
                       colorSpaceName:colorSpaceName];
    }
    
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

+ (NSString *)extensionForUniformType:(NSString *)type {
    NSDictionary *map = @{ (NSString *)kUTTypeBMP: @"bmp",
                           (NSString *)kUTTypeGIF: @"gif",
                           (NSString *)kUTTypeJPEG2000: @"jp2",
                           (NSString *)kUTTypeJPEG: @"jpeg",
                           (NSString *)kUTTypePNG: @"png",
                           (NSString *)kUTTypeTIFF: @"tiff",
                           (NSString *)kUTTypeICO: @"ico" };
    return map[type];
}

+ (NSImage *)it_imageForSymbolName:(NSString *)name accessibilityDescription:(NSString *)accessibilityDescription NS_AVAILABLE_MAC(10_16) {
    return [NSImage imageWithSystemSymbolName:name accessibilityDescription:accessibilityDescription];
}

+ (NSImage *)it_hamburgerForClass:(Class)theClass {
    if (@available(macOS 10.16, *)) {
        return [self it_imageForSymbolName:@"ellipsis.circle" accessibilityDescription:@"Menu"];
    }
    return [NSImage it_imageNamed:@"Hamburger" forClass:theClass];
}

+ (instancetype)it_imageNamed:(NSImageName)name forClass:(Class)theClass {
    return [[NSBundle bundleForClass:theClass] imageForResource:name];
}

+ (instancetype)it_cacheableImageNamed:(NSImageName)name forClass:(Class)theClass {
    static NSMutableDictionary<NSString *, NSImage *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary dictionary];
    });
    NSString *key = [NSString stringWithFormat:@"%@\n%@", NSStringFromClass(theClass), name];
    NSImage *cached = cache[key];
    if (cached) {
        return cached;
    }
    NSImage *image = [self it_imageNamed:name forClass:theClass];
    cache[key] = image;
    return image;
}

- (NSImage *)blurredImageWithRadius:(int)radius {
    // Initially, this used a CIFilter but this doesn't work on some machines for mysterious reasons.
    // Instead, this algorithm implements a really simple box blur. It's quite fast--about 5ms on
    // a macbook pro with radius 5 for a 48x48 image.

    NSImage *image = self;
    NSSize size = self.size;
    NSRect frame = NSMakeRect(0, 0, size.width, size.height);
    for (int i = 0; i < radius; i++) {
        [image lockFocus];
        [self drawInRect:frame
                fromRect:frame
               operation:NSCompositingOperationSourceOver
                fraction:1];
        [image unlockFocus];
        image = [self onePixelBoxBlurOfImage:image alpha:1.0/9.0];
    }
    return image;
}

- (NSImage *)onePixelBoxBlurOfImage:(NSImage *)image alpha:(CGFloat)alpha {
    NSSize size = image.size;
    NSImage *destination = [[NSImage alloc] initWithSize:image.size];
    [destination lockFocus];
    for (int dx = -1; dx <= 1; dx++) {
        for (int dy = -1; dy <= 1; dy++) {
            [image drawInRect:NSMakeRect(dx,
                                         dy,
                                         size.width,
                                         size.height)
                     fromRect:NSMakeRect(0, 0, size.width, size.height)
                    operation:NSCompositingOperationSourceOver
                     fraction:alpha];
        }
    }
    [destination unlockFocus];
    return destination;
}

+ (CGContextRef)newBitmapContextOfSize:(NSSize)size storage:(NSMutableData *)data {
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

- (CGContextRef)newBitmapContextWithStorage:(NSMutableData *)data {
    NSSize size = self.size;
    return [NSImage newBitmapContextOfSize:size storage:data];
}

- (NSImage *)imageWithColor:(NSColor *)color {
    NSSize size = self.size;
    NSRect rect = NSZeroRect;
    rect.size = size;

    // Create a bitmap context.
    NSMutableData *data = [NSMutableData data];
    CGContextRef context = [self newBitmapContextWithStorage:data];

    // Draw myself into that context.
    CGContextDrawImage(context, rect, [self CGImageForProposedRect:NULL context:nil hints:nil]);

    // Now draw over it with |color|.
    CGContextSetFillColorWithColor(context, [color CGColor]);
    CGContextSetBlendMode(context, kCGBlendModeSourceAtop);
    CGContextFillRect(context, rect);

    // Extract the resulting image into the graphics context.
    CGImageRef image = CGBitmapContextCreateImage(context);

    // Convert to NSImage
    NSImage *coloredImage = [[NSImage alloc] initWithCGImage:image size:size];

    // Release memory.
    CGContextRelease(context);
    CGImageRelease(image);

    return coloredImage;
}

- (void)saveAsPNGTo:(NSString *)filename {
    [[self dataForFileOfType:NSBitmapImageFileTypePNG] writeToFile:filename atomically:NO];
}

// TODO: Should this use -bitmapImageRep?
- (NSData *)dataForFileOfType:(NSBitmapImageFileType)fileType {
    CGImageRef cgImage = [self CGImageForProposedRect:NULL
                                              context:nil
                                                hints:nil];
    NSBitmapImageRep *imageRep = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
    [imageRep setSize:self.size];
    return [imageRep representationUsingType:fileType properties:@{}];
}

- (NSData *)rawPixelsInRGBColorSpace {
    NSMutableData *storage = [NSMutableData data];
    CGContextRef context = [self newBitmapContextWithStorage:storage];
    CGContextDrawImage(context, NSMakeRect(0, 0, self.size.width, self.size.height),
                       [self CGImageForProposedRect:NULL context:nil hints:nil]);
    CGContextRelease(context);
    return storage;
}

- (NSData *)rawDataForMetalOfSize:(NSSize)unsafeSize {
    const NSSize size = NSMakeSize(round(unsafeSize.width), round(unsafeSize.height));

    CGImageRef cgImage = [self CGImageForProposedRect:nil context:nil hints:nil];

    size_t bitsPerComponent = 8;
    size_t bytesPerRow = size.width * bitsPerComponent * 4 / 8;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = (CGBitmapInfo)kCGImageAlphaPremultipliedLast | kCGBitmapByteOrderDefault;
    NSMutableData *data = [NSMutableData dataWithLength:bytesPerRow * ceil(size.height)];
    CGContextRef context = CGBitmapContextCreate(data.mutableBytes,
                                                 size.width,
                                                 size.height,
                                                 bitsPerComponent,
                                                 bytesPerRow,
                                                 colorSpace,
                                                 bitmapInfo);
    if (!context) {
        DLog(@"Failed to create bitmap context width=%@ height=%@ bpc=%@ bpr=%@ cs=%@",
             @(size.width), @(size.height), @(bitsPerComponent), @(bytesPerRow), colorSpace);
        return nil;
    }
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);

    // Flip the context so the positive Y axis points down
    CGContextTranslateCTM(context, 0, size.height);
    CGContextScaleCTM(context, 1, -1);

    CGContextDrawImage(context, CGRectMake(0, 0, size.width, size.height), cgImage);

    CFRelease(context);

    return data;

}

- (NSImage *)safelyResizedImageWithSize:(NSSize)unsafeSize destinationRect:(NSRect)destinationRect {
    NSSize newSize = NSMakeSize(round(unsafeSize.width), round(unsafeSize.height));
    const CGFloat scale = 1;
    if (!self.isValid) {
        return nil;
    }

    NSBitmapImageRep *rep =
      [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                              pixelsWide:newSize.width
                                              pixelsHigh:newSize.height
                                           bitsPerSample:8
                                         samplesPerPixel:4
                                                hasAlpha:YES
                                                isPlanar:NO
                                          colorSpaceName:NSCalibratedRGBColorSpace
                                             bytesPerRow:0
                                            bitsPerPixel:0];
    rep.size = newSize;

    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    [self drawInRect:destinationRect
            fromRect:NSZeroRect
           operation:NSCompositingOperationCopy
            fraction:1.0];
    [NSGraphicsContext restoreGraphicsState];

    NSImage *newImage = [[NSImage alloc] initWithSize:NSMakeSize(newSize.width / scale,
                                                                 newSize.height / scale)];
    [newImage addRepresentation:rep];
    return newImage;
}

- (NSBitmapImageRep *)bitmapImageRep {
    int width = [self size].width;
    int height = [self size].height;

    if (width < 1 || height < 1) {
        return nil;
    }

    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:width
                                                                    pixelsHigh:height
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:width * 4
                                                                  bitsPerPixel:32];

    NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep: rep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:ctx];
    [self drawAtPoint:NSZeroPoint
             fromRect:NSZeroRect
            operation:NSCompositingOperationCopy
             fraction:1.0];
    [ctx flushGraphics];
    [NSGraphicsContext restoreGraphicsState];

    return rep;
}

- (NSImageRep *)bestRepresentationForScale:(CGFloat)desiredScale {
    NSImageRep *best = nil;
    double bestScale = 0;
    CGFloat width = self.size.width;
    if (width <= 0) {
        return nil;
    }
    for (NSImageRep *rep in self.representations) {
        const double scale = best.pixelsWide / width;
        if (!best || fabs(desiredScale - scale) < fabs(desiredScale - bestScale)) {
            best = rep;
            bestScale = scale;
        }
    }
    return best;
}

- (NSImage *)it_imageWithTintColor:(NSColor *)tintColor {
    if (!tintColor) {
        return self;
    }
    NSSize size = self.size;
    NSImage *image = [self copy];
    image.template = NO;
    [image it_drawWithBlock:^{
        [tintColor set];
        NSRectFillUsingOperation(NSMakeRect(0, 0, size.width, size.height),
                                 NSCompositingOperationSourceAtop);
    }];
    return image;

}

- (NSImage *)it_cachingImageWithTintColor:(NSColor *)tintColor key:(const void *)key {
    NSImage *cached = [self it_associatedObjectForKey:key];
    if (cached) {
        return cached;
    }

    NSImage *image = [self it_imageWithTintColor:tintColor];
    [self it_setAssociatedObject:image forKey:key];
    return image;
}

- (NSImage *)it_verticallyFlippedImage {
    return [self it_imageScaledByX:1 y:-1];
}

- (NSImage *)it_horizontallyFlippedImage {
    return [self it_imageScaledByX:-1 y:1];
}

- (NSImage *)it_imageScaledByX:(CGFloat)xScale y:(CGFloat)yScale {
    const NSSize size = self.size;
    if (size.width == 0 || size.height == 0) {
        return self;
    }
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform scaleXBy:xScale yBy:yScale];
    NSAffineTransform *center = [NSAffineTransform transform];
    [center translateXBy:size.width / 2. yBy:size.height / 2.];
    [transform appendTransform:center];
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [transform concat];
    NSRect rect = NSMakeRect(0, 0, size.width, size.height);
    NSPoint corner = NSMakePoint(-size.width / 2., -size.height / 2.);
    [self drawAtPoint:corner fromRect:rect operation:NSCompositingOperationCopy fraction:1.0];
    [image unlockFocus];
    return image;
}

- (NSImage *)it_imageOfSize:(NSSize)newSize {
    if (!self.isValid) {
        return nil;
    }

    return [NSImage imageOfSize:newSize drawBlock:^{
        [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
        [self drawInRect:NSMakeRect(0, 0, newSize.width, newSize.height)
                fromRect:NSMakeRect(0, 0, self.size.width, self.size.height)
               operation:NSCompositingOperationCopy
                fraction:1];
    }];
}

static NSBitmapImageRep * iTermCreateBitmapRep(NSSize size,
                                               NSImage *sourceImage) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
              initWithBitmapDataPlanes:NULL
                            pixelsWide:size.width
                            pixelsHigh:size.height
                         bitsPerSample:8
                       samplesPerPixel:4
                              hasAlpha:YES
                              isPlanar:NO
                             colorSpaceName:sourceImage.bitmapImageRep.colorSpaceName
                           bytesPerRow:0
                          bitsPerPixel:0];
    rep.size = size;

    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    [sourceImage drawInRect:NSMakeRect(0, 0, size.width, size.height)
                   fromRect:NSZeroRect
                  operation:NSCompositingOperationCopy
                   fraction:1.0];
    [NSGraphicsContext restoreGraphicsState];

    return rep;
}

+ (NSImage *)it_imageWithScaledBitmapFromFile:(NSString *)file pointSize:(NSSize)pointSize {
    NSImage *sourceImage = [[NSImage alloc] initWithContentsOfFile:file];
    if (!sourceImage.isValid) {
        return nil;
    }
    NSBitmapImageRep *lowdpi = iTermCreateBitmapRep(pointSize, sourceImage);
    const NSSize retinaPixelSize = NSMakeSize(pointSize.width * 2,
                                              pointSize.height * 2);
    NSBitmapImageRep *hidpi = iTermCreateBitmapRep(retinaPixelSize, sourceImage);

    NSImage *image = [[NSImage alloc] initWithSize:pointSize];
    [image addRepresentation:lowdpi];
    [image addRepresentation:hidpi];
    return image;
}

- (CGImageRef)CGImage {
    return [self CGImageForProposedRect:nil context:nil hints:nil];
}

- (NSImage *)grayscaleImage {
    const NSSize size = self.size;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
    CGContextRef context = CGBitmapContextCreate(nil,
                                                 size.width,
                                                 size.height,
                                                 8,
                                                 0,
                                                 colorSpace,
                                                 kCGImageAlphaNone);
    const CGRect rect = CGRectMake(0,
                                   0,
                                   size.width,
                                   size.height);
    CGContextDrawImage(context, rect, self.CGImage);
    CGImageRef cgImage = CGBitmapContextCreateImage(context);

    NSImage *result = [[NSImage alloc] initWithCGImage:cgImage
                                                  size:size];

    CFRelease(cgImage);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);

    return result;
}

@end
