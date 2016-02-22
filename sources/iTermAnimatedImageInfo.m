//
//  iTermAnimatedImageInfo.m
//  iTerm2
//
//  Created by George Nachman on 5/11/15.
//
//

#import "iTermAnimatedImageInfo.h"

@implementation iTermAnimatedImageInfo {
    NSArray *_images;
    NSArray *_delays;
    NSTimeInterval _creationTime;
    NSTimeInterval _maxDelay;
}

- (instancetype)initWithData:(NSData *)data {
    if (!data) {
        // This happens in internal use when creating an image that we know isn't animated and no
        // data is provided. For example, the Broken Pipe image.
        return nil;
    }
    self = [super init];
    if (self) {
        NSMutableArray *images = [NSMutableArray array];
        NSMutableArray *delays = [NSMutableArray array];
        CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)data,
                                                              (CFDictionaryRef)@{});
        [(id)source autorelease];
        size_t const count = CGImageSourceGetCount(source);
        if (count <= 1) {
            return nil;
        }
        NSMutableArray *frameProperties = [NSMutableArray array];
        for (size_t i = 0; i < count; ++i) {
            NSDictionary *gifProperties = [self gifPropertiesForSource:source frame:i];
            if (!gifProperties) {
                // TIFF files may have multiple pages, so make sure it's an animated GIF.
                return nil;
            }
            [frameProperties addObject:gifProperties];
        }
        _maxDelay = 0;
        for (size_t i = 0; i < count; ++i) {
            CGImageRef imageRef = CGImageSourceCreateImageAtIndex(source, i, NULL);
            NSImage *image = [[[NSImage alloc] initWithCGImage:imageRef
                                                          size:NSMakeSize(CGImageGetWidth(imageRef),
                                                                          CGImageGetHeight(imageRef))] autorelease];
            [images addObject:image];
            CFRelease(imageRef);
            NSTimeInterval delay = [self delayInGifProperties:frameProperties[i]];
            _maxDelay += delay;
            [delays addObject:@(_maxDelay)];
        }
        _creationTime = [NSDate timeIntervalSinceReferenceDate];
        _images = [images retain];
        _delays = [delays retain];
    }
    return self;
}

- (void)dealloc {
    [_images release];
    [_delays release];
    [super dealloc];
}

- (int)currentFrame {
    NSTimeInterval offset = [NSDate timeIntervalSinceReferenceDate] - _creationTime;
    NSTimeInterval delay = fmod(offset, _maxDelay);
    for (int i = 0; i < _delays.count; i++) {
        if ([_delays[i] doubleValue] >= delay) {
            return i;
        }
    }
    return 0;
}

- (NSImage *)currentImage {
    return _images[self.currentFrame];
}

- (NSImage *)imageForFrame:(int)frame {
    return _images[frame];
}

- (NSDictionary *)gifPropertiesForSource:(CGImageSourceRef)source frame:(int)i {
    CFDictionaryRef const properties = CGImageSourceCopyPropertiesAtIndex(source, i, NULL);
    [(id)properties autorelease];
    if (properties) {
        CFDictionaryRef const gifProperties = CFDictionaryGetValue(properties,
                                                                   kCGImagePropertyGIFDictionary);
        return (NSDictionary *)gifProperties;
    } else {
        return nil;
    }
}

- (NSTimeInterval)delayInGifProperties:(NSDictionary *)gifProperties {
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

@end
