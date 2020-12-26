//
//  iTermImage+SandboxedWorker.m
//  iTerm2SandboxedWorker
//
//  Created by Benedek Kozma on 2020. 12. 27..
//

#import "iTermImage+SandboxedWorker.h"

@implementation iTermImage

- (instancetype)initWithData:(NSData *)data {
    self = [super init];
    if (self) {
        _delays = [NSMutableArray new];
        _images = [NSMutableArray new];
        
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
        _size = imageSize;
        
        BOOL isGIF = NO;
        NSNumber *frameCount;
        NSBitmapImageRep *bitmapImageRep = (NSBitmapImageRep *)rep;
        if ([bitmapImageRep isKindOfClass:[NSBitmapImageRep class]]) {
            frameCount = [bitmapImageRep valueForProperty:NSImageFrameCount];
            if (frameCount.intValue > 1) {
                isGIF = YES;
            }
        } else {
            // Other types don't work in fully restricted sandbox.
            return nil;
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
                [_images addObject:frame];
                NSTimeInterval delay = [((NSNumber *)[bitmapImageRep valueForProperty:NSImageCurrentFrameDuration]) doubleValue];
                totalDelay += delay;
                [_delays addObject:@(totalDelay)];
            }
        } else {
            [_images addObject:image];
        }
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
    NSBitmapImageRep *rep = ((NSBitmapImageRep *)image.representations.firstObject);
    if (![rep isKindOfClass:[NSBitmapImageRep class]]) {
        NSLog(@"Only bitmap images should get to this point.");
        return storage;
    }
    CGContextRef context = [self newBitmapContextWithStorage:storage];
    CGImageRef imageToDraw = rep.CGImage;
    CGContextDrawImage(context, NSMakeRect(0, 0, self.size.width, self.size.height), imageToDraw);
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

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
    // This process will not have to decode any images.
    return nil;
}

@end
