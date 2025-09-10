//
//  PSMOverflowPopUpButton.m
//  NetScrape
//
//  Created by John Pannell on 8/4/04.
//  Copyright 2004 Positive Spin Media. All rights reserved.
//

#import "PSMRolloverButton.h"

static const CGFloat PSMRolloverButtonDifferenceThreshold = 0.0001;
static const CGFloat PSMRolloverButtonFramesPerSecond = 60.0;
static const CGFloat PSMRolloverButtonMaxAlpha = 0.25;

extern BOOL gDebugLogging;
int DebugLogImpl(const char *file, int line, const char *function, NSString* value);
#define DLog(args...) \
    do { \
        if (gDebugLogging) { \
            DebugLogImpl(__FILE__, __LINE__, __FUNCTION__, [NSString stringWithFormat:args]); \
        } \
    } while (0)

@implementation PSMRolloverButton {
    NSImage *_rolloverImage;
    NSImage *_usualImage;
    CGFloat _targetAlpha;
    CGFloat _alpha;
    NSTimer *_timer;
    NSTrackingArea *_trackingArea;
    CGFloat _dragDistance;
    NSPoint _lastDragLocation;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
    }
    return self;
}

- (void)dealloc {
    if (_trackingArea) {
        [self removeTrackingArea:_trackingArea];
    }
}

- (BOOL)becomeFirstResponder {
    return NO;
}

// the regular image
- (void)setUsualImage:(NSImage *)newImage {
    _usualImage = newImage;
    [self setImage:_usualImage];
}

- (NSImage *)usualImage {
    return _usualImage;
}

- (void)setRolloverImage:(NSImage *)newImage {
    _rolloverImage = newImage;
}

- (NSImage *)rolloverImage {
    return _rolloverImage;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    [self reallyUpdateTrackingAreas];
}

- (void)reallyUpdateTrackingAreas {
    if (_trackingArea) {
        [self removeTrackingArea:_trackingArea];
    }


    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:(NSTrackingMouseEnteredAndExited |
                                                          NSTrackingMouseMoved |
                                                          NSTrackingCursorUpdate |
                                                          NSTrackingActiveAlways)
                                                   owner:self
                                                userInfo:nil];
    [self setTargetAlpha:0];
    [self addTrackingArea:_trackingArea];
}

// override for rollover effect
- (void)mouseEntered:(NSEvent *)theEvent {
    if (![self mouseReallyEntered:theEvent]) {
        [super mouseEntered:theEvent];
    }
}

- (BOOL)mouseReallyEntered:(NSEvent *)theEvent {
    [self setTargetAlpha:PSMRolloverButtonMaxAlpha];
    // set rollover image
    [self setImage:_rolloverImage];
    [self setNeedsDisplay:YES];
    [[self superview] setNeedsDisplay:YES]; // eliminates a drawing artifact
    return YES;
}

- (void)mouseExited:(NSEvent *)theEvent {
    if (![self mouseReallyExited:theEvent]) {
        [super mouseExited:theEvent];
    }
}

- (BOOL)mouseReallyExited:(NSEvent *)theEvent {
    // restore usual image
    [self setTargetAlpha:0];
    [self setImage:_usualImage];
    [self setNeedsDisplay:YES];
    [[self superview] setNeedsDisplay:YES]; // eliminates a drawing artifact
    return YES;
}

- (void)setTargetAlpha:(CGFloat)targetAlpha {
    if (fabs(targetAlpha - _targetAlpha) < PSMRolloverButtonDifferenceThreshold) {
        return;
    }
    _targetAlpha = targetAlpha;
    if (!_timer) {
        _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 / PSMRolloverButtonFramesPerSecond
                                                  target:self
                                                selector:@selector(updateBackgroundAlphaTimer:)
                                                userInfo:nil
                                                 repeats:YES];
    }
}

// macOS 10.14+ because it needs layers to properly composite the background color.
- (void)updateBackgroundAlphaTimer:(NSTimer *)timer NS_AVAILABLE_MAC(10_14) {
    const CGFloat duration = 0.25;
    const CGFloat changePerSecond = PSMRolloverButtonMaxAlpha / duration;
    if (_alpha < _targetAlpha) {
        _alpha = MIN(_targetAlpha, _alpha + changePerSecond / PSMRolloverButtonFramesPerSecond);
    } else {
        _alpha = MAX(_targetAlpha, _alpha - changePerSecond / PSMRolloverButtonFramesPerSecond);
    }
    if (fabs(_alpha - _targetAlpha) < PSMRolloverButtonDifferenceThreshold) {
        // Close enough
        [_timer invalidate];
        _timer = nil;
        _alpha = _targetAlpha;
    }
    self.layer.backgroundColor = [[NSColor colorWithWhite:0.5 alpha:_alpha] CGColor];
}

