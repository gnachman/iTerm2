//
//  ColorsMenuItemView.m
//  iTerm
//
//  Created by Andrea Bonomi on 2012/01/18.
//  

#import "ColorsMenuItemView.h"

@implementation ColorsMenuItemView

- (NSColor*)color
{
    return color_;
}

// -------------------------------------------------------------------------------
//	Returns the color gradient corresponding to the label. These colours were
//  chosen to appear similar to those in Aperture 3.
//  from http://cocoatricks.com/2010/07/a-label-color-picker-menu-item-2/
// -------------------------------------------------------------------------------

- (NSGradient *)gradientForLabel:(NSInteger)colorLabel
{
	NSGradient *gradient = nil;
	
	switch (colorLabel) {			
		case 1: // red
			gradient = [[NSGradient alloc] initWithColorsAndLocations:
						[NSColor colorWithDeviceRed:241.0/255.0 green:152.0/255.0 blue:139.0/255.0 alpha:1.0], 0.0,
						[NSColor colorWithDeviceRed:228.0/255.0 green:116.0/255.0 blue:102.0/255.0 alpha:1.0], 0.5,
						[NSColor colorWithCalibratedRed:192.0/255.0 green:86.0/255.0 blue:73.0/255.0 alpha:1.0], 1.0, nil];
			break;
		case 2: // orange
			gradient = [[NSGradient alloc] initWithColorsAndLocations:
						[NSColor colorWithDeviceRed:248.0/255.0 green:201.0/255.0 blue:148.0/255.0 alpha:1.0], 0.0,
						[NSColor colorWithDeviceRed:237.0/255.0 green:174.0/255.0 blue:107.0/255.0 alpha:1.0], 0.5,
						[NSColor colorWithCalibratedRed:210.0/255.0 green:143.0/255.0 blue:77.0/255.0 alpha:1.0], 1.0, nil];
			break;
		case 3: // yellow
			gradient = [[NSGradient alloc] initWithColorsAndLocations:
						[NSColor colorWithDeviceRed:240.0/255.0 green:229.0/255.0 blue:164.0/255.0 alpha:1.0], 0.0,
						[NSColor colorWithDeviceRed:227.0/255.0 green:213.0/255.0 blue:119.0/255.0 alpha:1.0], 0.5,
						[NSColor colorWithCalibratedRed:201.0/255.0 green:188.0/255.0 blue:92.0/255.0 alpha:1.0], 1.0, nil];
			break;
		case 4: // green
			gradient = [[NSGradient alloc] initWithColorsAndLocations:
						[NSColor colorWithDeviceRed:209.0/255.0 green:236.0/255.0 blue:156.0/255.0 alpha:1.0], 0.0,
						[NSColor colorWithDeviceRed:175.0/255.0 green:215.0/255.0 blue:119.0/255.0 alpha:1.0], 0.5,
						[NSColor colorWithCalibratedRed:142.0/255.0 green:182.0/255.0 blue:102.0/255.0 alpha:1.0], 1.0, nil];
			break;
		case 5: // blue
			gradient = [[NSGradient alloc] initWithColorsAndLocations:
						[NSColor colorWithDeviceRed:165.0/255.0 green:216.0/255.0 blue:249.0/255.0 alpha:1.0], 0.0,
						[NSColor colorWithDeviceRed:118.0/255.0 green:185.0/255.0 blue:232.0/255.0 alpha:1.0], 0.5,
						[NSColor colorWithCalibratedRed:90.0/255.0 green:152.0/255.0 blue:201.0/255.0 alpha:1.0], 1.0, nil];
			break;
		case 6: // purple
			gradient = [[NSGradient alloc] initWithColorsAndLocations:
						[NSColor colorWithDeviceRed:232.0/255.0 green:191.0/255.0 blue:248.0/255.0 alpha:1.0], 0.0,
						[NSColor colorWithDeviceRed:202.0/255.0 green:152.0/255.0 blue:224.0/255.0 alpha:1.0], 0.5,
						[NSColor colorWithCalibratedRed:163.0/255.0 green:121.0/255.0 blue:186.0/255.0 alpha:1.0], 1.0, nil];
			break;
		case 7: // gray
			gradient = [[NSGradient alloc] initWithColorsAndLocations:
						[NSColor colorWithCalibratedWhite:212.0/255.0 alpha:1.0], 0.0,
						[NSColor colorWithCalibratedWhite:182.0/255.0 alpha:1.0], 0.5,
						[NSColor colorWithCalibratedWhite:151.0/255.0 alpha:1.0], 1.0, nil];
			break;
			
	}
	
	return [gradient autorelease];
}

