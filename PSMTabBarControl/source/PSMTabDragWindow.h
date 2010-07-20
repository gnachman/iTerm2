//
//  PSMTabDragWindow.h
//  PSMTabBarControl
//
//  Created by Kent Sutherland on 6/1/06.
//  Copyright 2006 Kent Sutherland. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class PSMTabBarCell;

@interface PSMTabDragWindow : NSWindow {
	PSMTabBarCell *_cell;
	NSImageView *_imageView;
}
+ (PSMTabDragWindow *)dragWindowWithTabBarCell:(PSMTabBarCell *)cell image:(NSImage *)image styleMask:(unsigned int)styleMask;

- (id)initWithTabBarCell:(PSMTabBarCell *)cell image:(NSImage *)image styleMask:(unsigned int)styleMask;
- (NSImage *)image;
@end
