//
//  PasteView.m
//  iTerm
//
//  Created by George Nachman on 3/12/13.
//
//

#import "PasteView.h"
#import "PseudoTerminal.h"
#import "NSBezierPath+iTerm.h"

@implementation PasteView

- (void)resetCursorRects {
    NSCursor *arrow = [NSCursor arrowCursor];
    [self addCursorRect:[self bounds] cursor:arrow];
    [arrow setOnMouseEntered:YES];
}

- (BOOL)isFlipped {
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    NSBezierPath *path = [NSBezierPath smoothPathAroundBottomOfFrame:self.frame];
    PseudoTerminal* term = [[self window] windowController];
    if ([term isKindOfClass:[PseudoTerminal class]]) {
        [term fillPath:path];
    } else {
        [[NSColor windowBackgroundColor] set];
        [path fill];
    }

    [super drawRect:dirtyRect];
}

@end