// -------------------------------------------------------------------------------
//	Examine all the sub-view colored dots and color them with their appropriate colors.
//  from http://cocoatricks.com/2010/07/a-label-color-picker-menu-item-2/
// -------------------------------------------------------------------------------

-(void)drawRect:(NSRect)rect
{    
	for (NSInteger i = 0; i < 8; i++)
	{
		NSRect colorSquareRect = NSMakeRect(10 + 20 * i, 10, 16, 16);
        
		// draw the gradient dot
		NSGradient *gradient = [self gradientForLabel:i];
		NSRect dotRect = NSInsetRect(colorSquareRect, 2.0, 2.0);
		NSBezierPath *circlePath = [NSBezierPath bezierPathWithOvalInRect:dotRect];
		[gradient drawInBezierPath:circlePath angle:-90.0];
        
		// top edge outline
		gradient = [[NSGradient alloc] initWithColorsAndLocations:
					[NSColor colorWithCalibratedWhite:1.0 alpha:0.18], 0.0,
					[NSColor colorWithCalibratedWhite:1.0 alpha:0.0], 0.6, nil];
		circlePath = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(dotRect, 1.0, 1.0)];
		[circlePath appendBezierPath:[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(dotRect.origin.x+1.0, dotRect.origin.y-2.0, dotRect.size.width-2.0, dotRect.size.height)]];
		[circlePath setWindingRule:NSEvenOddWindingRule];
		[gradient drawInBezierPath:circlePath angle:-90.0];
		[gradient release];
		
		// top center gloss
		gradient = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:1.0 alpha:0.18] 
												 endingColor:[NSColor colorWithCalibratedWhite:1.0 alpha:0.0]];
		[gradient drawFromCenter:NSMakePoint(NSMidX(dotRect), NSMaxY(dotRect) - 2.0)
						  radius:0.0
						toCenter:NSMakePoint(NSMidX(dotRect), NSMaxY(dotRect) - 2.0)
						  radius:4.0
						 options:0];
		[gradient release];
		
		// draw a dark outline
		circlePath = [NSBezierPath bezierPathWithOvalInRect:dotRect];
		gradient = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.0 alpha:0.12] 
												 endingColor:[NSColor colorWithCalibratedWhite:0.0 alpha:0.46]];
		[circlePath appendBezierPath:[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(dotRect, 1.0, 1.0)]];
		[circlePath setWindingRule:NSEvenOddWindingRule];
		[gradient drawInBezierPath:circlePath angle:-90.0];
		[gradient release];		
	}
	
	
	// draw the menu Label:
	NSMutableDictionary *fontAtts = [[NSMutableDictionary alloc] init];
	[fontAtts setObject: [NSFont menuFontOfSize:14.0] forKey: NSFontAttributeName];
	NSString *labelTitle = @"Tab Color:";
	[labelTitle drawAtPoint:NSMakePoint(20.0, 32.0) withAttributes:fontAtts];
	[fontAtts release];
}


- (void)mouseUp:(NSEvent*) event {
    NSPoint mousePoint = [self convertPoint:[[self window] mouseLocationOutsideOfEventStream] fromView:nil];    
    NSMenuItem* mitem = [self enclosingMenuItem];
    NSMenu* m = [mitem menu];
    [m cancelTracking];
    
    if (mousePoint.y >= 10 && mousePoint.y <= 26) {
        int x = (int)mousePoint.x - 10;
        int p = x % 20;
        x = x / 20;
        if (p >= 2 && p <= 15 && x >= 0 && x <= 7) {
            switch (x) {
                case 0:
                    color_ = [NSColor whiteColor];
                    break;            
                case 1:
                    color_ = [NSColor redColor];
                    break;
                case 2:
                    color_ = [NSColor orangeColor];
                    break;
                case 3:
                    color_ = [NSColor yellowColor];
                    break;
                case 4:
                    color_ = [NSColor greenColor];
                    break;
                case 5:
                    color_ = [NSColor blueColor];
                    break;
                case 6:
                    color_ = [NSColor purpleColor];
                    break;
                case 7:
                    color_ = [NSColor grayColor];
                    break;
            }
            NSInteger menuIndex = [m indexOfItem: mitem];
            [m performActionForItemAtIndex: menuIndex];
        }
    }
}

@end
