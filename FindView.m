// -*- mode:objc -*-
/*
 **  FindView.m
 **
 **  Copyright (c) 2011
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: Draws find UI.
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

#import "FindView.h"
#import "iTerm/PseudoTerminal.h"

@implementation FindView

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
    }
    return self;
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect frame = [self frame];
    [[NSGraphicsContext currentContext] saveGraphicsState];
    [[NSGraphicsContext currentContext] setShouldAntialias:YES];
    NSBezierPath* path = [[NSBezierPath alloc] init];
    [path setLineWidth:1];
    float radius = 4;
    float height = frame.size.height - 1;
    float width = frame.size.width - 1;
    float x = 0.5;
    float y = 0;
    float nx, ny;
    [path moveToPoint:NSMakePoint(x, y)];
    nx = x+radius;
    ny = y+radius+0.5;  // Add an extra 0.5 to get on the pixel grid.
    [path curveToPoint:NSMakePoint(nx, ny)
         controlPoint1:NSMakePoint((nx+x)/2, y)
         controlPoint2:NSMakePoint(nx, (ny+y)/2)];
    x = nx; y = ny;
    ny = y + height - 2*radius;
    [path lineToPoint:NSMakePoint(nx, ny)];
    x = nx; y = ny;
    nx = x + radius;
    ny = y + radius;
    [path curveToPoint:NSMakePoint(nx, ny)
         controlPoint1:NSMakePoint(x, (y + ny)/2)
         controlPoint2:NSMakePoint((x+nx)/2, ny)];
    x = nx; y = ny;
    nx = x + width - 4*radius;
    [path lineToPoint:NSMakePoint(nx, ny)];
    x = nx; y = ny;
    nx = x + radius;
    ny = y - radius;
    [path curveToPoint:NSMakePoint(nx, ny)
         controlPoint1:NSMakePoint((nx+x)/2, y)
         controlPoint2:NSMakePoint(nx, (ny+y)/2)];
    x = nx; y = ny;
    ny = y - height + 2*radius;
    [path lineToPoint:NSMakePoint(nx, ny)];
    x = nx; y = ny;
    nx = x + radius;
    ny = y - radius - 0.5; // Subtract 0.5 to return to the "true" origin of the frame
    [path curveToPoint:NSMakePoint(nx, ny)
         controlPoint1:NSMakePoint(x, (ny+y)/2)
         controlPoint2:NSMakePoint((x+nx)/2, ny)];

    PseudoTerminal* term = [[self window] windowController];
    if ([term isKindOfClass:[PseudoTerminal class]]) {
      [term fillPath:path];
    } else {
      [[NSColor windowBackgroundColor] set];
      [path fill];
    }
    [path release];
    [[NSGraphicsContext currentContext] restoreGraphicsState];
}

@end
