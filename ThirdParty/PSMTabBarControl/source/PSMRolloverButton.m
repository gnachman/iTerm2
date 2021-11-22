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

@implementation PSMRolloverButton {
    NSImage *_rolloverImage;
    NSImage *_usualImage;
    CGFloat _targetAlpha;
    CGFloat _alpha;
    NSTimer *_timer;
    NSTrackingArea *_trackingArea;
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
    [self setTargetAlpha:PSMRolloverButtonMaxAlpha];
    // set rollover image
    [self setImage:_rolloverImage];
    [self setNeedsDisplay:YES];
    [[self superview] setNeedsDisplay:YES]; // eliminates a drawing artifact
}

- (void)mouseExited:(NSEvent *)theEvent {
    // restore usual image
    [self setTargetAlpha:0];
    [self setImage:_usualImage];
    [self setNeedsDisplay:YES];
    [[self superview] setNeedsDisplay:YES]; // eliminates a drawing artifact
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
    // eliminates drawing artifact
    [[NSRunLoop currentRunLoop] performSelector:@selector(display)
                                         target:[self superview]
                                       argument:nil
                                          order:1
                                          modes:@[ NSEventTrackingRunLoopMode, NSDefaultRunLoopMode ]];
}

- (void)mouseUp:(NSEvent *)event {
    if (event.clickCount == 1) {
        [self performClick:self];
    }
}

- (void)mouseDragged:(NSEvent *)event {
    [self.window makeKeyAndOrderFront:nil];
    [self.window performWindowDragWithEvent:event];
}

- (void)resetCursorRects {
    // called when the button rect has been changed
    [[self superview] setNeedsDisplay:YES]; // eliminates a drawing artifact
}

#pragma mark -  Archiving

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [super encodeWithCoder:aCoder];
    if ([aCoder allowsKeyedCoding]) {
        [aCoder encodeObject:_rolloverImage forKey:@"rolloverImage"];
        [aCoder encodeObject:_usualImage forKey:@"usualImage"];
    }
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        if ([aDecoder allowsKeyedCoding]) {
            _rolloverImage = [aDecoder decodeObjectForKey:@"rolloverImage"];
            _usualImage = [aDecoder decodeObjectForKey:@"usualImage"];
        }
    }
    return self;
}


@end
