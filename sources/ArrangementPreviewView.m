//
//  ArrangementPreviewView.m
//  iTerm
//
//  Created by George Nachman on 8/6/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "ArrangementPreviewView.h"
#import "PseudoTerminal.h"

@implementation ArrangementPreviewView

- (void)dealloc
{
    [arrangement_ release];
    [super dealloc];
}

- (void)setArrangement:(NSArray*)arrangement
{
    [arrangement_ autorelease];
    arrangement_ = [arrangement copy];
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor lightGrayColor] set];
    NSRectFill(dirtyRect);
    
    NSArray *screens = [NSScreen screens];
    CGFloat xMax = 0, yMax = 0;
    CGFloat xMin = 0, yMin = 0;
    for (NSScreen *screen in screens) {
        NSRect frame = [screen frame];
        CGFloat x = frame.origin.x + frame.size.width;
        CGFloat y = frame.origin.y + frame.size.height;
        xMax = MAX(xMax, x);
        yMax = MAX(yMax, y);
        xMin = MIN(xMin, frame.origin.x);
        yMin = MIN(yMin, frame.origin.y);
    }
    
    double xScale = [self frame].size.width / (xMax - xMin);
    double yScale = [self frame].size.height / (yMax - yMin);
    double scale = MIN(xScale, yScale);
    double yCorrection = MAX(0, ([self frame].size.height - (yMax - yMin) * scale) / 2);
    double xCorrection = MAX(0, ([self frame].size.width - (xMax - xMin) * scale) / 2);

    NSMutableArray *screenFrames = [NSMutableArray array];
    for (NSScreen *screen in screens) {
        NSRect frame = [screen frame];

        NSRect rect = NSMakeRect((frame.origin.x - xMin) * scale + xCorrection,
                                 (yMax - frame.size.height - frame.origin.y) * scale + yCorrection,
                                 frame.size.width * scale,
                                 frame.size.height * scale);
        [[NSColor blackColor] set];
        NSFrameRect(rect);
        
        rect.origin.x++;
        rect.origin.y++;
        rect.size.width -= 2;
        rect.size.height -= 2;
        [[NSColor colorWithCalibratedRed:0.270 green:0.545 blue:0.811 alpha:1] set];
        NSRectFill(rect);
        
        [screenFrames addObject:[NSValue valueWithRect:rect]];
    }
    
    for (NSDictionary* terminalArrangement in arrangement_) {
        [PseudoTerminal drawArrangementPreview:terminalArrangement screenFrames:screenFrames];
    }
}

- (BOOL)isFlipped
{
    return YES;
}

@end
