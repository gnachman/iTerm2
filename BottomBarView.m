//
//  BottomBarView.m
//  iTerm
//
//  Created by George Nachman on 12/26/13.
//
//

#import "BottomBarView.h"

@implementation BottomBarView

- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor controlColor] setFill];
    NSRectFill(dirtyRect);
    
    // Draw a black line at the top of the view.
    [[NSColor blackColor] setFill];
    NSRect r = [self frame];
    NSRectFill(NSMakeRect(0, r.size.height - 1, r.size.width, 1));
}

@end
