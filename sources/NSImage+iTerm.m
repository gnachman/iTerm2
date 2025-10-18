//
//  NSImage+iTerm.m
//  iTerm
//
//  Created by George Nachman on 7/20/14.
//
//

#import "NSAppearance+iTerm.h"
#import "SFSymbolEnum/SFSymbolEnum.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSObject+iTerm.h"
#import "iTermPresentationController.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation NSImage (iTerm)

+ (NSImage *)it_imageForColorSwatch:(NSColor *)color size:(NSSize)size {
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];

    // Determine border color: black in light mode, white in dark mode.
    NSAppearance *appearance = [NSApp effectiveAppearance];
    NSString *match = [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    NSColor *borderColor = [match isEqualToString:NSAppearanceNameDarkAqua] ? [NSColor whiteColor] : [NSColor blackColor];

    // Use white fill if color is nil.
    NSColor *fillColor = color ? color : [NSColor whiteColor];
    NSRect rect = NSMakeRect(0, 0, size.width, size.height);

    // Fill the rectangle.
    [fillColor setFill];
    NSRectFill(rect);

    // Draw the border.
    [borderColor setStroke];
    NSBezierPath *borderPath = [NSBezierPath bezierPathWithRect:NSInsetRect(rect, 0.5, 0.5)];
    [borderPath stroke];

    // If color is nil, draw a diagonal slash.
    if (!color) {
        NSBezierPath *slashPath = [NSBezierPath bezierPath];
        [slashPath moveToPoint:NSMakePoint(0, 0)];
        [slashPath lineToPoint:NSMakePoint(size.width, size.height)];
        [slashPath stroke];
    }

    [image unlockFocus];
    return image;
}

// When you draw an image into an image context, you get a mystery scale that
// isn't necessarily the scale of NSScreen.main.
// That assumption is made elsewhere in this file and I probably need to fix
// it.
+ (CGFloat)systemScale {
    NSImage *image = [NSImage imageOfSize:NSMakeSize(1, 1) drawBlock:^{}];
    NSBitmapImageRep *rep = [image it_bitmapImageRep];
    return rep.size.width;
}

+ (NSSize)pointSizeOfGeneratedImageWithPixelSize:(NSSize)pixelSize {
    // This might make a 1x or a 2x bitmap depending on ✨something secret✨
    NSImage *test = [NSImage imageOfSize:NSMakeSize(1, 1) drawBlock:^{
        [[NSColor blackColor] set];
        NSRectFill(NSMakeRect(0, 0, 1, 1));
    }];

    CGFloat scale = 1;
    for (NSImageRep *rep in test.representations) {
        scale = MAX(scale, rep.pixelsWide);
    }

    NSSize pointSize = {
        .width = pixelSize.width / scale,
        .height = pixelSize.height / scale
    };
    DLog(@"Pixel size %@ -> point size %@ because %@", NSStringFromSize(pixelSize),
         NSStringFromSize(pointSize),
         test);
    return pointSize;
}

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
    [image it_drawFlipped:NO withBlock:block];
    return image;
}

+ (instancetype)flippedImageOfSize:(NSSize)size drawBlock:(void (^ NS_NOESCAPE)(void))block {
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image it_drawFlipped:YES withBlock:block];
    return image;
}

- (void)it_drawWithBlock:(void (^)(void))block {
    [self it_drawFlipped:NO withBlock:block];
}

