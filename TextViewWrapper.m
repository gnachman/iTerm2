//
//  TextViewWrapper.m
//  iTerm
//
//  Created by George Nachman on 11/14/10.
//  Copyright 2010 Georgetech. All rights reserved.
//

#import "TextViewWrapper.h"
#import "iTerm/PTYTextView.h"

@implementation TextViewWrapper

- (void)drawRect:(NSRect)rect
{
    [child_ drawBackground:NSMakeRect(0, 
                                      [[child_ enclosingScrollView] documentVisibleRect].origin.y - VMARGIN, 
                                      [self frame].size.width, 
                                      VMARGIN) 
                   toPoint:NSMakePoint(0, VMARGIN)];
}

- (void)addSubview:(PTYTextView*)child
{
    [super addSubview:child];
    child_ = child;
    [self setFrame:NSMakeRect(0, 0, [child frame].size.width, [child frame].size.height)];
    [child setFrameOrigin:NSMakePoint(0, 0)];
    [self setPostsFrameChangedNotifications:YES];
    [self setPostsBoundsChangedNotifications:YES];
}

- (NSRect)adjustScroll:(NSRect)proposedVisibleRect
{
    return [child_ adjustScroll:proposedVisibleRect];
}

- (BOOL)isFlipped
{
    return YES;
}

@end
