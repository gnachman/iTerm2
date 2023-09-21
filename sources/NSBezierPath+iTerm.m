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
    NSBezierPath* path = [[[NSBezierPath alloc] init] autorelease];
    [path setLineWidth:1];
    float radius = 4;
    float height = frame.size.height - 1;
    float width = frame.size.width - 1;
    float x = 0.5;
    float y = MIN(0, height - 2*radius);
    float nx, ny;
    [path moveToPoint:NSMakePoint(x, y)];
    nx = x+radius;
    ny = y+radius+0.5;  // Add an extra 0.5 to get on the pixel grid.
    [path curveToPoint:NSMakePoint(nx, ny)
         controlPoint1:NSMakePoint((nx+x)/2, y)
         controlPoint2:NSMakePoint(nx, (ny+y)/2)];
    y = ny;
    ny = y + MAX(0, height - 2*radius);
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
    ny = y - MAX(0, height - 2*radius);
    [path lineToPoint:NSMakePoint(nx, ny)];
    x = nx; y = ny;
    nx = x + radius;
    ny = y - radius - 0.5; // Subtract 0.5 to return to the "true" origin of the frame
    [path curveToPoint:NSMakePoint(nx, ny)
         controlPoint1:NSMakePoint(x, (ny+y)/2)
         controlPoint2:NSMakePoint((x+nx)/2, ny)];

    return path;
}

- (CGPathRef)iterm_CGPath {
    return [self iterm_cgPathOpen:NO];
}

- (CGPathRef)iterm_openCGPath {
    return [self iterm_cgPathOpen:YES];
}

- (CGPathRef)iterm_cgPathOpen:(BOOL)open {
    if (self.elementCount == 0) {
        return NULL;
    }

    CGMutablePathRef path = CGPathCreateMutable();
    BOOL closed = YES;

    for (NSInteger i = 0; i < self.elementCount; i++) {
        NSPoint associatedPoints[3];
        NSBezierPathElement element = [self elementAtIndex:i associatedPoints:associatedPoints];
        switch (element) {
            case NSMoveToBezierPathElement:
                CGPathMoveToPoint(path, NULL, associatedPoints[0].x, associatedPoints[0].y);
                break;

            case NSLineToBezierPathElement:
                closed = NO;
                CGPathAddLineToPoint(path, NULL, associatedPoints[0].x, associatedPoints[0].y);
                break;

            case NSCurveToBezierPathElement:
                closed = NO;
                CGPathAddCurveToPoint(path, NULL,
                                      associatedPoints[0].x, associatedPoints[0].y,
                                      associatedPoints[1].x, associatedPoints[1].y,
                                      associatedPoints[2].x, associatedPoints[2].y);
                break;

            case NSClosePathBezierPathElement:
                closed = YES;
                if (!open) {
                    CGPathCloseSubpath(path);
                }
                break;
            case NSBezierPathElementQuadraticCurveTo:
                closed = NO;
                CGPathAddQuadCurveToPoint(path, NULL, associatedPoints[0].x, associatedPoints[0].y, associatedPoints[1].x, associatedPoints[1].y);
                break;
        }
    }

    if (!closed && !open) {
        CGPathCloseSubpath(path);
    }

    CGPathRef theCopy = CGPathCreateCopy(path);
    CGPathRelease(path);

    return (CGPathRef)[(id)theCopy autorelease];
}

@end
