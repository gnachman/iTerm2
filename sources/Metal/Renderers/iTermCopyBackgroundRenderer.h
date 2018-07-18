//
//  iTermCopyBackgroundRenderer.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/4/17.
//

#import <Foundation/Foundation.h>
#import "iTermMetalRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermCopyRendererTransientState : iTermMetalRendererTransientState

// The texture to copy from.
@property (nonatomic, strong) id<MTLTexture> sourceTexture;

@end

// Copies from one texture to another.
@interface iTermCopyRenderer : NSObject<iTermMetalRenderer>

@property (nonatomic) BOOL enabled;

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface iTermCopyBackgroundRendererTransientState : iTermCopyRendererTransientState
@end

// The purpose of this renderer is to copy a texture to another texture. When
// there is a background image, diagonal broadcast input lines, a badge, or any
// other stuff that appears behind text that isn't a text background color,
// that makes subpixel antialiasing complicated and the text renderer needs to
// be able to sample its background color to decide what color to use. That
// necessitates drawing the composited background image, bars, badge, etc., to
// a texture because for some reason Metal doesn't let you sample from the
// texture you're drawing to.
@interface iTermCopyBackgroundRenderer : iTermCopyRenderer
@end

@interface iTermCopyOffscreenRendererTransientState : iTermCopyRendererTransientState
@end

@interface iTermCopyOffscreenRenderer : iTermCopyRenderer
@end

#if ENABLE_USE_TEMPORARY_TEXTURE
NS_CLASS_DEPRECATED_MAC(10_12, 10_14)
@interface iTermCopyToDrawableRendererTransientState : iTermCopyRendererTransientState
@end

NS_CLASS_DEPRECATED_MAC(10_12, 10_14)
@interface iTermCopyToDrawableRenderer : iTermCopyRenderer
@end
#endif

NS_CLASS_AVAILABLE_MAC(10_14)
@interface iTermPremultiplyAlphaRendererTransientState : iTermCopyRendererTransientState
@end

NS_CLASS_AVAILABLE_MAC(10_14)
@interface iTermPremultiplyAlphaRenderer : iTermCopyRenderer
@end

NS_ASSUME_NONNULL_END
