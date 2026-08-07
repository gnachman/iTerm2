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
#import "NSObject+iTerm.h"

#import <AVFoundation/AVFoundation.h>
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
        // This view ignores its alpha value sometimes unless it has a layer. Like setAlpha: is
        // flaky (it works if you do it after a spin of the runloop). I guess if you have a subviews
        // with layers and you want alpha to work you must yourself have a layer? I don't think I'll
        // ever understand layers on macOS and I will be forever grateful that I don't have to
        // maintain the spaghetti that must implement them.
        self.wantsLayer = YES;
        self.layer = [[CALayer alloc] init];
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

- (void)setAlphaValue:(CGFloat)alpha {
    [super setAlphaValue:alpha];
}

@end

@implementation iTermInternalImageView {
    CGFloat _lastTilingScale;

    // Set only while showing a video background. The player layer sits on top
    // of self.layer and inherits the superview's alpha, so blend and
    // transparency work the same as for still images. The player itself is
    // owned by the image wrapper and shared with other consumers; we hold a
    // playback interest on _playbackInterestImage while visible. That may
    // lag _image briefly during an image change, which is why it's tracked
    // separately: the release must go to the wrapper that was retained.
    AVPlayerLayer *_playerLayer;
    iTermImageWrapper *_playbackInterestImage;
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

- (void)dealloc {
    [_playbackInterestImage releaseVideoPlaybackInterest];
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
    [self updateVideoPlaybackState];
}

- (void)update {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    [self reallyUpdate];

    [CATransaction commit];
}

- (void)reallyUpdate {
    if (_image.isVideo) {
        [self loadVideo];
        return;
    }
    [self destroyVideoPlayer];
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

#pragma mark - Video

- (AVLayerVideoGravity)desiredVideoGravity {
    switch (_contentMode) {
        case iTermBackgroundImageModeStretch:
            return AVLayerVideoGravityResize;
        case iTermBackgroundImageModeScaleAspectFit:
            return AVLayerVideoGravityResizeAspect;
        case iTermBackgroundImageModeScaleAspectFill:
        case iTermBackgroundImageModeTile:
            // Tiling a video isn't supported; fill is the least surprising stand-in.
            return AVLayerVideoGravityResizeAspectFill;
    }
    return AVLayerVideoGravityResizeAspectFill;
}

- (void)loadVideo {
    self.layer.contents = nil;
    self.layer.backgroundColor = nil;
    _lastTilingScale = -1;

    if (_playerLayer && _playerLayer.player == _image.videoPlayer) {
        _playerLayer.videoGravity = [self desiredVideoGravity];
        return;
    }
    [self destroyVideoPlayer];

    _playerLayer = [AVPlayerLayer playerLayerWithPlayer:_image.videoPlayer];
    _playerLayer.videoGravity = [self desiredVideoGravity];
    _playerLayer.actions = @{ @"bounds": [NSNull null],
                              @"position": [NSNull null] };
    _playerLayer.frame = self.layer.bounds;
    [self.layer addSublayer:_playerLayer];

    [self updateVideoPlaybackState];
}

- (void)destroyVideoPlayer {
    [self setPlaybackInterestImage:nil];
    [_playerLayer removeFromSuperlayer];
    _playerLayer = nil;
}

- (void)setPlaybackInterestImage:(iTermImageWrapper *)image {
    if (image == _playbackInterestImage) {
        return;
    }
    [_playbackInterestImage releaseVideoPlaybackInterest];
    _playbackInterestImage = image;
    [_playbackInterestImage retainVideoPlaybackInterest];
}

// Decoding a video that nobody can see wastes power, so track visibility.
// SessionView toggles hidden on an ancestor, hence the OrHasHiddenAncestor
// check and the viewDidHide/viewDidUnhide overrides.
- (void)updateVideoPlaybackState {
    if (!_playerLayer) {
        return;
    }
    const BOOL visible = !self.isHiddenOrHasHiddenAncestor && self.window != nil;
    [self setPlaybackInterestImage:visible ? _image : nil];
}

- (void)viewDidHide {
    [super viewDidHide];
    [self updateVideoPlaybackState];
}

- (void)viewDidUnhide {
    [super viewDidUnhide];
    [self updateVideoPlaybackState];
}

- (void)layout {
    [super layout];
    if (_playerLayer) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _playerLayer.frame = self.layer.bounds;
        [CATransaction commit];
    }
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
    [self updateVideoPlaybackState];
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

