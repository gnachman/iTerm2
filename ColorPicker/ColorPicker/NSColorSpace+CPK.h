//
//  NSColorSpace+CPK.h
//  ColorPicker
//
//  Created by George Nachman on 12/15/21.
//  Copyright © 2021 Google. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSColorSpace(CPK)
- (NSString *)cpk_shortLocalizedName;

/**
 * Maps a colorspace to one of the three supported colorspaces (P3, sRGB, or Device).
 * Returns the closest supported colorspace.
 */
+ (NSColorSpace *)cpk_supportedColorSpaceForColorSpace:(NSColorSpace *)colorSpace;
@end

NS_ASSUME_NONNULL_END
