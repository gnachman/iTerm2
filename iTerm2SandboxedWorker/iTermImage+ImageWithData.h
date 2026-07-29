//
//  iTermImage+ImageWithData.h
//  iTerm2
//
//  Created by Benedek Kozma on 2020. 12. 23..
//

#import "iTermImage.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermImage(ImageWithData)

- (instancetype)initWithData:(NSData *)data;

// Repairs SVGs whose <use> elements reference ids nested inside a <g>
// in <defs>, which _NSSVGImageRep otherwise silently drops. Returns the
// input unchanged when it isn't SVG or needs no repair. Safe to call on
// untrusted data (pure NSXMLDocument transform, no rendering).
+ (NSData *)fixedSVGData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
