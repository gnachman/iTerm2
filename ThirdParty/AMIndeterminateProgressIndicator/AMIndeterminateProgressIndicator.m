//
//  AMIndeterminateProgressIndicator.m
//
//  Created by Andreas on 23.01.07.
//  Copyright 2007 Andreas Mayer. All rights reserved.
//
// Updated to use a layer animation by George Nachman on 3/10/2016.

#import "AMIndeterminateProgressIndicator.h"
#import "NSImage+iTerm.h"
#import <QuartzCore/QuartzCore.h>

static CGFloat DegreesToRadians(double radians) {
    return radians / 180.0 * M_PI;
}

typedef struct {
    CGFloat outerRadius;
    CGFloat innerRadius;
    CGFloat strokeWidth;
} AMGeometry;

typedef struct {
    AMGeometry geometry;
    CGFloat scale;
    CGRect frame;
    float size;
    NSPoint center;
    CGFloat anglePerStep;
    CGFloat (^alphaFunction)(NSInteger, NSInteger);
    int alphaFunctionID;
    BOOL bigSur;
} AMConfig;

@interface AMIndeterminateProgressIndicator()
@property(nonatomic, retain) CAKeyframeAnimation *animation;
@end

@implementation AMIndeterminateProgressIndicator {
    NSSize _animationSize;
    int _count;
    BOOL _wantsAnimation;
    AMConfig _config;
    BOOL _hasConfig;
}

- (id)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
      self.wantsLayer = YES;
      [self setColor:[NSColor blackColor]];
      [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(windowWillEnterFullScreen:)
                                                   name:NSWindowWillEnterFullScreenNotification
                                                 object:nil];
      [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(windowDidEnterFullScreen:)
                                                   name:NSWindowDidEnterFullScreenNotification
                                                 object:nil];
      [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(windowWillExitFullScreen:)
                                                   name:NSWindowWillExitFullScreenNotification
                                                 object:nil];
      [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(windowDidExitFullScreen:)
                                                   name:NSWindowDidExitFullScreenNotification
                                                 object:nil];
  }
  return self;
}

- (void)windowWillEnterFullScreen:(NSNotification *)notification {
    if (_wantsAnimation && _count == 0) {
        [self stopAnimation];
    }
    _count++;
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification {
    _count--;
    if (_count == 0 && _wantsAnimation) {
        [self startAnimation];
    }
}

- (void)windowWillExitFullScreen:(NSNotification *)notification {
    if (_wantsAnimation && _count == 0) {
        [self stopAnimation];
    }
    _count++;
}

- (void)windowDidExitFullScreen:(NSNotification *)notification {
    _count--;
    if (_count == 0 && _wantsAnimation) {
        [self startAnimation];
    }
}

- (void)setColor:(NSColor *)value {
    if (_color != value) {
        _color = value;
        assert([_color alphaComponent] > 0.999);
    }
}

- (NSSize)physicalSize {
    NSSize size = self.frame.size;
    CGFloat scale = self.layer.contentsScale;
    size.width *= scale;
    size.height *= scale;
    return size;
}

- (void)startAnimation:(id)sender {
    _wantsAnimation = YES;
    [self startAnimation];
}

- (void)initializeConfigIfNeeded {
    if (_hasConfig) {
        return;
    }
    _config = [self config];
    _hasConfig = YES;
}

- (void)startAnimation {
    if (_count) {
        return;
    }
    if (!self.animation || !NSEqualSizes(_animationSize, self.physicalSize)) {
        _animationSize = self.physicalSize;
        self.animation = [CAKeyframeAnimation animationWithKeyPath:@"contents"];
        self.animation.calculationMode = kCAAnimationDiscrete;
        if (self.useBigSurStyle) {
            self.animation.duration = 0.8;
        } else {
            self.animation.duration = 0.5;
        }
        [self initializeConfigIfNeeded];
        NSArray *images = AMIndeterminateProgressIndicatorImagesForSize(self.physicalSize,
                                                                        self.numberOfSteps,
                                                                        self.numberOfSpokes,
                                                                        _color,
                                                                        &_config);
        static CFTimeInterval epoch;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            epoch = CACurrentMediaTime();
        });
        // This causes animations to all show the same frame at the same time.
        self.animation.beginTime = epoch;
        self.animation.values = images;
        self.animation.repeatCount = INFINITY;
    }
    [self.layer removeAllAnimations];
    [self.layer addAnimation:_animation forKey:@"contents"];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window && _wantsAnimation && [self.layer animationKeys] == nil) {
        // Layer animations seem to be removed when the view is removed from and then re-added to
        // the view hierarchy, so re-add it.
        [self startAnimation];
    }
}

