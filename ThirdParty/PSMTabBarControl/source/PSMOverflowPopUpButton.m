//
//  PSMOverflowPopUpButton.m
//  PSMTabBarControl
//
//  Created by John Pannell on 11/4/05.
//  Copyright 2005 Positive Spin Media. All rights reserved.
//

#import "PSMOverflowPopUpButton.h"
#import "PSMTabBarControl.h"

@implementation PSMOverflowPopUpButton {
    NSImage         *_PSMTabBarOverflowPopUpImage;
    NSImage         *_PSMTabBarOverflowDownPopUpImage;
    BOOL            _down;
}

- (id)initWithFrame:(NSRect)frameRect pullsDown:(BOOL)flag {
    self = [super initWithFrame:frameRect pullsDown:YES];
    if (self) {
        [self setBezelStyle:NSBezelStyleRegularSquare];
        [self setBordered:NO];
        [self setTitle:@""];
        [self setPreferredEdge:NSMaxXEdge];
        _PSMTabBarOverflowPopUpImage = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:@"overflowImage"]];
        _PSMTabBarOverflowDownPopUpImage = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:@"overflowImagePressed"]];
    }
    return self;
}

- (void)drawRect:(NSRect)rect {
    if (_PSMTabBarOverflowPopUpImage == nil) {
        [super drawRect:rect];
        return;
    }
    
    NSImage *image = (_down) ? _PSMTabBarOverflowDownPopUpImage : _PSMTabBarOverflowPopUpImage;
    NSSize imageSize = [image size];
    NSRect bounds = [self bounds];
    
    NSPoint drawPoint = NSMakePoint(NSMidX(bounds) - (imageSize.width * 0.5f), NSMidY(bounds) - (imageSize.height * 0.5f));
    
    [image drawAtPoint:drawPoint
              fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver
              fraction:1.0f];
}

- (void)mouseDown:(NSEvent *)event
{
    _down = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(notificationReceived:)
                                                 name:NSMenuDidEndTrackingNotification
                                               object:[self menu]];
    [self setNeedsDisplay:YES];
    [super mouseDown:event];
}

- (void)notificationReceived:(NSNotification *)notification
{
    _down = NO;
    [self setNeedsDisplay:YES];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
