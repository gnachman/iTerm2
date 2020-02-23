//
//  iTermImageView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/22/20.
//

#import "iTermImageView.h"

#import "iTermAlphaBlendingHelper.h"
#import "NSImage+iTerm.h"

#import <QuartzCore/QuartzCore.h>

@implementation iTermImageView

- (instancetype)init {
    self = [super init];
    if (self) {
        _contentMode = iTermBackgroundImageModeTile;
        self.layer = [[CALayer alloc] init];
        self.layer.contentsGravity = kCAGravityResizeAspectFill;
        self.wantsLayer = YES;
        self.layer.actions = @{@"backgroundColor": [NSNull null],
                               @"contents": [NSNull null],
                               @"contentsGravity": [NSNull null] };
    }
    return self;
}

- (void)setBlend:(CGFloat)blend {
    _blend = blend;
    [self updateAlpha];
}

- (void)setTransparency:(CGFloat)transparency {
    _transparency = transparency;
    [self updateAlpha];
}

- (CGFloat)desiredAlpha {
    return iTermAlphaValueForBottomView(_transparency, _blend);
}

- (void)updateAlpha {
    [super setAlphaValue:self.desiredAlpha];
}

- (void)setImage:(NSImage *)image {
    if (image == _image) {
        return;
    }
    _image = image;
    [self update];
}

- (void)setHidden:(BOOL)hidden {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    [super setHidden:hidden];

    [CATransaction commit];
}

- (void)update {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    [self reallyUpdate];

    [CATransaction commit];
}

- (void)reallyUpdate {
    switch (_contentMode) {
        case iTermBackgroundImageModeTile:
            [self loadTiledImage];
            self.layer.contentsGravity = kCAGravityResize;
            return;
            
        case iTermBackgroundImageModeStretch:
            [self loadRegularImage];
            self.layer.contentsGravity = kCAGravityResize;
            return;
            
        case iTermBackgroundImageModeScaleAspectFit:
            [self loadRegularImage];
            self.layer.contentsGravity = kCAGravityResizeAspect;
            self.layer.backgroundColor = self.backgroundColor.CGColor;
            return;
            
        case iTermBackgroundImageModeScaleAspectFill:
            [self loadRegularImage];
            self.layer.contentsGravity = kCAGravityResizeAspectFill;
            return;
    }
}

// Loads a non-tiled image.
- (void)loadRegularImage {
    CGFloat scale = self.window.backingScaleFactor ?: 2.0;
    self.layer.backgroundColor = nil;
    self.layer.contents = [_image layerContentsForContentsScale:[_image recommendedLayerContentsScale:scale]];
#warning TODO: What if you switch to a low dpi screen?
}

static void iTermImageViewDrawImage(void *info, CGContextRef context) {
    CGImageRef image = (CGImageRef)info;
    CGContextDrawImage(context,
                       CGRectMake(0,
                                  0,
                                  CGImageGetWidth(image),
                                  CGImageGetHeight(image)),
                       image);
}

static void iTermImageViewReleaseImage(void *info) {
    // The CGImage is autoreleased so this does nothing.
}

// Make a pattern color and set the layer's background color to that.
- (void)loadTiledImage {
    const CGImageRef cgImage = [_image CGImage];
    const int width = CGImageGetWidth(cgImage);
    const int height = CGImageGetHeight(cgImage);
    const CGPatternCallbacks callbacks = {
        .version = 0,
        .drawPattern = iTermImageViewDrawImage,
        .releaseInfo = iTermImageViewReleaseImage
    };
    CGPatternRef pattern = CGPatternCreate(cgImage,
                                           CGRectMake (0, 0, width, height),
                                           CGAffineTransformMake(1, 0, 0, 1, 0, 0),
                                           width,
                                           height,
                                           kCGPatternTilingConstantSpacing,
                                           YES /* isColored */,
                                           &callbacks);
    const CGColorSpaceRef colorSpace = CGColorSpaceCreatePattern(NULL);
    const CGFloat components[1] = { 1.0 };
    const CGColorRef color = CGColorCreateWithPattern(colorSpace, pattern, components);
    CGColorSpaceRelease(colorSpace);
    CGPatternRelease(pattern);
    self.layer.contents = nil;
    self.layer.backgroundColor = color;
    CGColorRelease(color);
}

- (void)setContentMode:(iTermBackgroundImageMode)contentMode {
    _contentMode = contentMode;
    [self update];
}

- (void)setBackgroundColor:(NSColor *)backgroundColor {
    _backgroundColor = backgroundColor;
    switch (self.contentMode) {
        case iTermBackgroundImageModeTile:
        case iTermBackgroundImageModeStretch:
        case iTermBackgroundImageModeScaleAspectFill:
            return;
            
        case iTermBackgroundImageModeScaleAspectFit:
            self.layer.backgroundColor = backgroundColor.CGColor;
            return;
    }
}

@end