- (void)stopAnimation:(id)sender {
    _wantsAnimation = NO;
    [self stopAnimation];
}

- (void)stopAnimation {
    [self.layer removeAllAnimations];
}

static void AMIndeterminateProgressIndicatorDrawSpoke(NSPoint firstPoint,
                                                      NSPoint secondPoint,
                                                      CGFloat strokeWidth) {
    NSLineCapStyle previousLineCapStyle = [NSBezierPath defaultLineCapStyle];
    CGFloat previousLineWidth = [NSBezierPath defaultLineWidth];

    [NSBezierPath setDefaultLineCapStyle:NSRoundLineCapStyle];
    [NSBezierPath setDefaultLineWidth:strokeWidth];

    [NSBezierPath strokeLineFromPoint:firstPoint toPoint:secondPoint];

    // Restore previous defaults
    [NSBezierPath setDefaultLineCapStyle:previousLineCapStyle];
    [NSBezierPath setDefaultLineWidth:previousLineWidth];
}

static void AMIndeterminateProgressIndicatorDrawStep(NSInteger step,
                                                     NSInteger numberOfSpokes,
                                                     NSColor *color,
                                                     const AMConfig *config) {
    CGFloat initialAngle = 0;
    if (!config->bigSur) {
        initialAngle = DegreesToRadians(270 - (step * config->anglePerStep));
    }

    for (NSInteger i = 0; i < numberOfSpokes; i++) {
        CGFloat currentAngle = initialAngle - DegreesToRadians(config->anglePerStep) * i;
        [[color colorWithAlphaComponent:config->alphaFunction(i, step)] set];

        const NSPoint outerPoint = NSMakePoint(config->center.x + cos(currentAngle) * config->geometry.outerRadius,
                                               config->center.y + sin(currentAngle) * config->geometry.outerRadius);

        const NSPoint innerPoint = NSMakePoint(config->center.x + cos(currentAngle) * config->geometry.innerRadius,
                                               config->center.y + sin(currentAngle) * config->geometry.innerRadius);
        AMIndeterminateProgressIndicatorDrawSpoke(innerPoint,
                                                  outerPoint,
                                                  config->geometry.strokeWidth);
    }
}

// Returns an array of CGImageRefs for each frame of the animation.
static NSArray *AMIndeterminateProgressIndicatorImagesForSize(NSSize size,
                                                              NSInteger numberOfSteps,
                                                              NSInteger numberOfSpokes,
                                                              NSColor *color,
                                                              const AMConfig *config) {
    static NSMutableDictionary *_cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _cache = [NSMutableDictionary dictionary];
    });
    id key = @{ @"size": NSStringFromSize(size),
                @"numberOfSteps": @(numberOfSteps),
                @"numberOfSpokes": @(numberOfSpokes),
                @"color": color,
                @"config.geometry.outerRadius": @(config->geometry.outerRadius),
                @"config.geometry.innerRadius": @(config->geometry.innerRadius),
                @"config.geometry.strokeWidth": @(config->geometry.strokeWidth),
                @"config.scale": @(config->scale),
                @"config.frame": NSStringFromRect(config->frame),
                @"config.size": @(config->size),
                @"config.center": NSStringFromPoint(config->center),
                @"config.anglePerStep": @(config->anglePerStep),
                @"config.alphaFunctionID": @(config->alphaFunctionID) };

    NSArray *cached = _cache[key];
    if (cached) {
        return cached;
    }

    NSMutableArray *frames = [NSMutableArray array];

    for (NSInteger step = 0; step < numberOfSteps; step++) {
        NSImage *image = [[NSImage alloc] initWithSize:size];
        [image lockFocus];
        AMIndeterminateProgressIndicatorDrawStep(step, numberOfSpokes, color, config);
        [image unlockFocus];
        
        NSBitmapImageRep *rep = image.bitmapImageRep;
        NSData *data = [rep representationUsingType:NSBitmapImageFileTypePNG
                                         properties:@{ NSImageInterlaced: @0,
                                                       NSImageCompressionFactor: @1 }];
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data);
        CGImageRef cgImage = CGImageCreateWithPNGDataProvider(provider,
                                                              NULL,
                                                              true,
                                                              kCGRenderingIntentDefault);
        CFRelease(provider);

        [frames addObject:(__bridge id)cgImage];
        CFRelease(cgImage);
    }
    _cache[key] = frames;
    return frames;
}

