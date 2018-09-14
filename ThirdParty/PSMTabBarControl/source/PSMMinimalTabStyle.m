//
//  PSMMinimalTabStyle.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/10/18.
//

#import "PSMMinimalTabStyle.h"

@implementation NSColor(PSMMinimalTabStyle)

- (NSColor *)psm_nonSelectedColorWithDifference:(double)difference {
    NSColor *color = [self colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    CGFloat delta = -difference;
    CGFloat proposed = color.it_hspBrightness + delta;
    if (proposed < 0 || proposed > 1) {
        delta = -delta;
    }
    return [NSColor colorWithSRGBRed:color.redComponent + delta
                               green:color.greenComponent + delta
                                blue:color.blueComponent + delta
                               alpha:1];
    
}

- (NSColor *)psm_highlightedColor:(double)weight {
    NSColor *color = [self colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    const CGFloat amount = 0.1;
    CGFloat delta = amount;
    CGFloat proposed = color.it_hspBrightness + delta;
    if (proposed < 0 || proposed > 1) {
        delta = -delta;
    }
    delta *= weight;
    return [NSColor colorWithSRGBRed:color.redComponent + delta
                               green:color.greenComponent + delta
                                blue:color.blueComponent + delta
                               alpha:1];
    
}

@end

@implementation PSMMinimalTabStyle

- (NSString *)name {
    return @"Minimal";
}

- (NSColor *)tabBarColor {
    return [self.delegate minimalTabStyleBackgroundColor] ?: [NSColor blackColor];
}

- (BOOL)backgroundIsDark {
    CGFloat backgroundBrightness = self.tabBarColor.it_hspBrightness;
    return (backgroundBrightness < 0.5);
}

- (NSColor *)textColorDefaultSelected:(BOOL)selected {
    CGFloat backgroundBrightness = self.tabBarColor.it_hspBrightness;
    
    const CGFloat delta = selected ? 0.85 : 0.5;
    CGFloat value;
    if (backgroundBrightness < 0.5) {
        value = MIN(1, backgroundBrightness + delta);
    } else {
        value = MAX(0, backgroundBrightness - delta);
    }
    return [NSColor colorWithWhite:value alpha:1];
}

- (NSColor *)topLineColorSelected:(BOOL)selected {
    return self.tabBarColor;
}

- (NSColor *)bottomLineColorSelected:(BOOL)selected {
    return self.tabBarColor;
}

- (NSColor *)verticalLineColorSelected:(BOOL)selected {
    return [NSColor clearColor];
}

- (NSColor *)nonSelectedTabColor {
    const double difference = [[self.tabBar.delegate tabView:self.tabBar
                                               valueOfOption:PSMTabBarControlOptionMinimalStyleBackgroundColorDifference] doubleValue];
    return [self.tabBarColor psm_nonSelectedColorWithDifference:difference];
}

- (NSColor *)backgroundColorSelected:(BOOL)selected highlightAmount:(CGFloat)highlightAmount {
    NSColor *color;
    if (self.tabBar.cells.count > 1 && !selected) {
        color = [self nonSelectedTabColor];
    } else {
        color = self.tabBarColor;
    }
    if (selected || highlightAmount == 0) {
        return color;
    }
    color = [color psm_highlightedColor:highlightAmount];
    return color;
}

- (BOOL)useLightControls {
    return self.backgroundIsDark;
}

- (NSColor *)accessoryFillColor {
    return [NSColor colorWithCalibratedWhite:0.27 alpha:1.00];
}

- (NSColor *)accessoryStrokeColor {
    return [NSColor colorWithCalibratedWhite:0.12 alpha:1.00];
}

- (NSColor *)accessoryTextColor {
    return [self textColorDefaultSelected:YES];
}

- (void)drawPostHocDecorationsOnSelectedCell:(PSMTabBarCell *)cell
                               tabBarControl:(PSMTabBarControl *)bar {
    if (self.anyTabHasColor) {
        const CGFloat brightness = [self tabColorBrightness:cell];
        NSRect rect = NSInsetRect(cell.frame, 0, 0.5);
        NSBezierPath *path;
        
        NSColor *outerColor;
        NSColor *innerColor;
        const CGFloat alpha = [self.tabBar.window isKeyWindow] ? 0.5 : 0.3;
        if (brightness > 0.5) {
            outerColor = [NSColor colorWithWhite:1 alpha:alpha];
            innerColor = [NSColor colorWithWhite:0 alpha:alpha];
        } else {
            outerColor = [NSColor colorWithWhite:0 alpha:alpha];
            innerColor = [NSColor colorWithWhite:1 alpha:alpha];
        }
        
        [innerColor set];
        path = [NSBezierPath bezierPath];
        [path moveToPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect))];
        [path lineToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect))];
        [path setLineWidth:1];
        [path stroke];
        
        [outerColor set];
        rect = NSInsetRect(rect, 0, 1);
        path = [NSBezierPath bezierPath];
        [path moveToPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect))];
        [path lineToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect))];
        [path setLineWidth:1];
        [path stroke];
    }
}