// Must override mouseDown and mouseUp and not call super for mouseDragged: to work.
- (void)mouseDown:(NSEvent *)theEvent {
    if (![self mouseReallyDown:theEvent]) {
        [super mouseDown:theEvent];
    }
}

- (BOOL)mouseReallyDown:(NSEvent *)theEvent {
    // eliminates drawing artifact
    [[NSRunLoop currentRunLoop] performSelector:@selector(display)
                                         target:[self superview]
                                       argument:nil
                                          order:1
                                          modes:@[ NSEventTrackingRunLoopMode, NSDefaultRunLoopMode ]];
    _dragDistance = 0;
    _lastDragLocation = theEvent.locationInWindow;
    DLog(@"mouseDown. Set dragDistance=0, lastDragLocation=%@", NSStringFromPoint(_lastDragLocation));
    return YES;
}

- (void)mouseUp:(NSEvent *)theEvent {
    if (![self mouseReallyUp:theEvent]) {
        [super mouseUp:theEvent];
    }
}

- (BOOL)mouseReallyUp:(NSEvent *)event {
    if (event.clickCount == 1 && _dragDistance < 4) {
        DLog(@"mouseUp. dragDistance=%@ so act like click", @(_dragDistance));
        [self performClick:self];
    }
    DLog(@"mouseUp. dragDistance=%@ so reset drag distance to 0", @(_dragDistance));
    _dragDistance = 0;
    return YES;
}

- (void)mouseDragged:(NSEvent *)event {
    if (![self mouseReallyDragged:event]) {
        [super mouseDragged:event];
    }
}

- (BOOL)mouseReallyDragged:(NSEvent *)event {
    if (!self.allowDrags) {
        DLog(@"mouseDragged. drags not allowed");
        return NO;
    }
    _dragDistance += sqrt(pow(event.locationInWindow.y - _lastDragLocation.y, 2) +
                          pow(event.locationInWindow.x - _lastDragLocation.x, 2));
    _lastDragLocation = event.locationInWindow;
    DLog(@"mouseDragged. dragDistance<-%@ lastDragLocation<-%@", @(_dragDistance), @(_lastDragLocation));
    [self.window makeKeyAndOrderFront:nil];
    [self.window performWindowDragWithEvent:event];
    return YES;
}

- (void)resetCursorRects {
    // called when the button rect has been changed
    [[self superview] setNeedsDisplay:YES]; // eliminates a drawing artifact
}

@end

#ifdef MAC_OS_VERSION_26_0
NS_AVAILABLE_MAC(26)
@implementation PSMTahoeRolloverButton

- (instancetype)initWithSymbolName:(NSString *)name {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        NSImage *symbol = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
        symbol.template = YES;
        self.image = symbol;

        self.imagePosition = NSImageOnly;
        self.imageScaling = NSImageScaleProportionallyDown;
        self.contentTintColor = [NSColor labelColor];

        // New Tahoe (macOS 26) look:
        self.controlSize = NSControlSizeLarge;
        self.bezelStyle = NSBezelStyleGlass;              // Liquid Glass bezel
        self.borderShape = NSControlBorderShapeCircle;    // round/capsule shape
        self.bordered = YES;
        self.showsBorderOnlyWhileMouseInside = NO;
    }
    return self;
}

- (void)setUsualImage:(NSImage *)newImage {
}

- (NSImage *)usualImage {
    return nil;
}
- (void)setRolloverImage:(NSImage *)newImage {
}

- (NSImage *)rolloverImage {
    return nil;
}

- (void)reallyUpdateTrackingAreas {
}

- (BOOL)mouseReallyEntered:(NSEvent *)theEvent {
    return NO;
}

- (BOOL)mouseReallyExited:(NSEvent *)theEvent {
    return NO;
}

- (BOOL)mouseReallyDown:(NSEvent *)theEvent {
    return NO;
}
- (BOOL)mouseReallyUp:(NSEvent *)event {
    return NO;
}
- (BOOL)mouseReallyDragged:(NSEvent *)event {
    return NO;
}

@end
#endif
