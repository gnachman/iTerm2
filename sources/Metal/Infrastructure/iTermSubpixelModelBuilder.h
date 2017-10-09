//
//  iTermSubpixelModelBuilder.h
//  subpixel
//
//  Created by George Nachman on 10/16/17.
//  Copyright © 2017 George Nachman. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <simd/simd.h>

@interface iTermSubpixelModel : NSObject

// The table contains 256 RGBA values that map a reference value to a color value in this model.
// The gray value is a pixel in a non-subpixel-antialiased rendering, while the color value is
// the corresponding color in a subpixel-antialiased glyph in this model. Each combination of
// foreground and background color should have a separate model. Ignore the A, it's always 0.
// Each value is an unsigned short (2 bytes)
@property (nonatomic, readonly) NSData *table;
@property (nonatomic, readonly) vector_float4 foregroundColor;
@property (nonatomic, readonly) vector_float4 backgroundColor;

+ (NSUInteger)keyForForegroundColor:(vector_float4)foregroundColor
                    backgroundColor:(vector_float4)backgroundColor;

- (NSUInteger)key;
- (NSString *)dump;

@end

// Builds and keeps a cache of built models that map colors in a black-on-white reference glyph
// to the colors used in a glyph with an arbitrary foreground and background color. Thanks to this
// mapping, we only need black-on-white textures with subpixel antialiasing and the GPU can color
// them in the fragment shader. A color map is 768 bytes which is less memory than a single
// 5x12 pt retina glyph.
//
// Example usage:
// iTermSubpixelModel *model = [builder modelForForegroundColor:f backgroundColor:b];
// NSData *glyphBGRAData = [self drawGlyphForString:s];
//
// In practice, glyphBGRAData would be saved in a texture and the following code would run on the
// GPU, but it's presented as objective C for readability:
//
// for (int i = 0; i < glyphBGRAData.length; i += 4) {
//   glyphBGRAData.bytes[i] = model.redTable.bytes[glyphBGRAData.bytes[i]];
//   glyphBGRAData.bytes[i+1] = model.greenTable.bytes[glyphBGRAData.bytes[i+1]];
//   glyphBGRAData.bytes[i+2] = model.blueTable.bytes[glyphBGRAData.bytes[i+2]];
// }
@interface iTermSubpixelModelBuilder : NSObject

+ (instancetype)sharedInstance;

- (iTermSubpixelModel *)modelForForegoundColor:(vector_float4)foregroundColor
                               backgroundColor:(vector_float4)backgroundColor;

@end
