//
//  PSMYosemiteTabStyle.h
//  PSMTabBarControl
//
//  Created by John Pannell on 2/17/06.
//  Copyright 2006 Positive Spin Media. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "PSMTabStyle.h"

@interface PSMYosemiteTabStyle : NSObject <PSMTabStyle> {
    NSImage *metalCloseButton;
    NSImage *metalCloseButtonDown;
    NSImage *metalCloseButtonOver;
    NSImage *_addTabButtonImage;
    NSImage *_addTabButtonPressedImage;
    NSImage *_addTabButtonRolloverImage;
	
	NSDictionary *_objectCountStringAttributes;
	
	PSMTabBarOrientation orientation;
	PSMTabBarControl *tabBar;
}

- (void)encodeWithCoder:(NSCoder *)aCoder;
- (id)initWithCoder:(NSCoder *)aDecoder;

@end
