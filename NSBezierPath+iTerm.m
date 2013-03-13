//
//  NSBezierPath+iTerm.m
//  iTerm
//
//  Created by George Nachman on 3/12/13.
//
//

#import "NSBezierPath+iTerm.h"

@implementation NSBezierPath (iTerm)

+ (NSBezierPath *)smoothPathAroundBottomOfFrame:(NSRect)frame {
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
    y = ny;
    ny = y + height - 2*radius;
    [path lineToPoint:NSMakePoint(nx, ny)];
    x = nx; y = ny;
    nx = x + radius;
    ny = y + radius;
    [path curveToPoint:NSMakePoint(nx, ny)
         controlPoint1:NSMakePoint(x, (y + ny)/2)
         controlPoint2:NSMakePoint((x+nx)/2, ny)];
    x = nx;
    nx = x + width - 4*radius;
    [path lineToPoint:NSMakePoint(nx, ny)];
    x = nx; y = ny;
    nx = x + radius;
    ny = y - radius;
    [path curveToPoint:NSMakePoint(nx, ny)
         controlPoint1:NSMakePoint((nx+x)/2, y)
         controlPoint2:NSMakePoint(nx, (ny+y)/2)];
    y = ny;
    ny = y - height + 2*radius;
    [path lineToPoint:NSMakePoint(nx, ny)];
    x = nx; y = ny;
    nx = x + radius;
    ny = y - radius - 0.5; // Subtract 0.5 to return to the "true" origin of the frame
    [path curveToPoint:NSMakePoint(nx, ny)
         controlPoint1:NSMakePoint(x, (ny+y)/2)
         controlPoint2:NSMakePoint((x+nx)/2, ny)];

    return path;
}

@end
