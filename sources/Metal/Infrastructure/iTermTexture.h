//
//  iTermTexture.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/28/18.
//

#import <Foundation/Foundation.h>
#import <MetalKit/MetalKit.h>

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermTexture : NSObject

+ (void)setBytesPerRow:(int)bytesPerRow
           rawDataSize:(int)size
       samplesPerPixel:(int)samplesPerPixel
            forTexture:(id<MTLTexture>)texture;

+ (int)samplesPerPixelForTexture:(id<MTLTexture>)texture;
+ (int)bytesPerRowForForTexture:(id<MTLTexture>)texture;
+ (int)rawDataSizeForTexture:(id<MTLTexture>)texture;
+ (NSDictionary *)metadataForTexture:(id<MTLTexture>)texture;
+ (void)setMetadataObject:(id)object forKey:(id)key onTexture:(id<MTLTexture>)texture;

@end
