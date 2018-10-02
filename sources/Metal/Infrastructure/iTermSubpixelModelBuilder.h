//
//  iTermSubpixelModelBuilder.h
//  subpixel
//
//  Created by George Nachman on 10/16/17.
//  Copyright © 2017 George Nachman. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <simd/simd.h>

NS_CLASS_DEPRECATED_MAC(10_12, 10_14)
@interface iTermSubpixelModel : NSObject

// The table contains 256 values that map a reference value to a color value in this channel.
@property (nonatomic, readonly) NSData *table;
@property (nonatomic, readonly) float foregroundColor;
@property (nonatomic, readonly) float backgroundColor;

+ (NSUInteger)keyForForegroundColor:(float)foregroundColor
                    backgroundColor:(float)backgroundColor;

- (NSUInteger)key;
- (NSString *)dump;

@end

// Builds and keeps a cache of built models that map colors in a black-on-white reference glyph
// to the colors used in a glyph with an arbitrary foreground and background color. Thanks to this
// mapping, we only need black-on-white textures with subpixel antialiasing and the GPU can color
// them in the fragment shader.
NS_CLASS_DEPRECATED_MAC(10_12, 10_14)
@interface iTermSubpixelModelBuilder : NSObject

+ (instancetype)sharedInstance;

- (iTermSubpixelModel *)modelForForegroundColor:(float)foregroundComponent
                                backgroundColor:(float)backgroundComponent;

- (void)writeDebugDataToFolder:(NSString *)folder
               foregroundColor:(float)foregroundComponent
               backgroundColor:(float)backgroundComponent;

@end