- (NSColor *)outlineColor {
    CGFloat backgroundBrightness = self.tabBarColor.it_hspBrightness;
    
    const CGFloat delta = [[self.tabBar.delegate tabView:self.tabBar
                                           valueOfOption:PSMTabBarControlOptionColoredMinimalOutlineStrength] doubleValue];
    CGFloat value;
    if (backgroundBrightness < 0.5) {
        value = MIN(1, backgroundBrightness + delta);
    } else {
        value = MAX(0, backgroundBrightness - delta);
    }
    return [NSColor colorWithWhite:value alpha:1];
}

- (void)drawVerticalLineInFrame:(NSRect)rect x:(CGFloat)x {
}

- (void)drawHorizontalLineInFrame:(NSRect)rect y:(CGFloat)y {
}

- (void)drawBackgroundInRect:(NSRect)rect
                       color:(NSColor *)backgroundColor
                  horizontal:(BOOL)horizontal {
    if (self.orientation == PSMTabBarVerticalOrientation && [self.tabBar frame].size.width < 2) {
        return;
    }

    [super drawBackgroundInRect:rect color:backgroundColor horizontal:horizontal];

    [self drawStartInset];
    [self drawEndInset];
}

- (void)drawRect:(NSRect)rect withColor:(NSColor *)color {
    [color set];
    NSRectFill(rect);
}

- (BOOL)firstTabIsSelected {
    return self.firstVisibleCell.state == NSOnState;
}

- (BOOL)lastTabIsSelected {
    return self.lastVisibleCell.state == NSOnState;
}

- (void)drawStartInset {
    NSColor *color;
    if (self.firstTabIsSelected) {
        color = [self selectedTabColor];
    } else {
        color = [self nonSelectedTabColor];
    }
    [self drawRect:[self startInsetFrame] withColor:color];
}

- (void)drawEndInset {
    NSColor *color;
    PSMTabBarControl *bar = self.tabBar;
    const BOOL oneTab = (self.lastTabIsSelected && !self.firstTabIsSelected);
    const BOOL horizontal = (bar.orientation == PSMTabBarHorizontalOrientation);
    if ((horizontal && self.lastTabIsSelected) || (!horizontal && oneTab)) {
        color = [self selectedTabColor];
    } else {
        color = [self nonSelectedTabColor];
    }
    [self drawRect:[self endInsetFrame] withColor:color];
}

- (NSColor *)selectedTabColor {
    PSMTabBarCell *cell = self.selectedVisibleCell;
    if (!cell) {
        return self.tabBarColor;
    }
    PSMTabBarControl *bar = self.tabBar;
    BOOL selected = (bar.orientation == PSMTabBarHorizontalOrientation) || [self firstTabIsSelected];

    return [self effectiveBackgroundColorForTabWithTabColor:cell.tabColor
                                                   selected:selected
                                            highlightAmount:0
                                                     window:self.tabBar.window];
}

