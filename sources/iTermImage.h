//
//  iTermImage.h
//  iTerm2
//
//  Created by George Nachman on 8/27/16.
//
//

#import <Cocoa/Cocoa.h>

#define DECODE_IMAGES_IN_PROCESS 0

#if defined(__has_feature)
#if __has_feature(address_sanitizer)
#undef DECODE_IMAGES_IN_PROCESS
#define DECODE_IMAGES_IN_PROCESS 1
#endif
#endif

@interface iTermImage : NSObject<NSSecureCoding>

// For animated gifs, delays is 1:1 with images. For non-animated images, delays is empty.
@property(nonatomic, readonly) NSMutableArray<NSNumber *> *delays;
@property(nonatomic, readonly) NSSize size;
@property(nonatomic, readonly) NSMutableArray<NSImage *> *images;

// Animated GIFs are not supported through this interface.
+ (instancetype)imageWithNativeImage:(NSImage *)image;

// Decompresses in a sandboxed process. Returns nil if anything goes wrong.
+ (instancetype)imageWithCompressedData:(NSData *)data;

// Assumes it begins with DCS parameters followed by newline.
// Decompresses in a sandboxed processes. Returns nil if anything goes wrong.
+ (instancetype)imageWithSixelData:(NSData *)sixelData;

@end
