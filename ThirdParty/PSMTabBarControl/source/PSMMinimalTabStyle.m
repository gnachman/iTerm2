//
//  PSMMinimalTabStyle.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/10/18.
//

#import "PSMMinimalTabStyle.h"
#import "PSMOverflowPopUpButton.h"

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

- (NSRect)adjustedCellRect:(NSRect)rect generic:(NSRect)generic {
    return rect;
}

- (NSAppearance *)accessoryAppearance NS_AVAILABLE_MAC(10_14) {
    if (self.backgroundIsDark) {
        return [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    } else {
        return [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    }
}

- (NSColor *)tabBarColor {
    NSColor *minimalStyleColor = [self.delegate minimalTabStyleBackgroundColor];
    DLog(@"Computing tab bar color. delegate=%@ minimalStyleColor=%@", self.delegate, minimalStyleColor);
    if (PSMShouldExtendTransparencyIntoMinimalTabBar()) {
      const CGFloat alpha = [self alphaValue:[self backgroundAlphaValue:NO]
                                 opacifiedBy:0.3];
      NSColor *base = [self colorByDimmingColor:minimalStyleColor ?: [NSColor colorWithRed:0 green:0 blue:0 alpha:1]];
      return [base colorWithAlphaComponent:alpha];
  } else {
      return [self colorByDimmingColor:minimalStyleColor ?: [NSColor colorWithRed:0 green:0 blue:0 alpha:1]];
  }
}

- (BOOL)backgroundIsDark {
    CGFloat backgroundBrightness = self.tabBarColor.it_hspBrightness;
    return (backgroundBrightness < 0.5);
}

// For w in [0,1], move linearly between l (when w=0) and u (when w=1).
static CGFloat PSMWeightedAverage(CGFloat l, CGFloat u, CGFloat w) {
    return l * (1 - w) + u * w;
}

- (CGFloat)legibilityCorrectedAlpha:(CGFloat)baseValue {
    double legibility = [[self.tabBar.delegate tabView:self.tabBar valueOfOption:PSMTabBarControlOptionMinimalTextLegibilityAdjustment] doubleValue];
    if (legibility <= 0) {
        return baseValue;
    }
    return pow(baseValue, 1 / legibility);
}

- (NSColor *)textColorDefaultSelected:(BOOL)selected
                      backgroundColor:(NSColor *)backgroundColor
           windowIsMainAndAppIsActive:(BOOL)mainAndActive {
    const CGFloat backgroundBrightness =
    (backgroundColor ?
     backgroundColor.it_hspBrightness :
     [self backgroundColorSelected:selected highlightAmount:0].it_hspBrightness);

    if (!backgroundColor) {
        DLog(@"Choose background brightness from tab bar color of %@", self.tabBarColor);
    }
    const CGFloat delta = selected ? 0.85 : 0.5;
    CGFloat value;
    CGFloat extremity;
    if (backgroundBrightness < 0.5) {
        value = MIN(1, backgroundBrightness + delta);
        extremity = MAX(value, selected ? 1 : 0.9);
    } else {
        value = MAX(0, backgroundBrightness - delta);
        extremity = MIN(value, selected ? 0 : 0.3);
    }

    if (PSMShouldExtendTransparencyIntoMinimalTabBar()) {
        // Push value toward an extreme (black or white) as transparency increases.
        const CGFloat transparencyAlpha = [[self.tabBar.delegate tabView:self.tabBar
                                                           valueOfOption:PSMTabBarControlOptionMinimalBackgroundAlphaValue] doubleValue];
        if (transparencyAlpha == 1 && backgroundColor == nil) {
            NSColor *color = [self.tabBar.delegate tabView:self.tabBar valueOfOption:PSMTabBarControlOptionTextColor];
            if (selected) {
                return color;
            }
            return [color colorWithAlphaComponent:0.5];
        }
        value = PSMWeightedAverage(value, extremity, pow(1 - transparencyAlpha, 0.5));

        CGFloat minAlpha;  // For opaque windows
        CGFloat maxAlpha;  // For transparent windows
        if (mainAndActive) {
            minAlpha = 0.75;
            maxAlpha = 1.0;
        } else {
            minAlpha = 0.5;
            maxAlpha = 0.75;
        }
        const CGFloat alpha = [self legibilityCorrectedAlpha:PSMWeightedAverage(minAlpha, maxAlpha, 1 - transparencyAlpha)];
        DLog(@"selected=%@ backgroundColor=%@ backgroundBrightness=%@ delta=%@ value=%@", @(selected), backgroundColor, @(backgroundBrightness), @(delta), @(value));
        return [NSColor colorWithWhite:value alpha:alpha];
    } else {
        CGFloat alpha = 1;
        if (mainAndActive) {
            alpha = 0.75;
        } else {
            alpha = 0.5;
        }
        alpha = [self legibilityCorrectedAlpha:alpha];
        DLog(@"selected=%@ backgroundColor=%@ backgroundBrightness=%@ delta=%@ value=%@", @(selected), backgroundColor, @(backgroundBrightness), @(delta), @(value));
        return [NSColor colorWithWhite:value alpha:alpha];
    }
}

- (NSColor *)horizontalLineColor {
    if (PSMShouldExtendTransparencyIntoMinimalTabBar()) {
        NSColor *color = [self tabBarColor];
        const CGFloat transparencyAlpha = [[self.tabBar.delegate tabView:self.tabBar
                                                           valueOfOption:PSMTabBarControlOptionMinimalBackgroundAlphaValue] doubleValue];
        CGFloat alpha = color.alphaComponent * pow(transparencyAlpha, 0.5);
        return [color colorWithAlphaComponent:alpha];
    } else {
        return self.tabBarColor;
    }
}

- (NSColor *)topLineColorSelected:(BOOL)selected {
    return [self horizontalLineColor];
}

- (NSColor *)bottomLineColorSelected:(BOOL)selected {
    return [self horizontalLineColor];
}

- (NSColor *)verticalLineColorSelected:(BOOL)selected {
    return [NSColor clearColor];
}

- (CGFloat)alphaValue:(CGFloat)base opacifiedBy:(CGFloat)weight {
    return weight + (1 - weight) * base;
}

- (CGFloat)backgroundAlphaValue:(BOOL)selected {
    const CGFloat base = [[self.tabBar.delegate tabView:self.tabBar valueOfOption:PSMTabBarControlOptionMinimalBackgroundAlphaValue] doubleValue];
    if (selected) {
        return base;
    }
    if (base == 1) {
        return base;
    }
    return base * 0.9;
}

- (NSColor *)nonSelectedTabColor {
    if (PSMShouldExtendTransparencyIntoMinimalTabBar()) {
        const CGFloat transparencyAlpha = [[self.tabBar.delegate tabView:self.tabBar
                                                           valueOfOption:PSMTabBarControlOptionMinimalBackgroundAlphaValue] doubleValue];

        const double base = [[self.tabBar.delegate tabView:self.tabBar
                                             valueOfOption:PSMTabBarControlOptionMinimalStyleBackgroundColorDifference] doubleValue];
        const CGFloat difference = PSMWeightedAverage(0, base, pow(transparencyAlpha, 5));
        NSColor *color = [self colorByDimmingColor:[self.tabBarColor psm_nonSelectedColorWithDifference:difference]];
        const CGFloat alpha = [self backgroundAlphaValue:NO];
        if (alpha != 1) {
            color = [color colorWithAlphaComponent:alpha];
        }
        return color;
    } else {
        const double difference = [[self.tabBar.delegate tabView:self.tabBar
                                                   valueOfOption:PSMTabBarControlOptionMinimalStyleBackgroundColorDifference] doubleValue];
        return [self colorByDimmingColor:[self.tabBarColor psm_nonSelectedColorWithDifference:difference]];
    }
}

- (NSColor *)backgroundColorSelected:(BOOL)selected highlightAmount:(CGFloat)highlightAmount {
    NSColor *color;
    if (self.tabBar.cells.count > 1 && !selected) {
        color = [self nonSelectedTabColor];
    } else {
        color = self.tabBarColor;
    }
    const CGFloat alpha = [self backgroundAlphaValue:selected];
    if (PSMShouldExtendTransparencyIntoMinimalTabBar()) {
        if (alpha != 1) {
            color = [color colorWithAlphaComponent:alpha];
        }
    }
    if (selected || highlightAmount == 0) {
        return color;
    }
    color = [color psm_highlightedColor:highlightAmount];
    if (PSMShouldExtendTransparencyIntoMinimalTabBar()) {
        if (alpha != 1) {
            color = [color colorWithAlphaComponent:alpha];
        }
    }


    return color;
}

- (NSColor *)colorByDimmingColor:(NSColor *)color {
    const CGFloat dimmingAmount = [[self.tabBar.delegate tabView:self.tabBar
                                                   valueOfOption:PSMTabBarControlOptionDimmingAmount] doubleValue];
    if (dimmingAmount > 0) {
        CGFloat components[4];
        [color getComponents:components];
        for (int i = 0; i < 3; i++) {
            components[i] = dimmingAmount * 0.5 + (1 - dimmingAmount) * components[i];
        }
        return [NSColor colorWithColorSpace:color.colorSpace components:components count:4];
    }
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
    DLog(@"> begin Computing accessory color");
    NSColor *result = [self textColorDefaultSelected:YES backgroundColor:nil windowIsMainAndAppIsActive:self.windowIsMainAndAppIsActive];
    DLog(@"< end Computing accessory color");
    return result;
}

- (void)drawPostHocDecorationsOnSelectedCell:(PSMTabBarCell *)cell
                               tabBarControl:(PSMTabBarControl *)bar {
    if (self.anyTabHasColor) {
        const BOOL tabColorIsDark = ([self tabColorBrightness:cell] < 0.);
        NSRect containingFrame = cell.frame;
        const BOOL isHorizontal = bar.orientation == PSMTabBarHorizontalOrientation;
        if (isHorizontal) {
            if (bar.cells.firstObject == cell && self.treatLeftInsetAsPartOfFirstTab) {
                containingFrame = NSMakeRect(0, 0, NSMaxX(containingFrame), NSHeight(containingFrame));
            }
            containingFrame.origin.x += 0.5;
            containingFrame.size.width -= 0.5;
        }
        NSRect rect = NSInsetRect(containingFrame, 0, 0);
        NSBezierPath *path;
        
        NSColor *outerColor;
        NSColor *innerColor;
        const BOOL keyMainAndActive = self.windowIsMainAndAppIsActive;
        CGFloat prominence = [[self.tabBar.delegate tabView:self.tabBar valueOfOption:PSMTabBarControlOptionMinimalSelectedTabUnderlineProminence] doubleValue];
        const CGFloat alpha = (keyMainAndActive ? 0.75 : 0.5) * prominence;
        const BOOL tabBarColorIsDark = self.backgroundIsDark;
        if (tabColorIsDark != tabBarColorIsDark) {
            outerColor = [NSColor colorWithWhite:1 alpha:alpha];
            innerColor = [NSColor colorWithWhite:0 alpha:sqrt(alpha)];
        } else {
            outerColor = [NSColor colorWithWhite:0 alpha:sqrt(alpha)];
            innerColor = [NSColor colorWithWhite:1 alpha:alpha];
        }

        [outerColor set];
        rect = NSInsetRect(rect, 0, 1);
        path = [NSBezierPath bezierPath];
        [path moveToPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect))];
        [path lineToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect))];
        [path setLineWidth:2];
        [path stroke];

        [innerColor set];
        rect = NSInsetRect(rect, 0, 2);
        path = [NSBezierPath bezierPath];
        [path moveToPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect))];
        [path lineToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect))];
        [path setLineWidth:2];
        [path stroke];
    }
}

