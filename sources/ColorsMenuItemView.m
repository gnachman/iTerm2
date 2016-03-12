/*
 **  ColorsMenuItemView.m
 **
 **  Copyright (c) 2012
 **
 **  Author: Andrea Bonomi
 **
 **  Project: iTerm
 **
 **  Description: Colored Tabs.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import "ColorsMenuItemView.h"

@interface ColorsMenuItemView()
@property(nonatomic, retain) NSColor *color;
@end

@implementation ColorsMenuItemView

const int kNumberOfColors = 8;
const int kColorAreaOffsetX = 20;
const int kColorAreaOffsetY = 10;
const int kColorAreaDistanceX = 18;
const int kColorAreaDimension = 12;
const int kColorAreaBorder = 1;
const int kDefaulColorOffset = 2;
const int kDefaultColorDimension = 8;
const int kDefaultColorStokeWidth = 2;
const int kMenuFontSize = 14;
const int kMenuLabelOffsetX = 20;
const int kMenuLabelOffsetY = 32;

enum {
    kMenuItemDefault = 0,
    kMenuItemRed = 1,
    kMenuItemOrange = 2,
    kMenuItemYellow = 3,
    kMenuItemGreen = 4,
    kMenuItemBlue = 5,
    kMenuItemPurple = 6,
    kMenuItemGray = 7
};

- (void)dealloc {
    [_color release];
    [super dealloc];
}

// Returns the color gradient corresponding to the color index.
// These colors were chosen to appear similar to those in Aperture 3.
// Based on http://cocoatricks.com/2010/07/a-label-color-picker-menu-item-2/

- (NSGradient *)gradientForColorIndex:(NSInteger)colorIndex {
    NSGradient *gradient = nil;

    switch (colorIndex) {
        case kMenuItemDefault:
            return nil;

        case kMenuItemRed:
            gradient = [[NSGradient alloc] initWithColorsAndLocations:
                        [NSColor colorWithDeviceRed:241.0/255.0 green:152.0/255.0 blue:139.0/255.0 alpha:1.0], 0.0,
                        [NSColor colorWithDeviceRed:228.0/255.0 green:116.0/255.0 blue:102.0/255.0 alpha:1.0], 0.5,
                        [NSColor colorWithDeviceRed:192.0/255.0 green:86.0/255.0 blue:73.0/255.0 alpha:1.0], 1.0, nil];
            break;
        case kMenuItemOrange:
            gradient = [[NSGradient alloc] initWithColorsAndLocations:
                        [NSColor colorWithDeviceRed:248.0/255.0 green:201.0/255.0 blue:148.0/255.0 alpha:1.0], 0.0,
                        [NSColor colorWithDeviceRed:237.0/255.0 green:174.0/255.0 blue:107.0/255.0 alpha:1.0], 0.5,
                        [NSColor colorWithDeviceRed:210.0/255.0 green:143.0/255.0 blue:77.0/255.0 alpha:1.0], 1.0, nil];
            break;
        case kMenuItemYellow:
            gradient = [[NSGradient alloc] initWithColorsAndLocations:
                        [NSColor colorWithDeviceRed:240.0/255.0 green:229.0/255.0 blue:164.0/255.0 alpha:1.0], 0.0,
                        [NSColor colorWithDeviceRed:227.0/255.0 green:213.0/255.0 blue:119.0/255.0 alpha:1.0], 0.5,
                        [NSColor colorWithDeviceRed:201.0/255.0 green:188.0/255.0 blue:92.0/255.0 alpha:1.0], 1.0, nil];
            break;
        case kMenuItemGreen:
            gradient = [[NSGradient alloc] initWithColorsAndLocations:
                        [NSColor colorWithDeviceRed:209.0/255.0 green:236.0/255.0 blue:156.0/255.0 alpha:1.0], 0.0,
                        [NSColor colorWithDeviceRed:175.0/255.0 green:215.0/255.0 blue:119.0/255.0 alpha:1.0], 0.5,
                        [NSColor colorWithDeviceRed:142.0/255.0 green:182.0/255.0 blue:102.0/255.0 alpha:1.0], 1.0, nil];
            break;
        case kMenuItemBlue:
            gradient = [[NSGradient alloc] initWithColorsAndLocations:
                        [NSColor colorWithDeviceRed:165.0/255.0 green:216.0/255.0 blue:249.0/255.0 alpha:1.0], 0.0,
                        [NSColor colorWithDeviceRed:118.0/255.0 green:185.0/255.0 blue:232.0/255.0 alpha:1.0], 0.5,
                        [NSColor colorWithDeviceRed:90.0/255.0 green:152.0/255.0 blue:201.0/255.0 alpha:1.0], 1.0, nil];
            break;
        case kMenuItemPurple:
            gradient = [[NSGradient alloc] initWithColorsAndLocations:
                        [NSColor colorWithDeviceRed:232.0/255.0 green:191.0/255.0 blue:248.0/255.0 alpha:1.0], 0.0,
                        [NSColor colorWithDeviceRed:202.0/255.0 green:152.0/255.0 blue:224.0/255.0 alpha:1.0], 0.5,
                        [NSColor colorWithDeviceRed:163.0/255.0 green:121.0/255.0 blue:186.0/255.0 alpha:1.0], 1.0, nil];
            break;
        case kMenuItemGray:
            gradient = [[NSGradient alloc] initWithColorsAndLocations:
                        [NSColor colorWithDeviceRed:150.0/255.0 green:150.0/255.0 blue:150.0/255.0 alpha:1.0], 0.0,
                        [NSColor colorWithDeviceRed:130.0/255.0 green:130.0/255.0 blue:130.0/255.0 alpha:1.0], 0.5,
                        [NSColor colorWithDeviceRed:120.0/255.0 green:120.0/255.0 blue:120.0/255.0 alpha:1.0], 1.0, nil];
            break;
    }

    return [gradient autorelease];
}

// Draw the menu item (label and colors)

- (void)drawRect:(NSRect)rect
{
    // draw the "x" (reset color to default)
    NSColor *color = [NSColor grayColor];
    [color set];
    CGFloat savedWidth = [NSBezierPath defaultLineWidth];
    [NSBezierPath setDefaultLineWidth:kDefaultColorStokeWidth];
    float defaultX0 = kColorAreaOffsetX + kDefaulColorOffset;
    float defaultX1 = defaultX0 + kDefaultColorDimension;
    float defaultY0 = kColorAreaOffsetY + kDefaulColorOffset;
    float defaultY1 = defaultY0 + kDefaultColorDimension;
    [NSBezierPath strokeLineFromPoint:NSMakePoint(defaultX0, defaultY0)
                              toPoint:NSMakePoint(defaultX1, defaultY1)];
    [NSBezierPath strokeLineFromPoint:NSMakePoint(defaultX1, defaultY0)
                              toPoint:NSMakePoint(defaultX0, defaultY1)];

    // draw the colors
    NSGradient *outlineGradient = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithDeviceWhite:0.0 alpha:0.3]
                                                                endingColor:[NSColor colorWithDeviceWhite:0.0 alpha:0.7]];

    for (NSInteger i = 1; i < kNumberOfColors; i++) {
        NSRect outlineArea = NSMakeRect(kColorAreaOffsetX + kColorAreaDistanceX * i, kColorAreaOffsetY,
                                        kColorAreaDimension, kColorAreaDimension);
        // draw the outline
        [outlineGradient drawInRect:outlineArea angle:-90.0];

        // draw the color
        NSRect colorArea = NSInsetRect(outlineArea, kColorAreaBorder, kColorAreaBorder);
        NSGradient *gradient = [self gradientForColorIndex:i];
        [gradient drawInRect:colorArea angle:-90.0];
    }
    [outlineGradient release];

    // draw the menu label
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    attributes[NSFontAttributeName] = [NSFont menuFontOfSize:kMenuFontSize];
    
    NSMenu *rootMenu = self.enclosingMenuItem.menu;
    while (rootMenu.supermenu) {
        rootMenu = rootMenu.supermenu;
    }
    if (rootMenu == [NSApp mainMenu] &&
        [[[NSUserDefaults standardUserDefaults] stringForKey:@"AppleInterfaceStyle"] isEqualToString:@"Dark"]) {
        attributes[NSForegroundColorAttributeName] = [NSColor whiteColor];
    }

    NSString *labelTitle = @"Tab Color:";
    [labelTitle drawAtPoint:NSMakePoint(kMenuLabelOffsetX, kMenuLabelOffsetY) withAttributes:attributes];
    [NSBezierPath setDefaultLineWidth:savedWidth];
}

- (void)mouseUp:(NSEvent*) event {
    NSPoint mousePoint = [self convertPoint:[[self window] mouseLocationOutsideOfEventStream] fromView:nil];
    NSMenuItem* mitem = [self enclosingMenuItem];
    NSMenu* m = [mitem menu];
    [m cancelTracking];

    // check the click Y position
    if (mousePoint.y >= kColorAreaOffsetY && mousePoint.y <= kColorAreaOffsetY + kColorAreaDimension) {
        // convert the mouse position into a color index
        int x = (int)mousePoint.x - kColorAreaOffsetX;
        int offset = x % kColorAreaDistanceX;
        int colorIndex = x / kColorAreaDistanceX;
        // check the click X position
        if (offset >= 0 && offset < kColorAreaDimension &&
                colorIndex >= 0 && colorIndex < kNumberOfColors) {
            switch (colorIndex) {
                case kMenuItemDefault:
                    self.color = nil;
                    break;
                case kMenuItemRed:
                    self.color = [NSColor colorWithDeviceRed:251.0/255.0 green:107.0/255.0 blue:98.0/255.0 alpha:1.0];
                    break;
                case kMenuItemOrange:
                    self.color = [NSColor colorWithDeviceRed:246.0/255.0 green:172.0/255.0 blue:71.0/255.0 alpha:1.0];
                    break;
                case kMenuItemYellow:
                    self.color = [NSColor colorWithDeviceRed:240.0/255.0 green:220.0/255.0 blue:79.0/255.0 alpha:1.0];
                    break;
                case kMenuItemGreen:
                    self.color = [NSColor colorWithDeviceRed:181.0/255.0 green:215.0/255.0 blue:73.0/255.0 alpha:1.0];
                    break;
                case kMenuItemBlue:
                    self.color = [NSColor colorWithDeviceRed:95.0/255.0 green:163.0/255.0 blue:248.0/255.0 alpha:1.0];
                    break;
                case kMenuItemPurple:
                    self.color = [NSColor colorWithDeviceRed:193.0/255.0 green:142.0/255.0 blue:217.0/255.0 alpha:1.0];
                    break;
                case kMenuItemGray:
                    self.color = [NSColor colorWithDeviceRed:120.0/255.0 green:120.0/255.0 blue:120.0/255.0 alpha:1.0];
                    break;
            }
            // perform the menu action (set the color)
            NSInteger menuIndex = [m indexOfItem: mitem];
            [m performActionForItemAtIndex: menuIndex];
        }
    }
}

@end