- (PSMTabBarCell *)selectedVisibleCell {
    PSMTabBarControl *bar = self.tabBar;
    for (PSMTabBarCell *cell in bar.cells.reverseObjectEnumerator) {
        if (!cell.isInOverflowMenu && cell.state == NSOnState) {
            return cell;
        }
    }
    return nil;

}

- (NSRect)startInsetFrame {
    PSMTabBarControl *bar = self.tabBar;
    if (bar.orientation == PSMTabBarHorizontalOrientation) {
        if (self.tabBar.cells.count == 0) {
            return NSZeroRect;
        }
        PSMTabBarCell *cell = self.tabBar.cells.firstObject;
        return NSMakeRect(0, 0, cell.frame.size.width, cell.frame.size.height);
    } else {
        return NSMakeRect(0, 0, NSWidth(self.tabBar.frame), self.tabBar.insets.top);
    }
}

- (NSRect)endInsetFrame {
    if (self.tabBar.cells.count == 0) {
        return NSZeroRect;
    }
    PSMTabBarCell *cell = self.lastVisibleCell;
    PSMTabBarControl *bar = self.tabBar;
    if (bar.orientation == PSMTabBarHorizontalOrientation) {
        return NSMakeRect(NSMaxX(cell.frame),
                          0,
                          self.tabBar.frame.size.width - NSMaxX(cell.frame),
                          cell.frame.size.height);
    } else {
        return NSMakeRect(0,
                          NSMaxY(cell.frame),
                          NSWidth(cell.frame),
                          NSHeight(self.tabBar.frame) - NSMaxY(cell.frame));
    }
}

- (PSMTabBarCell *)firstVisibleCell {
    PSMTabBarControl *bar = self.tabBar;
    return bar.cells.firstObject;
}

- (PSMTabBarCell *)lastVisibleCell {
    PSMTabBarControl *bar = self.tabBar;
    for (PSMTabBarCell *cell in bar.cells.reverseObjectEnumerator) {
        if (!cell.isInOverflowMenu) {
            return cell;
        }
    }
    return nil;
}

