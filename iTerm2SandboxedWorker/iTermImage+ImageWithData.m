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
            return nil;
#endif
        }
    }
    return self;
}

@end
