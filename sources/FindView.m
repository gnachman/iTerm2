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
#import "PseudoTerminal.h"
#import "NSBezierPath+iTerm.h"

@implementation FindView

- (BOOL)isFlipped
{
    return YES;
}

- (void)resetCursorRects
{
    [super resetCursorRects];
    NSRect frame = [self frame];
    [self addCursorRect:NSMakeRect(0, 0, frame.size.width, frame.size.height)
                 cursor:[NSCursor arrowCursor]];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p frame=%@ isHidden=%@ alpha=%@>",
            [self class], self, NSStringFromRect(self.frame), @(self.hidden), @(self.alphaValue)];
}

- (void)drawRect:(NSRect)dirtyRect {
    dirtyRect = NSIntersectionRect(dirtyRect, self.bounds);
    NSRect frame = [self frame];
    [[NSGraphicsContext currentContext] saveGraphicsState];
    [[NSGraphicsContext currentContext] setShouldAntialias:YES];
    NSBezierPath *path = [NSBezierPath smoothPathAroundBottomOfFrame:frame];

    PseudoTerminal* term = [[self window] windowController];
    if ([term isKindOfClass:[PseudoTerminal class]]) {
      [term fillPath:path];
    } else {
      [[NSColor windowBackgroundColor] set];
      [path fill];
    }
    [[NSGraphicsContext currentContext] restoreGraphicsState];
}

@end

@implementation MinimalFindView {
    NSVisualEffectView *_vev NS_AVAILABLE_MAC(10_14);
    IBOutlet NSButton *_closeButton;
}

- (void)awakeFromNib {
    _closeButton.image.template = YES;
    _closeButton.alternateImage.template = YES;
    _vev = [[NSVisualEffectView alloc] initWithFrame:NSInsetRect(self.bounds, 9, 9)];
    _vev.wantsLayer = YES;
    _vev.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    _vev.material = NSVisualEffectMaterialSheet;
    _vev.state = NSVisualEffectStateActive;
    _vev.layer.cornerRadius = 6;
    _vev.layer.borderColor = [[NSColor grayColor] CGColor];
    _vev.layer.borderWidth = 1;
    [self addSubview:_vev positioned:NSWindowBelow relativeTo:self.subviews.firstObject];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    _vev.frame = NSInsetRect(self.bounds, 9, 9);
}

- (void)resetCursorRects {
    [super resetCursorRects];
    NSRect frame = [self frame];
    [self addCursorRect:NSMakeRect(0, 0, frame.size.width, frame.size.height)
                 cursor:[NSCursor arrowCursor]];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p frame=%@ isHidden=%@ alpha=%@>",
            [self class], self, NSStringFromRect(self.frame), @(self.hidden), @(self.alphaValue)];
}

- (void)drawRect:(NSRect)dirtyRect {
}

@end

