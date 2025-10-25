//
//  NSImage+iTerm.h
//  iTerm
//
//  Created by George Nachman on 7/20/14.
//
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSImage (iTerm)
+ (NSSize)pointSizeOfGeneratedImageWithPixelSize:(NSSize)pixelSize;
- (CGImageRef)CGImage;
+ (NSImage *)imageOfSize:(NSSize)size color:(NSColor *)color;
+ (NSColorSpace * _Nullable)colorSpaceForProgramaticallyGeneratedImages;

+ (CGFloat)systemScale;

// Creates an image context and runs block. Do drawing into the current
// graphics context in the block. Returns the resulting image.
+ (instancetype)imageOfSize:(NSSize)size drawBlock:(void (^ NS_NOESCAPE)(void))block;
+ (instancetype)flippedImageOfSize:(NSSize)size drawBlock:(void (^ NS_NOESCAPE)(void))block;

+ (instancetype)imageWithRawData:(NSData *)data
                            size:(NSSize)size  // pixels
                      scaledSize:(NSSize)scaledSize  // image.size
                   bitsPerSample:(NSInteger)bitsPerSample  // e.g. 8 or 1
                 samplesPerPixel:(NSInteger)samplesPerPixel  // e.g. 4 (RGBA) or 1
                        hasAlpha:(BOOL)hasAlpha
                  colorSpaceName:(NSString *)colorSpaceName;  // e.g., NSCalibratedRGBColorSpace

+ (instancetype)imageWithRawData:(NSData *)data
                            size:(NSSize)size  // pixels
                      scaledSize:(NSSize)scaledSize  // image.size
                   bitsPerSample:(NSInteger)bitsPerSample
                 samplesPerPixel:(NSInteger)samplesPerPixel
                     bytesPerRow:(NSInteger)bytesPerRow
                        hasAlpha:(BOOL)hasAlpha
                  colorSpaceName:(NSString *)colorSpaceName;

// Load a file and create a low DPI version by downscaling it and use the file itself as the
// high DPI representation.
+ (NSImage * _Nullable)it_imageWithScaledBitmapFromFile:(NSString *)file pointSize:(NSSize)pointSize;

// Returns "gif", "png", etc., or nil.
+ (NSString * _Nullable)extensionForUniformType:(NSString *)type;

+ (NSImage * _Nullable)it_imageForSymbolName:(NSString *)name
                    accessibilityDescription:(NSString * _Nullable)description NS_AVAILABLE_MAC(10_16);
+ (NSImage * _Nullable)it_imageForSymbolName:(NSString *)name
                    accessibilityDescription:(NSString * _Nullable)description
                           fallbackImageName:(NSString *)fallbackImageName
                                    forClass:(Class)theClass;
+ (NSImage * _Nullable)it_hamburgerForClass:(Class)theClass;
+ (instancetype _Nullable)it_imageNamed:(NSImageName)name forClass:(Class)theClass;
+ (instancetype _Nullable)it_cacheableImageNamed:(NSImageName)name forClass:(Class)theClass;

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
- (NSImage * _Nullable)safelyResizedImageWithSize:(NSSize)newSize
                                  destinationRect:(NSRect)destinationRect
                                            scale:(CGFloat)scale;

- (NSBitmapImageRep * _Nullable)bitmapImageRep;  // prefer it_bitmapImageRep
- (NSBitmapImageRep *)it_bitmapImageRep;  // This is a cleaner method than -bitmapImageRep which won't change the pixel format.
- (NSImageRep * _Nullable)bestRepresentationForScale:(CGFloat)scale;
- (void)saveAsPNGTo:(NSString *)filename;

- (NSImage *)it_imageWithTintColor:(NSColor *)tintColor;
- (NSImage *)it_imageWithTintColor:(NSColor *)tintColor size:(NSSize)size;
- (NSImage *)it_cachingImageWithTintColor:(NSColor *)tintColor key:(const void *)key;
- (NSImage *)it_verticallyFlippedImage;
- (NSImage *)it_horizontallyFlippedImage;
- (NSImage * _Nullable)it_imageOfSize:(NSSize)size;
- (NSSize)it_sizeInPointsForScale:(CGFloat)scaleFactor;

// Returns an image of size `size`, with the receiver zoomed and cropped so it at least fills the
// resulting image.
- (NSImage *)it_imageFillingSize:(NSSize)size;

- (NSImage *)it_subimageWithRect:(NSRect)rect;
+ (NSImage *)it_imageForColorSwatch:(NSColor * _Nullable)color size:(NSSize)size;

@end

@interface NSBitmapImageRep(iTerm)
- (NSBitmapImageRep *)it_bitmapScaledTo:(NSSize)size;
// Assumes premultiplied alpha and little endian. Floating point must be 16 bit.
- (MTLPixelFormat)metalPixelFormat;
- (NSBitmapImageRep * _Nullable)it_bitmapWithAlphaLast;

@end

NS_ASSUME_NONNULL_END
