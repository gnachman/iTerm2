//
//  PSMOverflowPopUpButton.m
//  PSMTabBarControl
//
//  Created by John Pannell on 11/4/05.
//  Copyright 2005 Positive Spin Media. All rights reserved.
//

#import "PSMOverflowPopUpButton.h"
#import "PSMTabBarControl.h"

#define TIMER_INTERVAL 1.0 / 10.0
#define ANIMATION_STEP 0.05f

@implementation PSMOverflowPopUpButton

- (id)initWithFrame:(NSRect)frameRect pullsDown:(BOOL)flag
{
    if (self = [super initWithFrame:frameRect pullsDown:YES]) {
        [self setBezelStyle:NSRegularSquareBezelStyle];
        [self setBordered:NO];
        [self setTitle:@""];
        [self setPreferredEdge:NSMaxXEdge];
        _PSMTabBarOverflowPopUpImage = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:@"overflowImage"]];
		_PSMTabBarOverflowDownPopUpImage = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:@"overflowImagePressed"]];
		_animatingAlternateImage = NO;
    }
    return self;
}

- (void)dealloc
{
    [_PSMTabBarOverflowPopUpImage release];
	[_PSMTabBarOverflowDownPopUpImage release];
    [super dealloc];
}

- (void)drawRect:(NSRect)rect
{
    if(_PSMTabBarOverflowPopUpImage == nil){
        [super drawRect:rect];
        return;
    }
	
    NSImage *image = (_down) ? _PSMTabBarOverflowDownPopUpImage : _PSMTabBarOverflowPopUpImage;
	NSSize imageSize = [image size];
	NSRect bounds = [self bounds];
	
	NSPoint drawPoint = NSMakePoint(NSMidX(bounds) - (imageSize.width * 0.5f), NSMidY(bounds) - (imageSize.height * 0.5f));
	
    if ([self isFlipped]) {
        drawPoint.y += imageSize.height;
    }
	
    [image compositeToPoint:drawPoint operation:NSCompositeSourceOver fraction:(_animatingAlternateImage ? 0.7f : 1.0f)];
	
	if (_animatingAlternateImage) {
		NSImage *alternateImage = [self alternateImage];
		NSSize altImageSize = [alternateImage size];
		drawPoint = NSMakePoint(NSMidX(bounds) - (altImageSize.width * 0.5f), NSMidY(bounds) - (altImageSize.height * 0.5f));
		
		if ([self isFlipped]) {
			drawPoint.y += altImageSize.height;
		}
		
		[[self alternateImage] compositeToPoint:drawPoint operation:NSCompositeSourceOver fraction:sin(_animationValue * M_PI)];
	}
}

- (void)mouseDown:(NSEvent *)event
{
	_down = YES;
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notificationReceived:) name:NSMenuDidEndTrackingNotification object:[self menu]];
	[self setNeedsDisplay:YES];
	[super mouseDown:event];
}

- (void)setHidden:(BOOL)value
{
	if (!value && _animatingAlternateImage) {
		_animationValue = ANIMATION_STEP;
		_animationTimer = [NSTimer scheduledTimerWithTimeInterval:TIMER_INTERVAL target:self selector:@selector(animateStep:) userInfo:nil repeats:YES];
		[[NSRunLoop currentRunLoop] addTimer:_animationTimer forMode:NSEventTrackingRunLoopMode];
	} else {
		[_animationTimer invalidate], _animationTimer = nil;
	}
	
	[super setHidden:value];
}

- (void)notificationReceived:(NSNotification *)notification
{
	_down = NO;
	[self setNeedsDisplay:YES];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setAnimatingAlternateImage:(BOOL)flag
{
	_animatingAlternateImage = flag;
	[self setNeedsDisplay:YES];
	
	if (![self isHidden] && !_animationTimer) {
		if (flag) {
			_animationValue = ANIMATION_STEP;
			_animationTimer = [NSTimer scheduledTimerWithTimeInterval:TIMER_INTERVAL target:self selector:@selector(animateStep:) userInfo:nil repeats:YES];
			[[NSRunLoop currentRunLoop] addTimer:_animationTimer forMode:NSEventTrackingRunLoopMode];
		} else {
			[_animationTimer invalidate], _animationTimer = nil;
		}
	}
}

- (BOOL)animatingAlternateImage;
{
	return _animatingAlternateImage;
}

- (void)animateStep:(NSTimer *)timer
{
	_animationValue += ANIMATION_STEP;
	
	if (_animationValue >= 1) {
		_animationValue = ANIMATION_STEP;
	}
	
	[self setNeedsDisplay:YES];
}

#pragma mark -
#pragma mark Archiving

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [super encodeWithCoder:aCoder];
    if ([aCoder allowsKeyedCoding]) {
        [aCoder encodeObject:_PSMTabBarOverflowPopUpImage forKey:@"PSMTabBarOverflowPopUpImage"];
        [aCoder encodeObject:_PSMTabBarOverflowDownPopUpImage forKey:@"PSMTabBarOverflowDownPopUpImage"];
		[aCoder encodeBool:_animatingAlternateImage forKey:@"PSMTabBarOverflowAnimatingAlternateImage"];
    }
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    if ( (self = [super initWithCoder:aDecoder]) ) {
        if ([aDecoder allowsKeyedCoding]) {
            _PSMTabBarOverflowPopUpImage = [[aDecoder decodeObjectForKey:@"PSMTabBarOverflowPopUpImage"] retain];
            _PSMTabBarOverflowDownPopUpImage = [[aDecoder decodeObjectForKey:@"PSMTabBarOverflowDownPopUpImage"] retain];
			[self setAnimatingAlternateImage:[aDecoder decodeBoolForKey:@"PSMTabBarOverflowAnimatingAlternateImage"]];
        }
    }
    return self;
}

@end
