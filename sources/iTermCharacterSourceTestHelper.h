//
//  iTermCharacterSourceTestHelper.h
//  iTerm2
//
//  Created by George Nachman on 3/14/26.
//
//  Helper class to make iTermCharacterSource testable from Swift.
//

#import <Cocoa/Cocoa.h>

@class iTermCharacterSource;
@class iTermCharacterSourceDescriptor;
@class iTermCharacterSourceAttributes;
@class iTermFontTable;

NS_ASSUME_NONNULL_BEGIN

@interface iTermCharacterSourceTestHelper : NSObject

/// Creates a descriptor with default test values.
+ (iTermCharacterSourceDescriptor *)descriptorWithFontTable:(iTermFontTable *)fontTable
                                                      scale:(CGFloat)scale
                                                  glyphSize:(CGSize)glyphSize;

/// Creates attributes with default test values.
+ (iTermCharacterSourceAttributes *)defaultAttributes;

/// Creates attributes with specific bold/italic settings.
+ (iTermCharacterSourceAttributes *)attributesWithBold:(BOOL)bold italic:(BOOL)italic;

/// Creates a character source for testing.
+ (nullable iTermCharacterSource *)characterSourceWithCharacter:(NSString *)character
                                                     descriptor:(iTermCharacterSourceDescriptor *)descriptor
                                                     attributes:(iTermCharacterSourceAttributes *)attributes
                                                         radius:(int)radius
                                                        context:(CGContextRef)context;

/// Draws the character and returns the frame that was drawn.
/// Returns NSZeroRect if the character couldn't be drawn.
+ (NSRect)drawAndGetFrameForSource:(iTermCharacterSource *)source;

/// Draws the character, then checks if the context is properly cleared.
/// Returns YES if all pixels are zero (properly cleared), NO otherwise.
+ (BOOL)drawAndVerifyClearingForSource:(iTermCharacterSource *)source
                               context:(CGContextRef)context
                           contextSize:(CGSize)size;

/// Scans the context for any non-zero alpha pixels.
/// Returns YES if all pixels are zero, NO if any non-zero pixels found.
+ (BOOL)contextIsEmpty:(CGContextRef)context size:(CGSize)size;

/// Returns the bounding rect of non-zero alpha pixels in the context.
/// Returns NSZeroRect if no pixels are found.
+ (NSRect)pixelBoundsInContext:(CGContextRef)context size:(CGSize)size;

@end

NS_ASSUME_NONNULL_END
