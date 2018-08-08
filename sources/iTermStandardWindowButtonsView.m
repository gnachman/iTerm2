//
//  iTermStandardWindowButtonsView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/7/18.
//

#import "iTermStandardWindowButtonsView.h"

@implementation iTermStandardWindowButtonsView {
    BOOL _mouseInGroup;
    NSTrackingArea *_trackingArea;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(redraw)
                                                     name:NSApplicationDidBecomeActiveNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(redraw)
                                                     name:NSApplicationDidResignActiveNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(redraw)
                                                     name:NSWindowDidBecomeKeyNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(redraw)
                                                     name:NSWindowDidResignKeyNotification
                                                   object:nil];
    }
    return self;
}

- (void)redraw {
    for (NSView *subview in self.subviews) {
        [subview setNeedsDisplay:YES];
    }
}

- (NSView *)hitTest:(NSPoint)point {
    if (self.alphaValue == 0) {
        return nil;
    }
    NSView *view = [super hitTest:point];
    if (view == self) {
        return nil;
    } else {
        return view;
    }
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea != nil) {
        [self removeTrackingArea:_trackingArea];
    }
    
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways)
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
    [super mouseEntered:event];
    [self setShowIcons:YES];
}

- (void)mouseExited:(NSEvent *)event {
    [super mouseExited:event];
    [self setShowIcons:NO];
}

- (void)setShowIcons:(BOOL)mouseInGroup {
    if (!!_mouseInGroup == !!mouseInGroup) {
        return;
    }
    _mouseInGroup = mouseInGroup;
    for (NSView *subview in self.subviews) {
        [subview setNeedsDisplay:YES];
    }
}

// Overrides a private method. Returns YES to show icons in the buttons.
- (BOOL)_mouseInGroup:(NSButton*)button {
    return _mouseInGroup;
}

@end
