//
//  AMIndeterminateProgressIndicator.m
//
//  Created by Andreas on 23.01.07.
//  Copyright 2007 Andreas Mayer. All rights reserved.
//

#import "AMIndeterminateProgressIndicator.h"

#define ConvertAngle(a) (fmod((90.0-(a)), 360.0))

#define DEG2RAD  0.017453292519943295

@interface AMIndeterminateProgressIndicator ()
@property(nonatomic) BOOL animate;
@end

@implementation AMIndeterminateProgressIndicator {
  double _step;
  NSTimer *_timer;
  NSTimeInterval _startTime;
}

- (id)init {
  self = [super init];
	if (self) {
		[self setColor:[NSColor blackColor]];
	}
	return self;
}

- (void)dealloc {
	[_color release];
	[super dealloc];
}

- (void)setColor:(NSColor *)value {
	if (_color != value) {
		[_color autorelease];
		_color = [value retain];
    assert([_color alphaComponent] > 0.999);
	}
}

- (void)startAnimation:(id)sender {
  self.animate = YES;
}

- (void)stopAnimation:(id)sender {
  self.animate = NO;
}

- (void)drawRect:(NSRect)dirtyRect {
  if (self.animate) {
    NSTimeInterval delta = [NSDate timeIntervalSinceReferenceDate] - _startTime;
    int step = round(-fmod(delta * 2.2, 1.0) * 12);
    CGRect frame = self.frame;
		float size = MIN(frame.size.width, frame.size.height);
    NSPoint center = NSMakePoint(NSMidX(frame), NSMidY(frame));

		float outerRadius;
		float innerRadius;
		float strokeWidth = size * 0.09;
		if (size >= 32.0) {
			outerRadius = size * 0.38;
			innerRadius = size * 0.23;
		} else {
			outerRadius = size * 0.48;
			innerRadius = size * 0.27;
		}

		float a; // angle
		NSPoint inner;
		NSPoint outer;
		// remember defaults
		NSLineCapStyle previousLineCapStyle = [NSBezierPath defaultLineCapStyle];
		float previousLineWidth = [NSBezierPath defaultLineWidth]; 
		// new defaults for our loop
		[NSBezierPath setDefaultLineCapStyle:NSRoundLineCapStyle];
		[NSBezierPath setDefaultLineWidth:strokeWidth];
    if (self.animate) {
			a = (270 + (step * 30)) * DEG2RAD;
		} else {
			a = 270 * DEG2RAD;
		}
		int i;
		for (i = 0; i < 12; i++) {
      [[_color colorWithAlphaComponent:1.0 - sqrt(i) * 0.25] set];
			outer = NSMakePoint(center.x + cos(a) * outerRadius, center.y + sin(a) * outerRadius);
			inner = NSMakePoint(center.x + cos(a) * innerRadius, center.y + sin(a) * innerRadius);
			[NSBezierPath strokeLineFromPoint:inner toPoint:outer];
			a -= 30 * DEG2RAD;
		}
		// restore previous defaults
		[NSBezierPath setDefaultLineCapStyle:previousLineCapStyle];
		[NSBezierPath setDefaultLineWidth:previousLineWidth];
	}
}

#pragma mark - Private

- (void)redraw {
  [self setNeedsDisplay:YES];
}

- (void)setAnimate:(BOOL)animate {
  if (animate == _animate) {
    return;
  }

  _animate = animate;
  if (animate) {
    _startTime = [NSDate timeIntervalSinceReferenceDate];
    _timer = [NSTimer scheduledTimerWithTimeInterval:1 / 60.0
                                              target:self
                                            selector:@selector(redraw)
                                            userInfo:nil
                                             repeats:YES];
  } else {
    [_timer invalidate];
    _timer = nil;
  }
}

@end
