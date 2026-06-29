//
//  iTermStatusBarView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/28/18.
//

#import "iTermStatusBarView.h"
#import "PTYWindow.h"
#import "iTermPreferenceDidChangeNotification.h"
#import "iTermPreferences.h"

@implementation iTermStatusBarView {
    // A 1pt NSBox separator hugging the edge that abuts the terminal content.
    // Using NSBox (rather than drawing a color in -drawRect:) guarantees the
    // line matches the workgroup toolbar's separators in every theme.
    NSBox *_edgeSeparator;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        // The status bar position pref decides which edge the separator hugs.
        // The hosting container is reused (only repositioned) when the position
        // changes, so a layout pass is not guaranteed; react to the change here.
        __weak __typeof(self) weakSelf = self;
        [iTermPreferenceDidChangeNotification subscribe:self
                                                  block:^(iTermPreferenceDidChangeNotification * _Nonnull notification) {
            if ([notification.key isEqualToString:kPreferenceKeyStatusBarPosition]) {
                [weakSelf positionEdgeSeparator];
            }
        }];
    }
    return self;
}

- (CGFloat)drawSeparatorsInRect:(NSRect)dirtyRect {
    CGFloat x = 1;
    const CGFloat separatorTopBottomInset = 3;

    if (self.separatorColor) {
        [self.separatorColor set];
        for (NSNumber *offsetNumber in _separatorOffsets) {
            CGFloat offset = offsetNumber.doubleValue;
            NSRect rect = NSMakeRect(offset, separatorTopBottomInset, 1, dirtyRect.size.height - separatorTopBottomInset * 2);
            NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);
            x = offset + 1;
        }
    }
    return x;
}

- (void)drawBackgroundColorsInRect:(NSRect)dirtyRect {
    CGFloat lastX = 0;
    CGFloat x = 0;
    for (iTermTuple<NSColor *, NSNumber *> *tuple in self.backgroundColors) {
        if (tuple == self.backgroundColors.lastObject) {
            x = self.bounds.size.width;
        } else {
            x = tuple.secondObject.doubleValue;
        }
        if (tuple.firstObject) {
            [tuple.firstObject set];
            NSRectFill(NSMakeRect(lastX,
                                  self.verticalOffset,
                                  x - lastX,
                                  dirtyRect.size.height - self.verticalOffset));
        }
        lastX = x;
    }
}

- (void)setDrawsSeparatorBetweenStatusBarAndTerminal:(BOOL)value {
    _drawsSeparatorBetweenStatusBarAndTerminal = value;
    if (value && !_edgeSeparator) {
        _edgeSeparator = [[NSBox alloc] initWithFrame:NSZeroRect];
        [self addSubview:_edgeSeparator];
        [self updateEdgeSeparatorColor];
    }
    _edgeSeparator.hidden = !value;
    [self setNeedsLayout:YES];
}

- (void)setEdgeSeparatorColor:(NSColor *)edgeSeparatorColor {
    _edgeSeparatorColor = edgeSeparatorColor;
    [self updateEdgeSeparatorColor];
}

- (void)updateEdgeSeparatorColor {
    if (!_edgeSeparator) {
        return;
    }
    if (_edgeSeparatorColor) {
        // The minimal theme's separator color is not the system separator
        // color, so fill a custom box rather than using NSBoxSeparator.
        _edgeSeparator.boxType = NSBoxCustom;
        _edgeSeparator.titlePosition = NSNoTitle;
        _edgeSeparator.borderWidth = 0;
        _edgeSeparator.borderColor = [NSColor clearColor];
        _edgeSeparator.fillColor = _edgeSeparatorColor;
    } else {
        // NSBoxSeparator renders the system separator color, which matches the
        // workgroup toolbar's dividers in the non-minimal themes.
        _edgeSeparator.boxType = NSBoxSeparator;
    }
}

- (void)viewDidMoveToSuperview {
    [super viewDidMoveToSuperview];
    // The single status bar view controller is reparented between the top and
    // bottom containers when the status bar position changes. Re-lay out so the
    // separator moves to the edge that now abuts the terminal content.
    [self setNeedsLayout:YES];
}

- (void)layout {
    [super layout];
    [self positionEdgeSeparator];
}

- (void)positionEdgeSeparator {
    if (!_edgeSeparator || _edgeSeparator.hidden) {
        return;
    }
    // Keep the separator in front of the component views so it is never covered.
    if (self.subviews.lastObject != _edgeSeparator) {
        [self addSubview:_edgeSeparator positioned:NSWindowAbove relativeTo:nil];
    }

    const CGFloat thickness = 1;
    // The separator hugs the edge that abuts the terminal content. The view is
    // not flipped, so y=0 is the bottom edge. When the status bar is on top the
    // terminal is below it (bottom edge); when on the bottom the terminal is
    // above it (top edge).
    CGFloat boundary = 0;
    switch ((iTermStatusBarPosition)[iTermPreferences unsignedIntegerForKey:kPreferenceKeyStatusBarPosition]) {
        case iTermStatusBarPositionTop:
            boundary = 0;
            break;
        case iTermStatusBarPositionBottom:
            boundary = NSHeight(self.bounds);
            break;
    }
    // NSBoxSeparator draws its line at the box's vertical center, so center the
    // box on the boundary. This puts the line exactly on the status bar/terminal
    // edge instead of inset into the bar (which would leave a half-point gap),
    // without changing the status bar's height.
    _edgeSeparator.frame = NSMakeRect(0, boundary - thickness / 2.0, NSWidth(self.bounds), thickness);
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    dirtyRect = NSIntersectionRect(dirtyRect, self.bounds);

    if (self.backgroundColor) {
        [self.backgroundColor set];
        NSRectFill(dirtyRect);
    }

    [self drawBackgroundColorsInRect:dirtyRect];
    [self drawSeparatorsInRect:dirtyRect];
}

@end
