//
//  iTermImage+ImageWithData.m
//  iTerm2SandboxedWorker
//
//  Created by George Nachman on 12/26/20.
//

#import <Foundation/Foundation.h>
#import "iTermImage.h"
#import "iTermImage+Private.h"

@interface NSPDFImageRep(iTerm)
- (NSImage *)bitmapImageFromPDFOfSize:(NSSize)size;
@end

@implementation NSPDFImageRep(iTerm)

- (NSImage *)bitmapImageFromPDFOfSize:(NSSize)size {
    if (self.pageCount == 0) {
        return nil;
    }
    if (size.width <= 1 || size.height <= 1) {
        return nil;
    }
    [self setCurrentPage:0];
    NSBitmapImageRep *bitmapRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                          pixelsWide:size.width
                                                                          pixelsHigh:size.height
                                                                       bitsPerSample:8
                                                                     samplesPerPixel:4
                                                                            hasAlpha:YES
                                                                            isPlanar:NO
                                                                      colorSpaceName:NSCalibratedRGBColorSpace
                                                                         bytesPerRow:0
                                                                        bitsPerPixel:0];

    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmapRep];

    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:context];
    [[NSGraphicsContext currentContext] setShouldAntialias:YES];
    [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
    [[NSGraphicsContext currentContext] setColorRenderingIntent:NSColorRenderingIntentPerceptual];

    const NSRect target = NSMakeRect(0, 0, size.width, size.height);
    [self drawInRect:target];

    [NSGraphicsContext restoreGraphicsState];

    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image addRepresentation:bitmapRep];
    return image;
}

@end

@implementation iTermImage(ImageWithData)

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
        self.size = imageSize;

        BOOL isGIF = NO;
        NSNumber *frameCount;
        if ([rep isKindOfClass:[NSBitmapImageRep class]]) {
            NSBitmapImageRep *bitmapImageRep = (NSBitmapImageRep *)rep;
            frameCount = [bitmapImageRep valueForProperty:NSImageFrameCount];
            if (frameCount.intValue > 1) {
                isGIF = YES;
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
                    [self.images addObject:frame];
                    NSTimeInterval delay = [((NSNumber *)[bitmapImageRep valueForProperty:NSImageCurrentFrameDuration]) doubleValue];
                    totalDelay += delay;
                    [self.delays addObject:@(totalDelay)];
                }
            } else {
                [self.images addObject:image];
            }
        } else if ([rep isKindOfClass:[NSPDFImageRep class]]) {
            [self.images addObject:[(NSPDFImageRep *)rep bitmapImageFromPDFOfSize:self.size]];
        } else {
#if DECODE_IMAGES_IN_PROCESS
            [self.images addObject:image];
#else
            // SVG takes this path.
            NSImage *safeImage = [self renderedImageOfUnknownType:image data:data];
            if (safeImage) {
                self.size = safeImage.size;
                [self.images addObject:safeImage];
            } else {
                return nil;
            }
#endif
        }
    }
    return self;
}

- (NSImage *)renderedImageOfUnknownType:(NSImage *)unsafeImage data:(NSData *)data {
    NSSize size = unsafeImage.size;
    if (size.width <= 0 || size.height <= 0) {
        size = NSMakeSize(1024, 1024);
    }
    const CGFloat largest = MAX(size.width, size.height);
    const CGFloat maxSize = 4096;
    if (largest <= maxSize) {
        // Image size is reasonable.
        NSImage *dest = [[NSImage alloc] initWithSize:size];
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:[unsafeImage TIFFRepresentation]];
        if (!rep) {
            return nil;
        }
        [dest addRepresentation:rep];
        return dest;
    }

    // Image is really big so we must redraw it.
    const CGFloat overage = largest / maxSize;
    size = NSMakeSize(MAX(1.0, round(size.width / overage)),
                      MAX(1.0, round(size.height / overage)));


    NSBitmapImageRep *bitmapRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nil
                                                                          pixelsWide:size.width
                                                                          pixelsHigh:size.height
                                                                       bitsPerSample:8
                                                                     samplesPerPixel:4
                                                                            hasAlpha:YES
                                                                            isPlanar:NO
                                                                      colorSpaceName:NSCalibratedRGBColorSpace
                                                                         bytesPerRow:0
                                                                        bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmapRep]];
    [unsafeImage drawInRect:NSMakeRect(0, 0, size.width, size.height)];
    [NSGraphicsContext restoreGraphicsState];

    NSImage *dest = [[NSImage alloc] initWithSize:size];
    [dest addRepresentation:bitmapRep];
    return dest;
}

@end
