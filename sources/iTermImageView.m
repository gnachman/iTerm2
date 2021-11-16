//
//  iTermImageView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/22/20.
//

#import "iTermImageView.h"

#import "iTermAlphaBlendingHelper.h"
#import "iTermMalloc.h"
#import "NSArray+iTerm.h"
#import "NSImage+iTerm.h"

#import <QuartzCore/QuartzCore.h>

@interface CALayer (CALayerAdditions)
@property(copy) NSString *contentsScaling;
@end

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

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p image=%@ hidden=%@ alpha=%@>",
            NSStringFromClass([self class]),
            self,
            self.image,
            @(self.isHidden),
            @(self.alphaValue)];
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

@implementation iTermInternalImageView {
    CGFloat _lastTilingScale;
}

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
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidChangeScreen:)
                                                     name:NSWindowDidChangeScreenNotification
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
    _lastTilingScale = -1;
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
    _lastTilingScale = -1;
}

- (CGFloat)scale {
    if (!self.window) {
        return 2;
    }
    return self.window.backingScaleFactor;
}

- (void)viewDidMoveToWindow {
    // The scale may have changed which affects tiled images.
    [self update];
}

- (void)windowDidChangeScreen:(NSNotification *)notification {
    // The scale may have changed which affects tiled images.
    [self update];
}

// Make a pattern color and set the layer's background color to that.
- (void)loadTiledImage {
    if (!_image.image) {
        self.layer.contents = nil;
        self.layer.backgroundColor = [[NSColor redColor] CGColor];
        return;
    }

    if (_lastTilingScale == self.scale) {
        return;
    }
    _lastTilingScale = self.scale;

    // This convoluted mess is because of crazy images like the one in issue 9582:
    //
    // <NSImage 0x60e000118580 Size={614.39999999999998, 345.59999999999997} RepProvider=<NSImageArrayRepProvider: 0x602000135730, reps:(
    //     "NSBitmapImageRep 0x60b000682160 Size={614.39999999999998, 345.59999999999997} ColorSpace=(not yet loaded) BPS=8 BPP=(not yet loaded) Pixels=2560x1440
    //      Alpha=NO Planar=NO Format=(not yet loaded) CurrentBacking=nil (faulting) CGImageSource=0x603000624c70"
    // )>>
    //
    // The NSImage API doesn't expose enough info to do anything sane with this.
    // Using the NSImage directly is a blurry mess.
    // Instead, we extract the CGImage from it—which is sane—and reconstruct two NSImages (one per scale)
    // and that does the "right" thing. The right thing I hereby define as 1 image pixel = 1 screen pixel.
    // That is right because it's convenient for the GPU renderer.
    // It's a little strange because the image will be visually twice as big on a 1x display as a retina display.
    NSImage *cookedImage = [_image tilingBackgroundImageForBackingScaleFactor:self.scale];
    CGColorRef cgcolor = [[NSColor colorWithPatternImage:cookedImage] CGColor];
    self.layer.backgroundColor = cgcolor;
    self.layer.contents = nil;
}

- (void)setContentMode:(iTermBackgroundImageMode)contentMode {
    if (contentMode == _contentMode) {
        return;
    }
    _contentMode = contentMode;
    [self update];
}

@end

