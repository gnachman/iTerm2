//
//  PSMTabDragWindow.m
//  PSMTabBarControl
//
//  Created by Kent Sutherland on 6/1/06.
//  Copyright 2006 Kent Sutherland. All rights reserved.
//

#import "PSMTabDragWindow.h"
#import "PSMTabBarCell.h"

@implementation PSMTabDragWindow

+ (PSMTabDragWindow *)dragWindowWithTabBarCell:(PSMTabBarCell *)cell image:(NSImage *)image styleMask:(unsigned int)styleMask
{
	return [[[PSMTabDragWindow alloc] initWithTabBarCell:cell image:image styleMask:styleMask] autorelease];
}

- (id)initWithTabBarCell:(PSMTabBarCell *)cell image:(NSImage *)image styleMask:(unsigned int)styleMask
{
	if ( (self = [super initWithContentRect:NSMakeRect(0, 0, 0, 0) styleMask:styleMask backing:NSBackingStoreBuffered defer:NO]) ) {
		_cell = [cell retain];
		_imageView = [[[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 0, 0)] autorelease];
		[self setContentView:_imageView];
		[self setLevel:NSStatusWindowLevel];
		[self setIgnoresMouseEvents:YES];
		[self setOpaque:NO];
		
		[_imageView setImage:image];
		
		//Set the size of the window to be the exact size of the drag image
		NSSize imageSize = [image size];
		NSRect windowFrame = [self frame];
		
		windowFrame.origin.y += windowFrame.size.height - imageSize.height;
		windowFrame.size = imageSize;
		
		if (styleMask | NSBorderlessWindowMask) {
			windowFrame.size.height += 22;
		}
		
		[self setFrame:windowFrame display:YES];
	}
	return self;
}

- (void)dealloc
{
	[_cell release];
	[super dealloc];
}

- (NSImage *)image
{
	return [[self contentView] image];
}

@end
