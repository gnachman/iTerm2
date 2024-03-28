//
//  NSImage+iTerm.h
//  iTerm
//
//  Created by George Nachman on 7/20/14.
//
//

#import <Cocoa/Cocoa.h>

@interface NSImage (iTerm)
+ (NSSize)pointSizeOfGeneratedImageWithPixelSize:(NSSize)pixelSize;
- (CGImageRef)CGImage;
+ (NSImage *)imageOfSize:(NSSize)size color:(NSColor *)color;
+ (NSColorSpace *)colorSpaceForProgramaticallyGeneratedImages;

// Creates an image context and runs block. Do drawing into the current
// graphics context in the block. Returns the resulting image.
+ (instancetype)imageOfSize:(NSSize)size drawBlock:(void (^ NS_NOESCAPE)(void))block;
+ (instancetype)flippedImageOfSize:(NSSize)size drawBlock:(void (^ NS_NOESCAPE)(void))block;

+ (instancetype)imageWithRawData:(NSData *)data
                            size:(NSSize)size
                   bitsPerSample:(NSInteger)bitsPerSample  // e.g. 8 or 1
                 samplesPerPixel:(NSInteger)samplesPerPixel  // e.g. 4 (RGBA) or 1
                        hasAlpha:(BOOL)hasAlpha
                  colorSpaceName:(NSString *)colorSpaceName;  // e.g., NSCalibratedRGBColorSpace

// Load a file and create a low DPI version by downscaling it and use the file itself as the
// high DPI representation.
+ (NSImage *)it_imageWithScaledBitmapFromFile:(NSString *)file pointSize:(NSSize)pointSize;

// Returns "gif", "png", etc., or nil.
+ (NSString *)extensionForUniformType:(NSString *)type;

+ (NSImage *)it_imageForSymbolName:(NSString *)name accessibilityDescription:(NSString *)description NS_AVAILABLE_MAC(10_16);
+ (NSImage *)it_hamburgerForClass:(Class)theClass;
+ (instancetype)it_imageNamed:(NSImageName)name forClass:(Class)theClass;
+ (instancetype)it_cacheableImageNamed:(NSImageName)name forClass:(Class)theClass;

// Returns an image blurred by repeated box blurs with |radius| iterations.
- (NSImage *)blurredImageWithRadius:(int)radius;

// Recolor the image with the given color but preserve its alpha channel.
- (NSImage *)imageWithColor:(NSColor *)color;

- (NSImage *)grayscaleImage;

// e.g., NSBitmapImageFileTypePNG
- (NSData *)dataForFileOfType:(NSBitmapImageFileType)fileType;

- (NSData *)rawPixelsInRGBColorSpace;

// Resizes an image in a way that lets you use rawDataForMetal. If you resize an image with only
// Cocoa APIs (lockFocus, drawInRect, unlockFocus), it won't work with 8 bits per component (only
// 16). So this uses CG APIs which produce a non-broken image. This creates an image with a single
// bitmap representation at the requested scale.
- (NSImage *)safelyResizedImageWithSize:(NSSize)newSize
                        destinationRect:(NSRect)destinationRect
                                  scale:(CGFloat)scale;

- (NSBitmapImageRep *)bitmapImageRep;  // prefer it_bitmapImageRep
- (NSBitmapImageRep *)it_bitmapImageRep;  // This is a cleaner method than -bitmapImageRep which won't change the pixel format.
- (NSImageRep *)bestRepresentationForScale:(CGFloat)scale;
- (void)saveAsPNGTo:(NSString *)filename;

- (NSImage *)it_imageWithTintColor:(NSColor *)tintColor;
- (NSImage *)it_imageWithTintColor:(NSColor *)tintColor size:(NSSize)size;
- (NSImage *)it_cachingImageWithTintColor:(NSColor *)tintColor key:(const void *)key;
- (NSImage *)it_verticallyFlippedImage;
- (NSImage *)it_horizontallyFlippedImage;
- (NSImage *)it_imageOfSize:(NSSize)size;

// Returns an image of size `size`, with the receiver zoomed and cropped so it at least fills the
// resulting image.
- (NSImage *)it_imageFillingSize:(NSSize)size;

- (NSImage *)it_subimageWithRect:(NSRect)rect;

@end

@interface NSBitmapImageRep(iTerm)
- (NSBitmapImageRep *)it_bitmapScaledTo:(NSSize)size;
// Assumes premultiplied alpha and little endian. Floating point must be 16 bit.
- (MTLPixelFormat)metalPixelFormat;
- (NSBitmapImageRep *)it_bitmapWithAlphaLast;

@end

