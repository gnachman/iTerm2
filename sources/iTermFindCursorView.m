//
//  FindCursorView.m
//  iTerm
//
//  Created by George Nachman on 12/26/13.
//
//

#import "iTermFindCursorView.h"
#import <QuartzCore/QuartzCore.h>

// Delay before teardown.
const double kFindCursorHoldTime = 1;

// When performing the "find cursor" action, a gray window is shown with a
// transparent "hole" around the cursor. This is the radius of that hole in
// pixels.
const double kFindCursorHoleRadius = 30;

@implementation iTermFindCursorView {
    NSTimer *_findCursorTeardownTimer;
    NSTimer *_findCursorBlinkTimer;
    CAEmitterLayer *_emitterLayer;
}

- (id)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];

    if (self) {
        [self setWantsLayer:YES];

        [self createCells];
    }

    return self;
}

- (void)dealloc {
    [_emitterLayer release];
    [super dealloc];
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


- (void)createCells {
    _emitterLayer = [[CAEmitterLayer layer] retain];
    _emitterLayer.emitterPosition = CGPointMake(self.bounds.size.width/2, self.bounds.size.height*(.75));
    _emitterLayer.renderMode = kCAEmitterLayerAdditive;
    _emitterLayer.emitterShape = kCAEmitterLayerPoint;

    // If the emitter layer has multiple emitterCells then it shows white boxes on 10.10.2. So instead
    // we create an invisibel cell and give it multiple emitterCells.
    _emitterLayer.emitterCells = @[ [self rootEmitterCell] ];
    [self.layer addSublayer:_emitterLayer];
}

- (void)setCursorPosition:(NSPoint)cursorPosition {
    _emitterLayer.emitterPosition = cursorPosition;
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
