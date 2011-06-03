//
//  PSMOverflowPopUpButton.m
//  NetScrape
//
//  Created by John Pannell on 8/4/04.
//  Copyright 2004 Positive Spin Media. All rights reserved.
//

#import "PSMRolloverButton.h"

@implementation PSMRolloverButton

// the regular image
- (void)setUsualImage:(NSImage *)newImage
{
    [newImage retain];
    [_usualImage release];
    _usualImage = newImage;
    [self setImage:_usualImage];
}

- (NSImage *)usualImage
{
    return _usualImage;
}

- (void)setRolloverImage:(NSImage *)newImage
{
    [newImage retain];
    [_rolloverImage release];
    _rolloverImage = newImage;
}

- (NSImage *)rolloverImage
{
    return _rolloverImage;
}

- (void)addTrackingRect
{
    // assign a tracking rect to watch for mouse enter/exit
    _myTrackingRectTag = [self addTrackingRect:[self bounds] owner:self userData:nil assumeInside:NO];
}

- (void)removeTrackingRect
{
	if (_myTrackingRectTag) {
		[self removeTrackingRect:_myTrackingRectTag];
	}
	_myTrackingRectTag = 0;
}

// override for rollover effect
- (void)mouseEntered:(NSEvent *)theEvent;
{
    // set rollover image
    [self setImage:_rolloverImage];
    [self setNeedsDisplay];
    [[self superview] setNeedsDisplay:YES]; // eliminates a drawing artifact
}

- (void)mouseExited:(NSEvent *)theEvent;
{
    // restore usual image
    [self setImage:_usualImage];
    [self setNeedsDisplay];
    [[self superview] setNeedsDisplay:YES]; // eliminates a drawing artifact
}

- (void)mouseDown:(NSEvent *)theEvent
{
    // eliminates drawing artifact
    [[NSRunLoop currentRunLoop] performSelector:@selector(display) target:[self superview] argument:nil order:1 modes:[NSArray arrayWithObjects:@"NSEventTrackingRunLoopMode", @"NSDefaultRunLoopMode", nil]];
    [super mouseDown:theEvent];
}

- (void)resetCursorRects
{
    // called when the button rect has been changed
    [self removeTrackingRect];
    [self addTrackingRect];
    [[self superview] setNeedsDisplay:YES]; // eliminates a drawing artifact
}

#pragma mark -
#pragma mark Archiving

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [super encodeWithCoder:aCoder];
    if ([aCoder allowsKeyedCoding]) {
        [aCoder encodeObject:_rolloverImage forKey:@"rolloverImage"];
        [aCoder encodeObject:_usualImage forKey:@"usualImage"];
        [aCoder encodeInt:_myTrackingRectTag forKey:@"myTrackingRectTag"];
    }
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        if ([aDecoder allowsKeyedCoding]) {
            _rolloverImage = [[aDecoder decodeObjectForKey:@"rolloverImage"] retain];
            _usualImage = [[aDecoder decodeObjectForKey:@"usualImage"] retain];
            _myTrackingRectTag = [aDecoder decodeIntForKey:@"myTrackingRectTag"];
        }
    }
    return self;
}


@end