- (void)it_drawFlipped:(BOOL)flipped withBlock:(void (^)(void))block {
    if (self.size.width == 0 || self.size.height == 0) {
        return;
    }
    [self lockFocusFlipped:flipped];

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
                      scaledSize:(NSSize)scaledSize
                   bitsPerSample:(NSInteger)bitsPerSample
                 samplesPerPixel:(NSInteger)samplesPerPixel
                     bytesPerRow:(NSInteger)bytesPerRow
                        hasAlpha:(BOOL)hasAlpha
                  colorSpaceName:(NSString *)colorSpaceName {
    if (samplesPerPixel == 1) {
        return [self imageWithRawData:[self dataWithFourBytesPerPixelFromDataWithOneBytePerPixel:data]
                                 size:size
                           scaledSize:scaledSize
                        bitsPerSample:8
                      samplesPerPixel:4
                             hasAlpha:YES
                       colorSpaceName:colorSpaceName];
    }

    assert(data.length == bytesPerRow * size.height);
    NSBitmapImageRep *bitmapImageRep =
        [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nil  // allocate the pixel buffer for us
                                                pixelsWide:size.width
                                                pixelsHigh:size.height
                                             bitsPerSample:bitsPerSample
                                           samplesPerPixel:samplesPerPixel
                                                  hasAlpha:hasAlpha
                                                  isPlanar:NO
                                            colorSpaceName:colorSpaceName
                                               bytesPerRow:bytesPerRow
                                              bitsPerPixel:bitsPerSample * samplesPerPixel];  // 0 means OS infers it

    memmove([bitmapImageRep bitmapData], data.bytes, data.length);

    NSImage *theImage = [[NSImage alloc] initWithSize:scaledSize];
    [theImage addRepresentation:bitmapImageRep];

    return theImage;
}

+ (instancetype)imageWithRawData:(NSData *)data
                            size:(NSSize)size
                      scaledSize:(NSSize)scaledSize
                   bitsPerSample:(NSInteger)bitsPerSample
                 samplesPerPixel:(NSInteger)samplesPerPixel
                        hasAlpha:(BOOL)hasAlpha
                  colorSpaceName:(NSString *)colorSpaceName {
    if (samplesPerPixel == 1) {
        return [self imageWithRawData:[self dataWithFourBytesPerPixelFromDataWithOneBytePerPixel:data]
                                 size:size
                           scaledSize:scaledSize
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

    NSImage *theImage = [[NSImage alloc] initWithSize:scaledSize];
    [theImage addRepresentation:bitmapImageRep];

    return theImage;
}

+ (NSString *)extensionForUniformType:(NSString *)type {
    NSDictionary *map = @{ UTTypeBMP.identifier: @"bmp",
                           UTTypeGIF.identifier: @"gif",
                           UTTypeJPEG.identifier: @"jpeg",
                           UTTypePNG.identifier: @"png",
                           UTTypeTIFF.identifier: @"tiff",
                           UTTypeICO.identifier: @"ico" };
    return map[type];
}

+ (NSImage *)it_imageForSymbolName:(NSString *)name accessibilityDescription:(NSString *)accessibilityDescription NS_AVAILABLE_MAC(10_16) {
    return [NSImage imageWithSystemSymbolName:name accessibilityDescription:accessibilityDescription];
}

+ (NSImage *)it_imageForSymbolName:(NSString *)name accessibilityDescription:(NSString *)description fallbackImageName:(NSString *)fallbackImageName forClass:(Class)theClass {
    if (@available(macOS 11, *)) {
        return [NSImage imageWithSystemSymbolName:name accessibilityDescription:description];
    }
    return [NSImage it_imageNamed:fallbackImageName forClass:theClass];
}

+ (NSImage *)it_hamburgerForClass:(Class)theClass {
    if (@available(macOS 10.16, *)) {
        return [self it_imageForSymbolName:SFSymbolGetString(SFSymbolEllipsisCircle) accessibilityDescription:@"Menu"];
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

- (NSImage *)safelyResizedImageWithSize:(NSSize)unsafeSize
                        destinationRect:(NSRect)destinationRect
                                  scale:(CGFloat)scale {
    DLog(@"safelyResizedImageWithSize:%@ destinationRect:%@ scale:%@",
         NSStringFromSize(unsafeSize), NSStringFromRect(destinationRect), @(scale));
    NSSize newSize = NSMakeSize(round(unsafeSize.width) * scale, round(unsafeSize.height) * scale);
    if (!self.isValid) {
        DLog(@"Invalid");
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
    DLog(@"rep=%@", rep);
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    const NSRect scaledDestinationRect = NSMakeRect(NSMinX(destinationRect) * scale,
                                                    NSMinY(destinationRect) * scale,
                                                    NSWidth(destinationRect) * scale,
                                                    NSHeight(destinationRect) * scale);
    DLog(@"scaledDestinationRect=%@", NSStringFromRect(scaledDestinationRect));
    [self drawInRect:scaledDestinationRect
            fromRect:NSZeroRect
           operation:NSCompositingOperationCopy
            fraction:1.0];
    [NSGraphicsContext restoreGraphicsState];

    NSImage *newImage = [[NSImage alloc] initWithSize:NSMakeSize(newSize.width / scale,
                                                                 newSize.height / scale)];
    [newImage addRepresentation:rep];
    DLog(@"newImage=%@", newImage);
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

- (NSSize)it_sizeInPointsForScale:(CGFloat)scaleFactor {
    NSBitmapImageRep *bitmapRep = [NSBitmapImageRep castFrom:[self bestRepresentationForScale:scaleFactor
                                                                                 mustBeBitmap:YES]];

    // If no bitmap representation exists, return the original image size
    if (!bitmapRep) {
        return self.size;
    }

    const NSInteger pixelWidth = bitmapRep.pixelsWide;
    const NSInteger pixelHeight = bitmapRep.pixelsHigh;

    NSSize sizeInPoints;
    sizeInPoints.width = pixelWidth / scaleFactor;
    sizeInPoints.height = pixelHeight / scaleFactor;

    return sizeInPoints;
}

- (NSBitmapImageRep *)bestBitmapRepresentationForScale:(CGFloat)desiredScale {
    return [NSBitmapImageRep castFrom:[self bestRepresentationForScale:desiredScale mustBeBitmap:YES]];
}

- (NSImageRep *)bestRepresentationForScale:(CGFloat)desiredScale mustBeBitmap:(BOOL)bitmap {
    NSImageRep *best = nil;
    double bestScale = 0;
    CGFloat width = self.size.width;
    if (width <= 0) {
        return nil;
    }
    for (NSImageRep *rep in self.representations) {
        if (bitmap && ![rep isKindOfClass:[NSBitmapImageRep class]]) {
            continue;
        }
        const double scale = best.pixelsWide / width;
        if (!best || fabs(desiredScale - scale) < fabs(desiredScale - bestScale)) {
            best = rep;
            bestScale = scale;
        }
    }
    return best;
}

- (NSImageRep *)bestRepresentationForScale:(CGFloat)desiredScale {
    return [self bestRepresentationForScale:desiredScale mustBeBitmap:NO];
}

- (NSImage *)it_imageWithTintColor:(NSColor *)tintColor size:(NSSize)size {
    if (!tintColor) {
        return self;
    }
    NSImage *image = [[NSImage alloc] initWithSize:size];
    NSBitmapImageRep *bitmapRep = [[NSBitmapImageRep alloc]
                                   initWithBitmapDataPlanes:NULL
                                                 pixelsWide:size.width
                                                 pixelsHigh:size.height
                                              bitsPerSample:8
                                            samplesPerPixel:4
                                                   hasAlpha:YES
                                                   isPlanar:NO
                                             colorSpaceName:NSCalibratedRGBColorSpace
                                               bitmapFormat:0
                                                bytesPerRow:0
                                               bitsPerPixel:32];

    [image addRepresentation:bitmapRep];
    [image it_drawWithBlock:^{
        const NSSize imageSize = [self size];
        if (imageSize.height == 0 || size.height == 0) {
            return;
        }
        const CGFloat imageAspect = imageSize.width / imageSize.height;
        const CGFloat targetAspect = size.width / size.height;
        NSRect drawRect = NSZeroRect;

        if (targetAspect > imageAspect) {
            // If the target is wider than the image's aspect, fit by height and center horizontally.
            CGFloat height = size.height;
            CGFloat width = height * imageAspect;
            CGFloat x = (size.width - width) / 2.0;
            drawRect = NSMakeRect(x, 0, width, height);
        } else {
            // Otherwise, fit by width and center vertically.
            CGFloat width = size.width;
            CGFloat height = width / imageAspect;
            CGFloat y = (size.height - height) / 2.0;
            drawRect = NSMakeRect(0, y, width, height);
        }

        [tintColor set];
        [self drawInRect:drawRect];
        NSRectFillUsingOperation(NSMakeRect(0, 0, size.width, size.height),
                                 NSCompositingOperationSourceIn);
    }];
    return image;
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
                                 NSCompositingOperationSourceIn);
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

+ (NSColorSpace *)colorSpaceForProgramaticallyGeneratedImages {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(1, 1)];
    [image lockFocus];
    [[NSColor blackColor] set];
    NSRectFill(NSMakeRect(0, 0, 1, 1));
    [image unlockFocus];
    return [image colorSpaceOfBestRepresentation];
}

- (CGFloat)scaleFactor {
    NSImageRep *rep = [self.representations maxWithBlock:^NSComparisonResult(NSImageRep *obj1, NSImageRep *obj2) {
        return [@(obj1.pixelsWide) compare:@(obj2.pixelsWide)];
    }];
    return (CGFloat)rep.pixelsWide / self.size.width;
}

+ (CGFloat)programaticallyCreatedImageScale {
    static CGFloat scale;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [iTermPresentationController sharedInstance];
        [[NSNotificationCenter defaultCenter] addObserverForName:iTermScreenParametersDidChangeNontrivally
                                                          object:nil
                                                           queue:nil
                                                      usingBlock:^(NSNotification * _Nonnull note) {
            scale = 0;
        }];
    });
    if (!scale) {
        DLog(@"Recompute scale");
        NSImage *image = [NSImage imageOfSize:NSMakeSize(1, 1) drawBlock:^{}];
        scale = [image scaleFactor];
    }
    DLog(@"Programatically created images have scale %f", scale);
    return scale;
}

- (NSImage *)it_imageScaledByX:(CGFloat)xScale y:(CGFloat)yScale {
    const NSSize size = self.size;
    if (size.width == 0 || size.height == 0) {
        return self;
    }
    DLog(@"Scale image by x=%f y=%f. Image=%@", xScale, yScale, self);
    CGFloat adjustment = 1;
    if ([self scaleFactor] == 1 && [NSImage programaticallyCreatedImageScale] > 1) {
        DLog(@"Use adjustment of 0.5 since we will create a 2x image");
        // We have no choice but to produce a 2x image from here. If the source is 1x, make the
        // returned image half the size in points so it'll be the same as the input image.
        adjustment = 0.5;
    }
    const NSSize destSize = NSMakeSize(self.size.width * fabs(xScale) * adjustment,
                                       self.size.height * fabs(yScale) * adjustment);
    DLog(@"Draw into destination fo size %@", NSStringFromSize(destSize));
    NSImage *image = [NSImage imageOfSize:destSize
                                drawBlock:^{
        NSAffineTransform *transform = [NSAffineTransform transform];

        [transform translateXBy:destSize.width / 2 yBy:destSize.height / 2];
        [transform scaleXBy:xScale yBy:yScale];
        [transform translateXBy:-destSize.width / 2 yBy:-destSize.height / 2];
        [transform concat];

        [self drawInRect:NSMakeRect(0, 0, destSize.width, destSize.height)];
    }];
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
                                                 0);
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

- (NSBitmapImageRep *)it_bitmapImageRep {
    CGImageRef cgImage = [[self bestRepresentationForScale:2] CGImageForProposedRect:nil context:nil hints:nil];
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
    return bitmap;
}

- (NSColorSpace *)colorSpaceOfBestRepresentation {
    CGImageRef cgImage = [[self bestRepresentationForScale:2] CGImageForProposedRect:nil context:nil hints:nil];
    CGColorSpaceRef cgColorSpace = CGImageGetColorSpace(cgImage);
    return [[NSColorSpace alloc] initWithCGColorSpace:cgColorSpace];
}

- (NSImage *)it_subimageWithRect:(NSRect)rect {
    const NSRect bounds = NSMakeRect(0, 0, self.size.width, self.size.height);
    NSImageRep *representation = [self bestRepresentationForRect:bounds
                                                         context:nil
                                                           hints:nil];

    return [NSImage imageWithSize:rect.size
                          flipped:NO
                   drawingHandler:^BOOL(NSRect destination) {
        BOOL ret = [representation drawInRect:destination
                                     fromRect:rect
                                    operation:NSCompositingOperationCopy
                                     fraction:1.0
                               respectFlipped:NO
                                        hints:nil];
        return ret;
    }];
}

@end

@implementation NSBitmapImageRep(iTerm)
- (NSBitmapImageRep *)it_bitmapScaledTo:(NSSize)size {
    const CGFloat scale = NSScreen.mainScreen.backingScaleFactor;
    NSSize points = size;
    points.width /= scale;
    points.height /= scale;
    NSImage *image = [[NSImage alloc] initWithSize:points];
    [image addRepresentation:self];
    return [[image it_imageOfSize:points] it_bitmapImageRep];
}

// Assumes premultiplied alpha and little endian. Floating point must be 16 bit.
- (MTLPixelFormat)metalPixelFormat {
    const MTLPixelFormat unsupportedFormatsMask = (NSBitmapFormatAlphaNonpremultiplied |
                                                   NSBitmapFormatSixteenBitBigEndian |
                                                   NSBitmapFormatThirtyTwoBitBigEndian |
                                                   NSBitmapFormatThirtyTwoBitLittleEndian |
                                                   NSBitmapFormatSixteenBitLittleEndian);  // Doesn't apply to 16-bit ints, not quite sure what this is for.
    if (self.bitmapFormat & unsupportedFormatsMask) {
        return MTLPixelFormatInvalid;
    }
    if (self.bitmapFormat & NSBitmapFormatFloatingPointSamples) {
        // Note that 16-bit floats don't have NSBitmapFormatSixteenBitLittleEndian set. That's only for ints.
        return MTLPixelFormatRGBA16Float;
    }
    const NSInteger bitsPerSample = self.bitsPerPixel / self.samplesPerPixel;
    if (bitsPerSample == 16) {
        return MTLPixelFormatRGBA16Unorm;
    }
    return MTLPixelFormatRGBA8Unorm;
}

- (NSBitmapImageRep *)it_bitmapWithAlphaLast {
    if (!(self.bitmapFormat & NSBitmapFormatAlphaFirst)) {
        return self;
    }
    const unsigned char *source = self.bitmapData;
    const NSUInteger samplesPerPixel = self.samplesPerPixel;
    const NSUInteger bytesPerSample = self.bitsPerSample / 8;
    const NSUInteger stride = samplesPerPixel * bytesPerSample;
    NSMutableData *storage = [NSMutableData dataWithLength:bytesPerSample * samplesPerPixel * self.pixelsWide * self.pixelsHigh];
    unsigned char *storageBase = (unsigned char *)storage.mutableBytes;
    for (NSUInteger i = 0; i < self.bytesPerRow * self.pixelsHigh; i += stride) {
        unsigned char *dest = storageBase + i;
        char temp[stride];
        memmove(temp, source + i, stride);
        // First, move the stuff that isn't alpha.
        const NSUInteger nonAlphaLength = (samplesPerPixel - 1) * bytesPerSample;
        memmove(dest,
                source + i + bytesPerSample,
                nonAlphaLength);
        // Now move alpha.
        memmove(dest + nonAlphaLength,
                source + i,
                bytesPerSample);
    }
    unsigned char *planes[1] = { storageBase };
    return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:planes
                                                   pixelsWide:self.pixelsWide
                                                   pixelsHigh:self.pixelsHigh
                                                bitsPerSample:self.bitsPerSample
                                              samplesPerPixel:self.samplesPerPixel
                                                     hasAlpha:YES
                                                     isPlanar:NO
                                               colorSpaceName:self.colorSpaceName
                                                 bitmapFormat:self.bitmapFormat & ~NSBitmapFormatAlphaFirst
                                                  bytesPerRow:self.bytesPerRow
                                                 bitsPerPixel:self.bitsPerPixel];
}
@end
