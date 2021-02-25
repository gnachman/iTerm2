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

// This is used with opaque windows to provide a background color under the image in case the
// image has transparent parts.
@interface iTermImageBackgroundColorView: NSView
@property (nonatomic, strong) NSColor *backgroundColor;
@end

@implementation iTermImageBackgroundColorView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
    }
    return self;
}

- (void)setBackgroundColor:(NSColor *)backgroundColor {
    _backgroundColor = backgroundColor;
    self.layer.backgroundColor = backgroundColor.CGColor;
}

@end

// This actually shows an image.
@interface iTermInternalImageView : NSView

@property (nonatomic, strong) iTermImageWrapper *image;
@property (nonatomic) iTermBackgroundImageMode contentMode;
@property (nonatomic) CGFloat blend;
@property (nonatomic) CGFloat transparency;

- (void)setAlphaValue:(CGFloat)alphaValue NS_UNAVAILABLE;

@end

@implementation iTermImageView {
    iTermInternalImageView *_lowerView;

    // This is used when the window is opaque. It provides a color behind the image in case the
    // image has transparent portions. When thew indow is transparent we hide it an let the
    // desktop show through.
    iTermImageBackgroundColorView *_backgroundColorView;
}

- (instancetype)init {
    self = [super initWithFrame:NSMakeRect(0, 0, 100, 100)];
    if (self) {
        self.autoresizesSubviews = YES;

        _backgroundColorView = [[iTermImageBackgroundColorView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        _backgroundColorView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self addSubview:_backgroundColorView];

        _lowerView = [[iTermInternalImageView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        _lowerView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self addSubview:_lowerView];
    }
    return self;
}

- (iTermImageWrapper *)image {
    return _lowerView.image;
}

- (void)setImage:(iTermImageWrapper *)image {
    _lowerView.image = image;
}

- (iTermBackgroundImageMode)contentMode {
    return _lowerView.contentMode;
}

- (void)setContentMode:(iTermBackgroundImageMode)contentMode {
    _lowerView.contentMode = contentMode;
}

- (void)setBackgroundColor:(NSColor *)backgroundColor {
    _backgroundColor = backgroundColor;
    _backgroundColorView.backgroundColor = backgroundColor;
}

- (CGFloat)blend {
    return _lowerView.blend;
}

- (void)setBlend:(CGFloat)blend {
    _lowerView.blend = blend;
}

- (CGFloat)transparency {
    return _lowerView.transparency;
}

- (void)setTransparency:(CGFloat)transparency {
    _lowerView.transparency = transparency;
}

@end

@implementation iTermInternalImageView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _contentMode = iTermBackgroundImageModeTile;
        self.layer = [[CALayer alloc] init];
        self.layer.contentsGravity = kCAGravityResizeAspectFill;
        self.wantsLayer = YES;
        self.layer.actions = @{@"backgroundColor": [NSNull null],
                               @"contents": [NSNull null],
                               @"contentsGravity": [NSNull null] };
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(fullScreenDidChange:)
                                                     name:NSWindowDidEnterFullScreenNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(fullScreenDidChange:)
                                                     name:NSWindowDidExitFullScreenNotification
                                                   object:nil];
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

- (BOOL)inFullScreenWindow {
    return (self.window.styleMask & NSWindowStyleMaskFullScreen) == NSWindowStyleMaskFullScreen;
}

- (CGFloat)desiredAlpha {
    if ([self inFullScreenWindow]) {
        // There is nothing behind this view in full screen so if it is not hidden it must be opaque.
        return 1;
    }
    return iTermAlphaValueForBottomView(_transparency, _blend);
}

- (void)fullScreenDidChange:(NSNotification *)notification {
    if (notification.object == self.window) {
        [self updateAlpha];
    }
}

- (void)updateAlpha {
    [self.superview setAlphaValue:self.desiredAlpha];
}

- (void)setImage:(iTermImageWrapper *)image {
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
            return;
            
        case iTermBackgroundImageModeScaleAspectFill:
            [self loadRegularImage];
            self.layer.contentsGravity = kCAGravityResizeAspectFill;
            return;
    }
}

// Loads a non-tiled image.
- (void)loadRegularImage {
    self.layer.backgroundColor = nil;
    CGImageRef cgi = [_image cgimage];
    self.layer.contents = (__bridge id)cgi;
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
    const CGImageRef cgImage = [_image.image CGImage];
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
    if (contentMode == _contentMode) {
        return;
    }
    _contentMode = contentMode;
    [self update];
}

@end

