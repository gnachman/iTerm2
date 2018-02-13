//
//  iTermTexture.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/28/18.
//

#import "iTermTexture.h"
#import <objc/runtime.h>

const char *iTermTextureMetadataKey = "iTermTextureMetadataKey";

@implementation iTermTexture

+ (void)setBytesPerRow:(int)bytesPerRow rawDataSize:(int)size forTexture:(id<MTLTexture>)texture {
    [self attachMetadata:@{ @"bytesPerRow": @(bytesPerRow),
                            @"rawDataSize": @(size) }
               toTexture:texture];
}

+ (void)attachMetadata:(NSDictionary *)metadata toTexture:(id<MTLTexture>)texture {
    objc_setAssociatedObject(texture, iTermTextureMetadataKey, metadata, OBJC_ASSOCIATION_RETAIN);
}

+ (NSDictionary *)metadataForTexture:(id<MTLTexture>)texture {
    return objc_getAssociatedObject(texture, iTermTextureMetadataKey);
}

+ (int)bytesPerRowForForTexture:(id<MTLTexture>)texture {
    return [[[self metadataForTexture:texture] objectForKey:@"bytesPerRow"] intValue];
}

+ (int)rawDataSizeForTexture:(id<MTLTexture>)texture {
    return [[[self metadataForTexture:texture] objectForKey:@"rawDataSize"] intValue];
}

+ (void)setMetadataObject:(id)object forKey:(id)key onTexture:(id<MTLTexture>)texture {
    NSMutableDictionary *dict = [[self metadataForTexture:texture] mutableCopy] ?: [NSMutableDictionary dictionary];
    dict[key] = object;
    [self attachMetadata:dict toTexture:texture];
}

@end