- (NSColor *)outlineColor {
    CGFloat backgroundBrightness = self.tabBarColor.it_hspBrightness;
    
    CGFloat alpha = [[self.tabBar.delegate tabView:self.tabBar
                                     valueOfOption:PSMTabBarControlOptionColoredMinimalOutlineStrength] doubleValue];
    if (PSMShouldExtendTransparencyIntoMinimalTabBar()) {
        const CGFloat transparencyAlpha = [[self.tabBar.delegate tabView:self.tabBar
                                                           valueOfOption:PSMTabBarControlOptionMinimalBackgroundAlphaValue] doubleValue];
        alpha *= pow(transparencyAlpha, 0.5);
    }
    CGFloat value;
    if (backgroundBrightness < 0.5) {
        value = 1;
    } else {
        value = 0;
    }
    return [NSColor colorWithWhite:value alpha:alpha];
}

- (void)drawVerticalLineInFrame:(NSRect)rect x:(CGFloat)x {
}

- (void)drawHorizontalLineInFrame:(NSRect)rect y:(CGFloat)y {
}

- (void)drawShadowForUnselectedTabInRect:(NSRect)backgroundRect {
}

- (CGFloat)tabBarHeight {
    return 0;
}
- (void)drawCellBackgroundSelected:(BOOL)selected
                            inRect:(NSRect)cellFrame
                      withTabColor:(NSColor *)tabColor
                   highlightAmount:(CGFloat)highlightAmount
                        horizontal:(BOOL)horizontal {
    const BOOL horizontalOrientation = self.tabBar.orientation == PSMTabBarHorizontalOrientation;
    NSEdgeInsets insets = NSEdgeInsetsZero;
    BOOL drawFrame = NO;
    if (!horizontalOrientation) {
        insets.right = 1;
        insets.left = 1;
    }
    if (highlightAmount > 0 && !selected) {
        if (horizontalOrientation) {
            drawFrame = YES;
            insets.left = 1.0;
            insets.right = 0.5;
            insets.bottom = 1.0;
            insets.top = 0.5;
        }
    }
    if (drawFrame) {
        [[self backgroundColorSelected:NO highlightAmount:0] set];
        NSFrameRect(cellFrame);
    }
    NSRect insetCellFrame = cellFrame;
    insetCellFrame.origin.x += insets.left;
    insetCellFrame.origin.y += insets.top;
    insetCellFrame.size.width -= (insets.left + insets.right);
    insetCellFrame.size.height -= (insets.top + insets.bottom);
    [super drawCellBackgroundSelected:selected inRect:insetCellFrame withTabColor:tabColor highlightAmount:highlightAmount horizontal:horizontal];
}