- (void)drawTabBar:(PSMTabBarControl *)bar
            inRect:(NSRect)rect
        horizontal:(BOOL)horizontal {
    [super drawTabBar:bar inRect:rect horizontal:horizontal];
    
    NSRect (^inset)(NSRect) = ^NSRect(NSRect rect) {
        rect.origin.x += 0.5;
        rect.origin.y += 0.5;
        rect.size.width -= 0.5;
        rect.size.height -= 1;
        return rect;
    };
    NSRect beforeRect;
    NSRect selectedRect = NSZeroRect;
    NSRect afterRect;
    NSInteger selectedIndex = -1;
    if (bar.orientation == PSMTabBarHorizontalOrientation) {
        beforeRect = inset(NSMakeRect(0,
                                      0,
                                      [self leftMarginForTabBarControl],
                                      bar.height));
        afterRect = inset(NSMakeRect(bar.frame.size.width - self.rightMarginForTabBarControl,
                                     0,
                                     self.rightMarginForTabBarControl,
                                     bar.height));
    } else {
        beforeRect = inset(NSMakeRect(0,
                                      0,
                                      bar.frame.size.width,
                                      self.topMarginForTabBarControl));
        PSMTabBarCell *lastCell = [self lastVisibleCell];
        afterRect = inset(NSMakeRect(0,
                                     NSMaxY(lastCell.frame),
                                     NSWidth(lastCell.frame),
                                     NSHeight(bar.frame) - NSMaxY(lastCell.frame)));
    }
    NSRect *current = &beforeRect;
    
    NSInteger i = 0;
    for (PSMTabBarCell *cell in [bar cells]) {
        if ([cell isInOverflowMenu]) {
            continue;
        }
        NSRect rect = inset(cell.frame);
        if (cell.state == NSOnState) {
            selectedIndex = i;
            current = &selectedRect;
        } else if (current == &selectedRect) {
            current = &afterRect;
        }
        *current = NSUnionRect(*current, rect);
        i++;
    }
    const BOOL lastIsSelected = (current == &selectedRect);

    NSBezierPath *path = [NSBezierPath bezierPath];
    if (bar.orientation == PSMTabBarHorizontalOrientation) {
        if (bar.tabLocation == PSMTab_TopTab) {
            if (selectedIndex == 0) {
                if (NSEqualRects(selectedRect, NSZeroRect)) {
                    [path moveToPoint:NSMakePoint(NSMaxX(afterRect), NSMaxY(afterRect))];
                } else {
                    [path moveToPoint:NSMakePoint(NSMaxX(selectedRect), NSMinY(selectedRect))];
                }
            } else {
                [path moveToPoint:NSMakePoint(NSMinX(beforeRect), NSMaxY(beforeRect))];
            }
            if (!NSEqualRects(selectedRect, NSZeroRect)) {
                if (selectedIndex > 0) {
                    [path lineToPoint:NSMakePoint(NSMinX(selectedRect), NSMaxY(selectedRect))];
                    [path lineToPoint:NSMakePoint(NSMinX(selectedRect), NSMinY(selectedRect))];
                    [path moveToPoint:NSMakePoint(NSMaxX(selectedRect), NSMinY(selectedRect))];
                }
                if (!lastIsSelected) {
                    [path lineToPoint:NSMakePoint(NSMaxX(selectedRect), NSMaxY(selectedRect))];
                }
            }
            if (!lastIsSelected) {
                [path lineToPoint:NSMakePoint(NSMaxX(afterRect), NSMaxY(afterRect))];
            }
        } else {
            // Bottom
            const BOOL leftTruncated = (beforeRect.size.width <= 0);
            if (leftTruncated) {
                [path moveToPoint:NSMakePoint(NSMaxX(selectedRect), NSMaxY(selectedRect))];
            } else {
                [path moveToPoint:NSMakePoint(NSMinX(beforeRect), NSMinY(beforeRect))];
            }
            if (!NSEqualRects(selectedRect, NSZeroRect)) {
                if (!leftTruncated) {
                    [path lineToPoint:NSMakePoint(NSMinX(selectedRect), NSMinY(selectedRect))];
                    [path lineToPoint:NSMakePoint(NSMinX(selectedRect), NSMaxY(selectedRect))];
                }
                if (!lastIsSelected) {
                    [path moveToPoint:NSMakePoint(NSMaxX(selectedRect), NSMaxY(selectedRect))];
                    [path lineToPoint:NSMakePoint(NSMaxX(selectedRect), NSMinY(selectedRect))];
                }
            }
            if (!lastIsSelected) {
                [path lineToPoint:NSMakePoint(NSMaxX(afterRect), NSMinY(afterRect))];
            }
        }
    } else {
        // Vertical orientation
        const BOOL firstIsSelected = [self firstTabIsSelected];
        if (firstIsSelected) {
            [path moveToPoint:NSMakePoint(NSMaxX(selectedRect), NSMaxY(selectedRect))];
        } else {
            [path moveToPoint:NSMakePoint(NSMaxX(beforeRect), NSMinY(beforeRect))];
        }
        if (!NSEqualRects(selectedRect, NSZeroRect)) {
            if (!firstIsSelected) {
                [path lineToPoint:NSMakePoint(NSMaxX(selectedRect), NSMinY(selectedRect))];
                [path lineToPoint:NSMakePoint(NSMinX(selectedRect), NSMinY(selectedRect))];
            }
            [path moveToPoint:NSMakePoint(NSMinX(selectedRect), NSMaxY(selectedRect))];
            [path lineToPoint:NSMakePoint(NSMaxX(selectedRect), NSMaxY(selectedRect))];
        }
        [path lineToPoint:NSMakePoint(NSMaxX(afterRect), NSMaxY(afterRect))];
    }
    [[self outlineColor] set];
    [path stroke];
}

- (NSColor *)cellBackgroundColorForTabColor:(NSColor *)tabColor
                                   selected:(BOOL)selected {
    CGFloat alpha = selected ? 1 : 0.5;
    if (![self.tabBar.window isKeyWindow]) {
        alpha *= 0.5;
    }
    return [tabColor colorWithAlphaComponent:alpha];
}


@end
