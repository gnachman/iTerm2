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

#import "iTermSerializableImage.h"

@implementation iTermSerializableImage

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

- (NSArray<NSString *> *)imageStringArray {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (NSImage *image in self.images) {
        NSData *data = [self dataForImage:image];
        NSString *encoded = [[NSString alloc] initWithData:[data base64EncodedDataWithOptions:0] encoding:NSUTF8StringEncoding];
        if (encoded) {
            [result addObject:encoded];
        }
    }
    return result;
}

- (NSDictionary *)dictionaryValue {
    return @{ @"delays": self.delays,
              @"size": @[ @(self.size.width), @(self.size.height) ],
              @"images": [self imageStringArray] };
}

- (NSData *)jsonValue {
    return [NSJSONSerialization dataWithJSONObject:[self dictionaryValue]
                                           options:0
                                             error:nil];
}

@end