- (NSEdgeInsets)backgroundInsetsWithHorizontalOrientation:(BOOL)horizontal {
    return NSEdgeInsetsZero;
}

- (void)drawBackgroundInRect:(NSRect)rect
                       color:(NSColor *)backgroundColor
                  horizontal:(BOOL)horizontal {
    if (self.orientation == PSMTabBarVerticalOrientation && [self.tabBar frame].size.width < 2) {
        return;
    }

    PSMTabBarCell *selectedCell = [self selectedCellInTabBarControl:self.tabBar];
    const CGFloat highlightAmount = [selectedCell highlightAmount];
    [[self backgroundColorSelected:YES highlightAmount:highlightAmount] set];
    NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);

    [self drawStartInset];
    [self drawEndInset];
}

- (void)drawRect:(NSRect)rect withColor:(NSColor *)color {
    [color set];
    NSRectFill(rect);
}

- (BOOL)firstTabIsSelected {
    return self.firstVisibleCell.state == NSControlStateValueOn;
}

- (BOOL)lastTabIsSelected {
    return self.lastVisibleCell.state == NSControlStateValueOn;
}

- (BOOL)treatLeftInsetAsPartOfFirstTab {
    return [[self.tabBar.delegate tabView:self.tabBar
                            valueOfOption:PSMTabBarControlOptionMinimalStyleTreatLeftInsetAsPartOfFirstTab] boolValue];
}

