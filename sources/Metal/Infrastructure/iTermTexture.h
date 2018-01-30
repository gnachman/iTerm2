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

+ (void)setBytesPerRow:(int)bytesPerRow rawDataSize:(int)size forTexture:(id<MTLTexture>)texture;
+ (int)bytesPerRowForForTexture:(id<MTLTexture>)texture;
+ (int)rawDataSizeForTexture:(id<MTLTexture>)texture;
+ (NSDictionary *)metadataForTexture:(id<MTLTexture>)texture;

@end
