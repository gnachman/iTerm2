//
//  iTermFindCursorView.m
//  iTerm
//
//  Created by George Nachman on 12/26/13.
//
//

#import "iTermFindCursorView.h"
#import "NSBezierPath+iTerm.h"
#import "NSDate+iTerm.h"
#import <QuartzCore/QuartzCore.h>

// Delay before teardown.
const double kFindCursorHoldTime = 1;

// When performing the "find cursor" action, a gray window is shown with a
// transparent "hole" around the cursor. This is the radius of that hole in
// pixels.
const double kFindCursorHoleRadius = 30;

#pragma mark - Interfaces for concrete implementations

@interface iTermFindCursorViewStarsImpl : iTermFindCursorView
@end

@interface iTermFindCursorViewArrowImpl : iTermFindCursorView
@end

@interface iTermFindCursorViewSpotlightImpl : iTermFindCursorView
@end

#pragma mark - Concrete implementations

@implementation iTermFindCursorViewSpotlightImpl

+ (instancetype)allocWithZone:(struct _NSZone *)zone {
    return NSAllocateObject([self class], 0, zone);
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];

    if (self) {
        self.alphaValue = 0.7;
    }
    return self;
}

// drawLayer:inContext: only gets called if drawRect: is implemented. wtf.
- (void)drawRect:(CGRect)dirtyRect {
    NSGradient *grad = [[NSGradient alloc] initWithStartingColor:[NSColor whiteColor]
                                                     endingColor:[NSColor blackColor]];
    NSPoint relativeCursorPosition = NSMakePoint(2 * (self.cursorPosition.x / self.frame.size.width - 0.5),
                                                 2 * (self.cursorPosition.y / self.frame.size.height - 0.5));
    NSRect rect = NSMakeRect(0, 0, self.frame.size.width, self.frame.size.height);
    [grad drawInRect:rect relativeCenterPosition:relativeCursorPosition];
    [grad release];

    double x = self.cursorPosition.x;
    double y = self.cursorPosition.y;

    const double focusRadius = kFindCursorHoleRadius;
    [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositeCopy];
    NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x - focusRadius,
                                                                             y - focusRadius,
                                                                             focusRadius * 2,
                                                                             focusRadius * 2)];
    [[NSColor clearColor] set];
    [circle fill];
}

- (void)setCursorPosition:(NSPoint)cursorPosition {
    [super setCursorPosition:cursorPosition];
    [self setNeedsDisplay:YES];
}


@end
@implementation iTermFindCursorViewArrowImpl {
    CALayer *_arrowLayer;
}

+ (instancetype)allocWithZone:(struct _NSZone *)zone {
    return NSAllocateObject([self class], 0, zone);
}

- (void)dealloc {
    [_arrowLayer release];
    [super dealloc];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];

    if (self) {
        [self setWantsLayer:YES];
        _arrowLayer = [[CALayer alloc] init];
        NSImage *image = [NSImage imageNamed:@"BigArrow"];
        _arrowLayer.frame = NSMakeRect(0, 0, image.size.width, image.size.height);
        _arrowLayer.contents = (id)[image CGImageForProposedRect:nil context:nil hints:nil];
        [self.layer addSublayer:_arrowLayer];

        [CATransaction begin];
        CAKeyframeAnimation *spinAnim = [CAKeyframeAnimation animationWithKeyPath:@"transform"];
        spinAnim.duration = 0.75;

        // Animations take the shortest path.
        // Specifying 0-2*pi doesn't work (that's no animation).
        // Specifying a keyframe of 0 -> pi -> 2*pi doesn't work (it goes to 180 degrees and then back the way it came)
        // It works to do 0 -> pi -> 2*pi + epsilon, although it shouldn't.
        // I could do it with three keyframe steps but it's strange to work with 2pi/3, so I use four instead.
        spinAnim.values = @[ [NSValue valueWithCATransform3D:CATransform3DMakeRotation(0, 0, 0, 1)],
                             [NSValue valueWithCATransform3D:CATransform3DMakeRotation(M_PI_2, 0, 0, 1)],
                             [NSValue valueWithCATransform3D:CATransform3DMakeRotation(M_PI, 0, 0, 1)],
                             [NSValue valueWithCATransform3D:CATransform3DMakeRotation(3.0 * M_PI_2, 0, 0, 1)],
                             [NSValue valueWithCATransform3D:CATransform3DMakeRotation(0, 0, 0, 1)] ];
        spinAnim.repeatCount = HUGE_VALF;
        _arrowLayer.anchorPoint = CGPointMake(1, 0.5);
        [_arrowLayer addAnimation:spinAnim forKey:@"spin"];


        [CATransaction commit];
    }
    return self;
}

- (void)setCursorPosition:(NSPoint)cursorPosition {
    [super setCursorPosition:cursorPosition];
    _arrowLayer.position = CGPointMake(cursorPosition.x, cursorPosition.y);
}


@end

#pragma mark -

@implementation iTermFindCursorViewStarsImpl {
    CAEmitterLayer *_emitterLayer;
}

+ (instancetype)allocWithZone:(struct _NSZone *)zone {
    return NSAllocateObject([self class], 0, zone);
}

