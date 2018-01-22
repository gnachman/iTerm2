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

@interface AMIndeterminateProgressIndicator()
@property(nonatomic, retain) CAKeyframeAnimation *animation;
@end

@implementation AMIndeterminateProgressIndicator {
    NSSize _animationSize;
    int _count;
    BOOL _wantsAnimation;
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

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_animation release];
    [_color release];
    [super dealloc];
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
        [_color autorelease];
        _color = [value retain];
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

- (void)startAnimation {
    if (_count) {
        return;
    }
    if (!self.animation || !NSEqualSizes(_animationSize, self.physicalSize)) {
        _animationSize = self.physicalSize;
        self.animation = [CAKeyframeAnimation animationWithKeyPath:@"contents"];
        self.animation.calculationMode = kCAAnimationDiscrete;
        self.animation.duration = 0.5;
        self.animation.values = self.images;
        self.animation.repeatCount = INFINITY;
    }
    [self.layer removeAllAnimations];
    [self.layer addAnimation:_animation forKey:@"contents"];
}

- (void)stopAnimation:(id)sender {
    _wantsAnimation = NO;
    [self stopAnimation];
}

- (void)stopAnimation {
    [self.layer removeAllAnimations];
}

// Returns an array of CGImageRefs for each frame of the animation.
- (NSArray *)images {
    NSMutableArray *frames = [NSMutableArray array];
    NSSize size = self.physicalSize;

    for (NSInteger step = 0; step < self.numberOfSteps; step++) {
        NSImage *image = [[[NSImage alloc] initWithSize:size] autorelease];
        [image lockFocus];
        [self drawStep:step];
        [image unlockFocus];
        
        NSBitmapImageRep *rep = image.bitmapImageRep;
        NSData *data = [rep representationUsingType:NSPNGFileType
                                         properties:@{ NSImageInterlaced: @NO,
                                                       NSImageCompressionFactor: @1 }];
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data);
        CGImageRef cgImage = CGImageCreateWithPNGDataProvider(provider,
                                                              NULL,
                                                              true,
                                                              kCGRenderingIntentDefault);
        CFRelease(provider);

        [frames addObject:(id)cgImage];
        CFRelease(cgImage);
    }
    return frames;
}

- (NSInteger)numberOfSteps {
    return 12;
}

- (void)drawStrokeFromPoint:(NSPoint)firstPoint
                    toPoint:(NSPoint)secondPoint
                strokeWidth:(CGFloat)strokeWidth {
    NSLineCapStyle previousLineCapStyle = [NSBezierPath defaultLineCapStyle];
    CGFloat previousLineWidth = [NSBezierPath defaultLineWidth];

    [NSBezierPath setDefaultLineCapStyle:NSRoundLineCapStyle];
    [NSBezierPath setDefaultLineWidth:strokeWidth];
    
    [NSBezierPath strokeLineFromPoint:firstPoint toPoint:secondPoint];

    // Restore previous defaults
    [NSBezierPath setDefaultLineCapStyle:previousLineCapStyle];
    [NSBezierPath setDefaultLineWidth:previousLineWidth];
}

- (void)drawStep:(NSInteger)step {
    CGRect frame = self.frame;
    
    // Scale frame by the layer's contentsScale so we fill it properly.
    CGFloat scale = self.layer.contentsScale;
    frame.size.width *= scale;
    frame.size.height *= scale;
    frame.origin.x *= scale;
    frame.origin.y *= scale;
    
    float size = MIN(frame.size.width, frame.size.height);
    NSPoint center = NSMakePoint(NSMidX(frame), NSMidY(frame));
    
    CGFloat outerRadius;
    CGFloat innerRadius;
    const CGFloat strokeWidth = size * 0.09;
    if (size >= 32.0 * scale) {
        outerRadius = size * 0.38;
        innerRadius = size * 0.23;
    } else {
        outerRadius = size * 0.48;
        innerRadius = size * 0.27;
    }
    
    NSPoint innerPoint;
    NSPoint outerPoint;
    CGFloat anglePerStep = 360 / self.numberOfSteps;
    CGFloat initialAngle = DegreesToRadians(270 - (step * anglePerStep));

    for (NSInteger i = 0; i < self.numberOfSteps; i++) {
        CGFloat currentAngle = initialAngle - DegreesToRadians(anglePerStep) * i;
        [[_color colorWithAlphaComponent:1.0 - sqrt(self.numberOfSteps - 1 - i) * 0.25] set];

        outerPoint = NSMakePoint(center.x + cos(currentAngle) * outerRadius,
                                 center.y + sin(currentAngle) * outerRadius);
        
        innerPoint = NSMakePoint(center.x + cos(currentAngle) * innerRadius,
                                 center.y + sin(currentAngle) * innerRadius);

        [self drawStrokeFromPoint:innerPoint toPoint:outerPoint strokeWidth:strokeWidth];
    }
}

@end
