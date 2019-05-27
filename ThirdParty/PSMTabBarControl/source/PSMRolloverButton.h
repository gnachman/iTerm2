//
//  PSMOverflowPopUpButton.h
//  NetScrape
//
//  Created by John Pannell on 8/4/04.
//  Copyright 2004 Positive Spin Media. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface PSMRolloverButton : NSButton

// the regular image
- (void)setUsualImage:(NSImage *)newImage;
- (NSImage *)usualImage;

// the rollover image
- (void)setRolloverImage:(NSImage *)newImage;
- (NSImage *)rolloverImage;

@end
