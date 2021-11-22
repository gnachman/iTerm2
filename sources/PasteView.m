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

@implementation MinimalPasteView {
    NSVisualEffectView *_vev NS_AVAILABLE_MAC(10_14);
}

- (void)awakeFromNib {
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
    NSCursor *arrow = [NSCursor arrowCursor];
    [self addCursorRect:[self bounds] cursor:arrow];
}

- (void)drawRect:(NSRect)dirtyRect {
}

@end
