//
//  PSMOverflowPopUpButton.h
//  NetScrape
//
//  Created by John Pannell on 8/4/04.
//  Copyright 2004 Positive Spin Media. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface PSMRolloverButton : NSButton
{
    NSImage             *_rolloverImage;
    NSImage             *_usualImage;
    NSTrackingRectTag   _myTrackingRectTag;
}

// the regular image
- (void)setUsualImage:(NSImage *)newImage;
- (NSImage *)usualImage;

// the rollover image
- (void)setRolloverImage:(NSImage *)newImage;
- (NSImage *)rolloverImage;

// tracking rect for mouse events
- (void)addTrackingRect;
- (void)removeTrackingRect;
@end