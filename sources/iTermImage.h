//
//  iTermImage.h
//  iTerm2
//
//  Created by George Nachman on 8/27/16.
//
//

#import <Cocoa/Cocoa.h>

@interface iTermImage : NSObject

// For animated gifs, delays is 1:1 with images. For non-animated images, delays is empty.
@property(nonatomic, readonly) NSMutableArray<NSNumber *> *delays;
@property(nonatomic, readonly) NSSize size;
@property(nonatomic, readonly) NSMutableArray<NSImage *> *images;

// Animated GIFs are not supported through this interface.
+ (instancetype)imageWithNativeImage:(NSImage *)image;

// Decompresses in a sandboxed process. Returns nil if anything goes wrong.
+ (instancetype)imageWithCompressedData:(NSData *)data;

@end
