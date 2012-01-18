/*
 
 File: TrackView.h
 
 Abstract: The NSView that handles the label color tracking.
 
 Version: 1.0
 
 
 */

#import <Cocoa/Cocoa.h>

@interface ColorLabelMenuItemView : NSView
{	
	NSInteger		selectedLabel;	// indicates the currently tracked label
}

@property (nonatomic, readonly) NSInteger selectedLabel;x

@end

