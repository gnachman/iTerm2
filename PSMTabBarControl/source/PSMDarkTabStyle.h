//
//  PSMDarkTabStyle.h
//  iTerm
//
//  Created by Brian Mock on 10/28/14.
//
//

#ifndef iTerm_PSMDarkTabStyle_h
#define iTerm_PSMDarkTabStyle_h

#import <Cocoa/Cocoa.h>
#import "PSMTabStyle.h"

@interface PSMDarkTabStyle : NSObject <PSMTabStyle>
{
    NSImage *darkCloseButton;
    NSImage *darkCloseButtonDown;
    NSImage *darkCloseButtonOver;
    NSImage *_addTabButtonImage;
    NSImage *_addTabButtonPressedImage;
    NSImage *_addTabButtonRolloverImage;

    float leftMargin;
    PSMTabBarControl *tabBar;
}
- (void)setLeftMarginForTabBarControl:(float)margin;
@end


#endif