- (BOOL)useBigSurStyle {
    if (@available(macOS 10.16, *)) {
        return YES;
    }
    return NO;
}

- (NSInteger)numberOfSteps {
    if (self.useBigSurStyle) {
        return 48;
    }
    return 12;
}

- (NSInteger)numberOfSpokes {
    if (self.useBigSurStyle) {
        return 8;
    }
    return 12;
}

- (AMConfig)config {
    AMConfig config;
    config.frame = self.frame;
    
    // Scale frame by the layer's contentsScale so we fill it properly.
    config.scale = self.layer.contentsScale;
    config.frame.size.width *= config.scale;
    config.frame.size.height *= config.scale;
    config.frame.origin.x *= config.scale;
    config.frame.origin.y *= config.scale;
    
    config.size = MIN(config.frame.size.width, config.frame.size.height);
    config.center = NSMakePoint(NSMidX(config.frame), NSMidY(config.frame));
    config.anglePerStep = 360 / self.numberOfSpokes;
    
    if (self.useBigSurStyle) {
        config.bigSur = YES;
        config.alphaFunction = [self bigSurAlphaFunction];
        config.alphaFunctionID = 0;
        config.geometry = [self bigSurGeometryForSize:config.size scale:config.scale];
    } else {
        config.bigSur = NO;
        config.alphaFunction = [self legacyAlphaFunction];
        config.alphaFunctionID = 1;
        config.geometry = [self legacyGeometryForSize:config.size scale:config.scale];
    }
    return config;
}

- (CGFloat (^)(NSInteger, NSInteger))legacyAlphaFunction {
    return ^CGFloat(NSInteger i, NSInteger step) {
        return 1.0 - sqrt(self.numberOfSteps - 1 - i) * 0.25;
    };
}

- (AMGeometry)legacyGeometryForSize:(float)size scale:(CGFloat)scale {
    AMGeometry result;
    result.strokeWidth = size * 0.09;
    if (size >= 32.0 * scale) {
        result.outerRadius = size * 0.38;
        result.innerRadius = size * 0.23;
        return result;
    }
    result.outerRadius = size * 0.48;
    result.innerRadius = size * 0.27;
    return result;
}

- (CGFloat (^)(NSInteger, NSInteger))bigSurAlphaFunction {
    const CGFloat numberOfSpokes = self.numberOfSpokes;
    return ^CGFloat(NSInteger i, NSInteger step) {
        const CGFloat minAlpha = 0.07;
        const CGFloat maxAlpha = 0.45;
        
        // The fraction of the way around the circle where min alpha begins.
        const double minAlphaFraction = (double)step / (double)self.numberOfSteps;
        
        // The current fraction of the way around the circle.
        double currentAngle = (double)i / (double)self.numberOfSpokes;
        if (currentAngle < minAlphaFraction) {
            currentAngle += 1.0;
        }
        // Compute fraction of the way around the circle from minAlpha to i.
        const CGFloat delta = currentAngle - minAlphaFraction;
        
        // The alpha value will be the linear interpolation of the alpha between min and max for the current position between them.
        CGFloat result;
        if (delta < (numberOfSpokes - 1) / numberOfSpokes) {
            // Linear ramp up from delta=0 to delta=7/8 mapping to minAlpha -> maxAlpha
            const CGFloat normalizedDelta = delta * numberOfSpokes / (numberOfSpokes - 1);  // this goes from 0 to 1
            result = minAlpha + normalizedDelta * (maxAlpha - minAlpha);
        } else {
            // delta between 7/8 and 1
            const CGFloat normalizedDelta = 1.0 - (delta * numberOfSpokes - (numberOfSpokes - 1));  // this goes from 0 to 1
            result = minAlpha + normalizedDelta * (maxAlpha - minAlpha);
        }
        return result;
    };
}

- (AMGeometry)bigSurGeometryForSize:(float)size scale:(CGFloat)scale {
    AMGeometry result;
    result.strokeWidth = size * 0.125;
    if (size >= 32.0 * scale) {
        result.outerRadius = size * 0.38 - 1;
        result.innerRadius = size * 0.23 - 0.5;
        return result;
    }
    result.outerRadius = size * 0.48 - 1;
    result.innerRadius = size * 0.27 - 0.5;
    return result;
}

@end