- (void)dealloc {
    [_emitterLayer release];
    [super dealloc];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];

    if (self) {
        [self setWantsLayer:YES];
        _emitterLayer = [[CAEmitterLayer layer] retain];
        _emitterLayer.emitterPosition = CGPointMake(self.bounds.size.width/2, self.bounds.size.height*(.75));
        _emitterLayer.renderMode = kCAEmitterLayerAdditive;
        _emitterLayer.emitterShape = kCAEmitterLayerPoint;

        // If the emitter layer has multiple emitterCells then it shows white boxes on 10.10.2. So instead
        // we create an invisible cell and give it multiple emitterCells.
        _emitterLayer.emitterCells = @[ [self rootEmitterCell] ];
        [self.layer addSublayer:_emitterLayer];
    }
    return self;
}

- (void)setCursorPosition:(NSPoint)cursorPosition {
    [super setCursorPosition:cursorPosition];
    _emitterLayer.emitterPosition = cursorPosition;

    CAShapeLayer *mask = [[[CAShapeLayer alloc] init] autorelease];

    NSBezierPath *outerPath = [NSBezierPath bezierPath];
    outerPath.windingRule = NSEvenOddWindingRule;

    NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(cursorPosition.x - 20,
                                                                           cursorPosition.y - 20,
                                                                           40,
                                                                           40)];
    [outerPath appendBezierPath:path];
    [outerPath appendBezierPath:[NSBezierPath bezierPathWithRect:self.bounds]];
    mask.fillRule = kCAFillRuleEvenOdd;
    mask.path = [outerPath iterm_CGPath];
    mask.fillColor = [[NSColor whiteColor] CGColor];
    self.layer.mask = mask;
}

#pragma mark - Private methods

- (CAEmitterCell *)rootEmitterCell {
    CAEmitterCell *supercell = [self supercell];
    float v = 1000;
    float b = 100;
    supercell.emitterCells = @[ [self subcellWithImageNumber:1 birthRate:b/5 velocity:v delay:0],
                                [self subcellWithImageNumber:2 birthRate:b/5 velocity:v delay:0],
                                [self subcellWithImageNumber:3 birthRate:b/5 velocity:v delay:0],
                                [self subcellWithImageNumber:1 birthRate:b velocity:v/10 delay:0],
                                [self subcellWithImageNumber:2 birthRate:b velocity:v/10 delay:0],
                                [self subcellWithImageNumber:3 birthRate:b velocity:v/10 delay:0]];
    return supercell;
}

- (CAEmitterCell *)supercell {
    CAEmitterCell *cell = [CAEmitterCell emitterCell];
    [cell setBirthRate:4];
    [cell setVelocity:0];
    [cell setVelocityRange:0];
    [cell setEmissionLongitude:M_PI_2];
    [cell setEmissionRange:M_PI * 2];
    [cell setScale:0];
    [cell setScaleSpeed:0];
    [cell setYAcceleration:0];
    [cell setScaleRange:0];
    [cell setAlphaSpeed:0];
    [cell setLifetime:0.75];
    [cell setLifetimeRange:0.25];
    [cell setSpin:M_PI * 6];
    [cell setSpinRange:M_PI * 2];

    return cell;
}

- (CAEmitterCell *)subcellWithImageNumber:(int)imageNumber
                                birthRate:(float)birthRate
                                 velocity:(float)v
                                    delay:(float)delay {
    CAEmitterCell *cell = [CAEmitterCell emitterCell];
    [cell setBirthRate:birthRate];
    [cell setEmissionLongitude:M_PI_2];
    [cell setEmissionRange:M_PI * 2];
    [cell setScale:0];
    [cell setVelocity:v];
    [cell setVelocityRange:v * 0.1];
    [cell setScaleSpeed:0.3];
    [cell setScaleRange:0.1];
    NSString *name = [NSString stringWithFormat:@"FindCursorCell%d", imageNumber];
    NSImage *image = [NSImage imageNamed:name];
    if (image) {
        [cell setContents:(id)[image CGImageForProposedRect:nil context:nil hints:nil]];
    }
    float lifetime = 1;
    [cell setAlphaSpeed:-1 / lifetime];
    [cell setLifetime:lifetime];
    [cell setLifetimeRange: lifetime * 0.3];
    [cell setSpin:M_PI * 6];
    [cell setSpinRange:M_PI * 2];
    [cell setBeginTime:delay];
    return cell;
}

@end

#pragma mark -

@implementation iTermFindCursorView {
    NSTimer *_findCursorTeardownTimer;
}

+ (instancetype)allocWithZone:(struct _NSZone *)zone {
    if ([NSDate isAprilFools] && [[NSView class] instancesRespondToSelector:@selector(allowsVibrancy)]) {
        // 10.10+ users get spiffy views on 4/1
        static int i;
        if (i++ % 2) {
            return [iTermFindCursorViewArrowImpl alloc];
        } else {
            return [iTermFindCursorViewStarsImpl alloc];
        }
    } else {
        return [iTermFindCursorViewSpotlightImpl alloc];
    }
}

- (void)setCursorPosition:(NSPoint)cursorPosition {
    _cursorPosition = cursorPosition;
}

- (void)startTearDownTimer {
    [self stopTearDownTimer];
    _findCursorTeardownTimer = [NSTimer scheduledTimerWithTimeInterval:kFindCursorHoldTime
                                                                target:self
                                                              selector:@selector(startCloseFindCursorWindow:)
                                                              userInfo:nil
                                                               repeats:NO];
}

- (void)stopTearDownTimer {
    [_findCursorTeardownTimer invalidate];
    _findCursorTeardownTimer = nil;
}

- (void)startCloseFindCursorWindow:(NSTimer *)timer {
    _findCursorTeardownTimer = nil;
    if (_autohide && !_stopping) {
        [_delegate findCursorViewDismiss];
    }
}

@end