- (void)drawStartInset {
    NSColor *color;
    if (self.firstTabIsSelected && self.treatLeftInsetAsPartOfFirstTab) {
        color = [self selectedTabColor];
    } else {
        color = [self nonSelectedTabColor];
    }
    [self drawRect:[self startInsetFrame] withColor:color];
}

- (void)drawEndInset {
    NSColor *color;
    PSMTabBarControl *bar = self.tabBar;
    PSMTabBarCell *cell = [self selectedCellInTabBarControl:bar];
    if (cell == nil || cell.isInOverflowMenu) {
        // Must be one of the overflow tabs
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
        if (!cell.isInOverflowMenu && cell.state == NSControlStateValueOn) {
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
        return NSMakeRect(0, 0, NSMinX(cell.frame), cell.frame.size.height);
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
        // Vertical tab bar
        if (!self.tabBar.overflowPopUpButton.isHidden) {
            // Popup button visible, so end inset equals its frame
            return NSMakeRect(0,
                              NSHeight(self.tabBar.frame) - NSHeight(cell.frame),
                              NSWidth(cell.frame),
                              NSHeight(cell.frame));
        }
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

- (PSMTabBarCell *)selectedCellInTabBarControl:(PSMTabBarControl *)bar {
    for (PSMTabBarCell *cell in bar.cells) {
        if (cell.state == NSControlStateValueOn) {
            return cell;
        }
    }
    return nil;
}

- (NSInteger)selectedIndex:(PSMTabBarControl *)bar {
    PSMTabBarCell *cell = [self selectedCellInTabBarControl:bar];
    if (cell.isInOverflowMenu) {
        return NSNotFound;
    }
    return [bar.cells indexOfObject:cell];
}

- (NSInteger)numberOfVisibleCells:(PSMTabBarControl *)bar {
    NSInteger i = 0;
    for (PSMTabBarCell *cell in bar.cells) {
        if (cell.isInOverflowMenu) {
            return i;
        }
        i++;
    }
    return i;
}

- (void)drawTabBar:(PSMTabBarControl *)bar
            inRect:(NSRect)rect
          clipRect:(NSRect)clipRect
        horizontal:(BOOL)horizontal
      withOverflow:(BOOL)withOverflow {
    [super drawTabBar:bar inRect:rect clipRect:clipRect horizontal:horizontal withOverflow:withOverflow];

    const BOOL horizontalOrientation = bar.orientation == PSMTabBarHorizontalOrientation;

    const NSInteger selectedIndex = [self selectedIndex:bar];
    const NSInteger numberOfVisibleCells = [self numberOfVisibleCells:bar];

    if (!horizontalOrientation) {
        if (bar.cells.count == 1) {
            [self drawOutlineAroundVerticalTabBarWithOneTab:bar];
        } else if (selectedIndex == 0) {
            [self drawOutlineAroundVerticalTabBarWithFirstTabSelected:bar];
        } else {
            [self drawOutlineAroundVerticalTabBarWithInteriorTabSelected:bar];
        }
    } else if (bar.tabLocation == PSMTab_TopTab) {
        if (bar.cells.count == 1) {
            [self drawOutlineAroundTopTabBarWithOneTab:bar];
        } else if (selectedIndex == 0) {
            [self drawOutlineAroundTopTabBarWithFirstTabSelected:bar];
        } else if (selectedIndex == numberOfVisibleCells - 1) {
            [self drawOutlineAroundTopTabBarWithLastTabSelected:bar];
        } else {
            [self drawOutlineAroundTopTabBarWithInteriorTabSelected:bar];
        }
    } else {
        if (bar.cells.count == 1) {
            [self drawOutlineAroundBottomTabBarWithOneTab:bar];
        } else if (selectedIndex == 0) {
            [self drawOutlineAroundBottomTabBarWithFirstTabSelected:bar];
        } else if (selectedIndex == numberOfVisibleCells - 1) {
            [self drawOutlineAroundBottomTabBarWithLastTabSelected:bar];
        } else {
            [self drawOutlineAroundBottomTabBarWithInteriorTabSelected:bar];
        }
    }
}

- (void)drawDividerBetweenTabBarAndContent:(NSRect)rect bar:(PSMTabBarControl *)bar {
}

- (BOOL)shouldDrawTopLineSelected:(BOOL)selected
                         attached:(BOOL)attached
                         position:(PSMTabPosition)position NS_AVAILABLE_MAC(10_16) {
    switch (position) {
        case PSMTab_BottomTab:
            return NO;

        case PSMTab_LeftTab:
        case PSMTab_TopTab:
            return [super shouldDrawTopLineSelected:selected attached:attached position:position];
    }
}

- (BOOL)willDrawSubtitle:(PSMCachedTitle *)subtitle {
    return subtitle && !subtitle.isEmpty;
}

- (CGFloat)verticalOffsetForTitleWhenSubtitlePresent {
    return -6;
}

- (CGFloat)verticalOffsetForSubtitle {
    return -1;
}

#pragma mark Draw outline around bottom tab bar

- (void)drawOutlineAroundBottomTabBarWithOneTab:(PSMTabBarControl *)bar {
}

- (void)drawOutlineAroundBottomTabBarWithFirstTabSelected:(PSMTabBarControl *)bar {
    [self drawOutlineAfterSelectedTabInBottomTabBar:bar];
}

- (void)drawOutlineAroundBottomTabBarWithLastTabSelected:(PSMTabBarControl *)bar {
    [self drawOutlineBeforeSelectedTabInBottomTabBar:bar];
    [self drawOutlineAfterSelectedTabInBottomTabBar:bar];
}

- (void)drawOutlineAroundBottomTabBarWithInteriorTabSelected:(PSMTabBarControl *)bar {
    [self drawOutlineBeforeSelectedTabInBottomTabBar:bar];
    [self drawOutlineAfterSelectedTabInBottomTabBar:bar];
}

- (void)drawOutlineAfterSelectedTabInBottomTabBar:(PSMTabBarControl *)bar {
    NSBezierPath *path = [NSBezierPath bezierPath];

    PSMTabBarCell *const cell = [self selectedCellInTabBarControl:bar];
    if (!cell || cell.isInOverflowMenu) {
        return;
    }
    const CGFloat left = NSMaxX(cell.frame) + 0.5;
    const CGFloat top = 0.5;
    const CGFloat right = NSMaxX(bar.frame) - 0.5;
    const CGFloat bottom = NSMaxY(cell.frame) - 0.5;

    [path moveToPoint:NSMakePoint(left, bottom)];
    [path lineToPoint:NSMakePoint(left, top)];
    [path lineToPoint:NSMakePoint(right, top)];

    [[self outlineColor] set];
    [path stroke];
}

- (void)drawOutlineBeforeSelectedTabInBottomTabBar:(PSMTabBarControl *)bar {
    NSBezierPath *path = [NSBezierPath bezierPath];

    PSMTabBarCell *const cell = [self selectedCellInTabBarControl:bar];
    NSRect frame = cell.frame;
    if (!cell || cell.isInOverflowMenu) {
        frame = NSMakeRect(NSMaxX(bar.frame) - [self rightMarginForTabBarControlWithOverflow:bar.lainOutWithOverflow
                                                                                addTabButton:bar.showAddTabButton],
                           0,
                           [self rightMarginForTabBarControlWithOverflow:bar.lainOutWithOverflow
                                                            addTabButton:bar.showAddTabButton],
                           NSHeight(bar.frame));
    }
    const CGFloat left = 0.5;
    const CGFloat top = 0.5;
    const CGFloat right = NSMinX(frame) - 0.5;
    const CGFloat bottom = NSMaxY(frame) - 0.5;

    [path moveToPoint:NSMakePoint(left, top)];
    [path lineToPoint:NSMakePoint(right, top)];
    [path lineToPoint:NSMakePoint(right, bottom)];

    [[self outlineColor] set];
    [path stroke];
}


#pragma mark Draw outline around top tab bar

- (void)drawOutlineAroundTopTabBarWithOneTab:(PSMTabBarControl *)bar {
    if (!self.treatLeftInsetAsPartOfFirstTab) {
        [self drawOutlineBeforeSelectedTabInTopTabBar:bar];
        [self drawOutlineAfterSelectedTabInTopTabBar:bar];
    }
}

- (void)drawOutlineAroundTopTabBarWithFirstTabSelected:(PSMTabBarControl *)bar {
    if (!self.treatLeftInsetAsPartOfFirstTab) {
        [self drawOutlineBeforeSelectedTabInTopTabBar:bar];
    }
    [self drawOutlineAfterSelectedTabInTopTabBar:bar];
}

- (void)drawOutlineAroundTopTabBarWithLastTabSelected:(PSMTabBarControl *)bar {
    [self drawOutlineBeforeSelectedTabInTopTabBar:bar];
    [self drawOutlineAfterSelectedTabInTopTabBar:bar];
}

- (void)drawOutlineAroundTopTabBarWithInteriorTabSelected:(PSMTabBarControl *)bar {
    [self drawOutlineBeforeSelectedTabInTopTabBar:bar];
    [self drawOutlineAfterSelectedTabInTopTabBar:bar];
}

- (void)drawOutlineAfterSelectedTabInTopTabBar:(PSMTabBarControl *)bar {
    NSBezierPath *path = [NSBezierPath bezierPath];

    PSMTabBarCell *const cell = [self selectedCellInTabBarControl:bar];
    if (!cell || cell.isInOverflowMenu) {
        return;
    }
    const CGFloat left = NSMaxX(cell.frame) + 0.5;
    const CGFloat top = 0.5;
    const CGFloat right = NSMaxX(bar.frame);
    const CGFloat bottom = NSMaxY(cell.frame) - 0.5;

    [path moveToPoint:NSMakePoint(left, top)];
    [path lineToPoint:NSMakePoint(left, bottom)];
    [path lineToPoint:NSMakePoint(right, bottom)];

    [[self outlineColor] set];
    [path stroke];
}

- (void)drawOutlineBeforeSelectedTabInTopTabBar:(PSMTabBarControl *)bar {
    NSBezierPath *path = [NSBezierPath bezierPath];

    PSMTabBarCell *const cell = [self selectedCellInTabBarControl:bar];
    NSRect frame = cell.frame;
    if (!cell || cell.isInOverflowMenu) {
        frame = NSMakeRect(NSMaxX(bar.frame) - [self rightMarginForTabBarControlWithOverflow:bar.lainOutWithOverflow
                                                                                addTabButton:bar.showAddTabButton],
                           0,
                           [self rightMarginForTabBarControlWithOverflow:bar.lainOutWithOverflow
                                                            addTabButton:bar.showAddTabButton],
                           NSHeight(bar.frame));
    }
    const CGFloat left = 0;
    const CGFloat top = 0.5;
    const CGFloat right = NSMinX(frame) - 0.5;
    const CGFloat bottom = NSMaxY(frame) - 0.5;

    [path moveToPoint:NSMakePoint(left, bottom)];
    [path lineToPoint:NSMakePoint(right, bottom)];
    [path lineToPoint:NSMakePoint(right, top)];

    [[self outlineColor] set];
    [path stroke];
}

#pragma mark Draw outline around vertical tab bar

- (void)drawOutlineAroundVerticalTabBarWithOneTab:(PSMTabBarControl *)bar {
    if (!self.treatLeftInsetAsPartOfFirstTab) {
        [self drawOutlineAboveSelectedTabInVerticalTabBar:bar];
    }
    [self drawOutlineUnderSelectedTabInVerticalTabBar:bar];
}

- (void)drawOutlineAroundVerticalTabBarWithFirstTabSelected:(PSMTabBarControl *)bar {
    if (!self.treatLeftInsetAsPartOfFirstTab) {
        [self drawOutlineAboveSelectedTabInVerticalTabBar:bar];
    }
    [self drawOutlineUnderSelectedTabInVerticalTabBar:bar];
}

- (void)drawOutlineAboveSelectedTabInVerticalTabBar:(PSMTabBarControl *)bar {
    NSBezierPath *path = [NSBezierPath bezierPath];

    PSMTabBarCell *const cell = [self selectedCellInTabBarControl:bar];
    NSRect frame = cell.frame;
    if (!cell || cell.isInOverflowMenu) {
        frame = NSMakeRect(0,
                           NSMaxY(bar.frame) - bar.height,
                           NSWidth(bar.frame),
                           bar.height);
    }
    const CGFloat top = 0.5;
    const CGFloat right = bar.frame.size.width - 0.5;
    const CGFloat bottom = NSMinY(frame) + 0.5;

    [path moveToPoint:NSMakePoint(right, top)];
    [path lineToPoint:NSMakePoint(right, bottom)];
    [path lineToPoint:NSMakePoint(0, bottom)];

    [[self outlineColor] set];
    [path stroke];
}

- (void)drawOutlineUnderSelectedTabInVerticalTabBar:(PSMTabBarControl *)bar {
    NSBezierPath *path = [NSBezierPath bezierPath];

    PSMTabBarCell *const cell = [self selectedCellInTabBarControl:bar];
    if (!cell || cell.isInOverflowMenu) {
        return;
    }
    const CGFloat top = NSMaxY(cell.frame) - 0.5;
    const CGFloat right = bar.frame.size.width - 0.5;
    const CGFloat bottom = NSMaxY(bar.frame) - 0.5;

    [path moveToPoint:NSMakePoint(0, top)];
    [path lineToPoint:NSMakePoint(right, top)];
    [path lineToPoint:NSMakePoint(right, bottom)];

    [[self outlineColor] set];
    [path stroke];
}

- (void)drawOutlineAroundVerticalTabBarWithInteriorTabSelected:(PSMTabBarControl *)bar {
    [self drawOutlineAboveSelectedTabInVerticalTabBar:bar];
    [self drawOutlineUnderSelectedTabInVerticalTabBar:bar];
}

- (NSColor *)cellBackgroundColorForTabColor:(NSColor *)tabColor
                                   selected:(BOOL)selected {
    CGFloat alpha = selected ? 1 : [[self.tabBar.delegate tabView:self.tabBar valueOfOption:PSMTabBarControlOptionMinimalNonSelectedColoredTabAlpha] doubleValue];
    const BOOL keyMainAndActive = self.windowIsMainAndAppIsActive;
    if (!keyMainAndActive) {
        alpha *= 0.5;
    }
    return [tabColor colorWithAlphaComponent:alpha];
}

@end
