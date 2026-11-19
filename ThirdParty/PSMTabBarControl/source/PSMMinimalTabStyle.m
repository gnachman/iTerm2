//
//  PSMMinimalTabStyle.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/10/18.
//

#import "PSMMinimalTabStyle.h"
#import "NSColor+PSM.h"
#import "PSMOverflowPopUpButton.h"
#import "PSMTabBarCell.h"
#import "PSMTabGroup.h"
#import "iTermAdvancedSettingsModel.h"

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

#pragma mark - Tab groups

// Minimal draws tab groups quietly, to match the rest of the bar: the group's
// name sits in a short tinted capsule (not a full-height solid block), and a
// thin strip in the full group color runs along the bar edge under the chip and
// every member tab to show the group's extent. A collapsed group is a capsule
// with the name, a member-count badge, and a right-pointing chevron.
static const CGFloat kPSMMinimalGroupChipMargin = 6;      // between the chip cell edge and the capsule
static const CGFloat kPSMMinimalGroupChipPad = 9;         // horizontal padding inside the capsule
static const CGFloat kPSMMinimalGroupChipHeight = 22;     // capsule height (clamped to the cell)
static const CGFloat kPSMMinimalGroupDotSize = 10;        // an unnamed expanded group's dot
static const CGFloat kPSMMinimalGroupBadgeGap = 6;        // name to count badge
static const CGFloat kPSMMinimalGroupChevronGap = 5;      // badge to chevron
static const CGFloat kPSMMinimalGroupChevronWidth = 5;
static const CGFloat kPSMMinimalGroupChevronTrailPad = 8; // chevron to the capsule's trailing edge
static const CGFloat kPSMMinimalGroupStripWidth = 2;      // membership strip thickness
static const CGFloat kPSMMinimalGroupStripGap = 1;        // between a parent's strip and a sub-group's
static const CGFloat kPSMMinimalGroupFontSize = 11;       // matches the default tab title size
static const CGFloat kPSMMinimalGroupChipFillFraction = 0.22;
static const CGFloat kPSMMinimalGroupBadgeFillFraction = 0.40;
static const CGFloat kPSMMinimalGroupLabelFraction = 0.45;
static const CGFloat kPSMMinimalGroupWashAlpha = 0.06;
static const CGFloat kPSMMinimalGroupMinimumContrast = 4.5;

// WCAG relative luminance of an sRGB color.
static CGFloat PSMMinimalRelativeLuminance(NSColor *color) {
    NSColor *srgb = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    if (!srgb) {
        return 0.5;
    }
    CGFloat (^linear)(CGFloat) = ^CGFloat(CGFloat c) {
        return (c <= 0.03928) ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
    };
    return 0.2126 * linear(srgb.redComponent) +
           0.7152 * linear(srgb.greenComponent) +
           0.0722 * linear(srgb.blueComponent);
}

static CGFloat PSMMinimalContrastRatio(NSColor *a, NSColor *b) {
    const CGFloat la = PSMMinimalRelativeLuminance(a);
    const CGFloat lb = PSMMinimalRelativeLuminance(b);
    return (MAX(la, lb) + 0.05) / (MIN(la, lb) + 0.05);
}

- (NSFont *)minimalGroupNameFont {
    return [NSFont systemFontOfSize:kPSMMinimalGroupFontSize weight:NSFontWeightMedium];
}

- (NSFont *)minimalGroupBadgeFont {
    return [NSFont monospacedDigitSystemFontOfSize:kPSMMinimalGroupFontSize - 1 weight:NSFontWeightMedium];
}

- (CGFloat)minimalGroupTextWidth:(NSString *)text font:(NSFont *)font {
    return ceil([(text ?: @"") sizeWithAttributes:@{ NSFontAttributeName: font }].width);
}

- (NSSize)minimalGroupBadgeSizeForCount:(NSInteger)count {
    NSFont *font = [self minimalGroupBadgeFont];
    const CGFloat height = ceil(font.ascender - font.descender) + 2;
    const CGFloat width = MAX(height, [self minimalGroupTextWidth:[@(count) stringValue] font:font] + 8);
    return NSMakeSize(width, height);
}

// Width of everything after the name in a collapsed capsule: the badge, the
// chevron, and the trailing padding.
- (CGFloat)minimalCollapsedTrailingWidthForCount:(NSInteger)count {
    return [self minimalGroupBadgeSizeForCount:count].width +
        kPSMMinimalGroupChevronGap + kPSMMinimalGroupChevronWidth + kPSMMinimalGroupChevronTrailPad;
}

- (CGFloat)tabGroupChipCellWidthForName:(NSString *)name {
    if (name.length == 0) {
        return kPSMMinimalGroupChipMargin * 2 + kPSMMinimalGroupDotSize;
    }
    const CGFloat textWidth = [self minimalGroupTextWidth:name font:[self minimalGroupNameFont]];
    return kPSMMinimalGroupChipMargin * 2 + kPSMMinimalGroupChipPad * 2 + textWidth;
}

- (CGFloat)tabGroupCollapsedChipCellWidthForName:(NSString *)name
                                     memberCount:(NSInteger)count
                                          nested:(BOOL)nested {
    CGFloat capsule = [self minimalCollapsedTrailingWidthForCount:count];
    if (name.length > 0) {
        capsule += kPSMMinimalGroupChipPad +
            [self minimalGroupTextWidth:name font:[self minimalGroupNameFont]] +
            kPSMMinimalGroupBadgeGap;
    } else {
        capsule += kPSMMinimalGroupChevronTrailPad;
    }
    return kPSMMinimalGroupChipMargin * 2 + capsule;
}

// The bar color without transparency, used as the base that group colors are
// mixed into so tints hold up in light mode and with custom tab colors.
- (NSColor *)minimalOpaqueBarColor {
    NSColor *bar = [[self tabBarColor] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    return [bar colorWithAlphaComponent:1] ?: [NSColor blackColor];
}

- (NSColor *)minimalGroupForegroundColor {
    return self.backgroundIsDark ? [NSColor whiteColor] : [NSColor blackColor];
}

- (NSColor *)minimalTintOfGroupColor:(NSColor *)groupColor fraction:(CGFloat)fraction {
    NSColor *base = [self minimalOpaqueBarColor];
    NSColor *group = [groupColor colorUsingColorSpace:[NSColorSpace sRGBColorSpace]] ?: groupColor;
    return [base blendedColorWithFraction:fraction ofColor:group] ?: base;
}

// The group color pushed toward the foreground, then further until it reaches a
// minimum contrast against `fill`.
- (NSColor *)minimalGroupLabelColorForGroupColor:(NSColor *)groupColor fill:(NSColor *)fill {
    NSColor *fg = [self minimalGroupForegroundColor];
    NSColor *group = [groupColor colorUsingColorSpace:[NSColorSpace sRGBColorSpace]] ?: groupColor;
    CGFloat fraction = kPSMMinimalGroupLabelFraction;
    NSColor *label = [group blendedColorWithFraction:fraction ofColor:fg] ?: fg;
    while (fraction < 1 && PSMMinimalContrastRatio(label, fill) < kPSMMinimalGroupMinimumContrast) {
        fraction = MIN(1, fraction + 0.1);
        label = [group blendedColorWithFraction:fraction ofColor:fg] ?: fg;
    }
    return label;
}

// Strips stack inward from the bar's outer content edge so a sub-group's strip
// sits beside its parent's rather than on top of it.
- (CGFloat)minimalStripDepthForChip:(PSMTabBarCell *)chip {
    const BOOL nested = chip.tabGroupParentIdentifier.length > 0;
    return nested ? kPSMMinimalGroupStripWidth + kPSMMinimalGroupStripGap : 0;
}

// The membership strip for a run spanning `extent` (chip through last member).
// On a horizontal bar it lies along the edge facing the content, just inside the
// 1pt outline Minimal draws there. On a vertical bar it lies along the bar's
// outer edge.
- (NSRect)minimalStripRectForExtent:(NSRect)extent depth:(CGFloat)depth bar:(PSMTabBarControl *)bar {
    const CGFloat w = kPSMMinimalGroupStripWidth;
    if (bar.orientation == PSMTabBarHorizontalOrientation) {
        if (bar.tabLocation == PSMTab_BottomTab) {
            return NSMakeRect(NSMinX(extent), NSMinY(extent) + 1 + depth, NSWidth(extent), w);
        }
        return NSMakeRect(NSMinX(extent), NSMaxY(extent) - 1 - depth - w, NSWidth(extent), w);
    }
    if (bar.tabLocation == PSMTab_RightTab) {
        return NSMakeRect(NSMaxX(extent) - depth - w, NSMinY(extent), w, NSHeight(extent));
    }
    return NSMakeRect(NSMinX(extent) + depth, NSMinY(extent), w, NSHeight(extent));
}

// The capsule's rect within a chip cell, `width` wide (clamped to the cell).
- (NSRect)minimalCapsuleRectInChipFrame:(NSRect)chipFrame width:(CGFloat)width bar:(PSMTabBarControl *)bar {
    CGFloat leading = kPSMMinimalGroupChipMargin;
    CGFloat trailing = kPSMMinimalGroupChipMargin;
    if (bar.orientation != PSMTabBarHorizontalOrientation) {
        // Clear the strips along the outer edge.
        const CGFloat strips = kPSMMinimalGroupStripWidth * 2 + kPSMMinimalGroupStripGap;
        if (bar.tabLocation == PSMTab_RightTab) {
            trailing += strips;
        } else {
            leading += strips;
        }
    }
    const CGFloat available = MAX(0, NSWidth(chipFrame) - leading - trailing);
    const CGFloat height = MIN(kPSMMinimalGroupChipHeight, MAX(0, NSHeight(chipFrame) - 8));
    return NSIntegralRect(NSMakeRect(NSMinX(chipFrame) + leading,
                                     NSMidY(chipFrame) - height / 2.0,
                                     MIN(width, available),
                                     height));
}

// Positions the name the way PSMYosemiteTabStyle positions a tab title
// (floor-centered on the cell using the attributed string's bounding height) so
// the two share a baseline.
- (void)drawMinimalGroupName:(NSString *)name
                      inRect:(NSRect)rect
                   cellFrame:(NSRect)cellFrame
                       color:(NSColor *)color {
    if (name.length == 0 || NSWidth(rect) <= 0) {
        return;
    }
    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.alignment = NSTextAlignmentLeft;
    para.lineBreakMode = NSLineBreakByTruncatingTail;
    NSAttributedString *attributed =
        [[NSAttributedString alloc] initWithString:name
                                        attributes:@{ NSFontAttributeName: [self minimalGroupNameFont],
                                                      NSForegroundColorAttributeName: color,
                                                      NSParagraphStyleAttributeName: para }];
    const CGFloat height = [attributed boundingRectWithSize:rect.size options:0].size.height;
    [attributed drawInRect:NSMakeRect(NSMinX(rect),
                                      NSMinY(cellFrame) + floor((NSHeight(cellFrame) - height) / 2.0),
                                      NSWidth(rect),
                                      height)];
}

- (void)drawTabGroupRunDecorationsForTabBar:(PSMTabBarControl *)bar clipRect:(NSRect)clipRect {
    if (bar.suppressTabGroupRunDecoration || NSIsEmptyRect(clipRect)) {
        return;
    }
    PSMTabBarCell *selected = [self selectedCellInTabBarControl:bar];
    [bar enumerateTabGroupRunsWithRect:nil
                                 block:^(PSMTabBarCell *chip,
                                         NSRect tabsRect,
                                         PSMTabBarCell *firstTab,
                                         NSString *gid) {
        [self drawMinimalTabGroupRunWithChip:chip
                                    tabsRect:tabsRect
                                     groupID:gid
                                    selected:selected
                                       inBar:bar];
    }];
    NSString *dropTargetGID = [bar collapsedTabGroupDropTargetIdentifier];
    [bar enumerateCollapsedTabGroupChipsWithBlock:^(PSMTabBarCell *chip,
                                                    NSInteger memberCount,
                                                    NSString *gid) {
        [self drawMinimalCollapsedTabGroupChip:chip
                                   memberCount:memberCount
                                       groupID:gid
                                         inBar:bar
                                  isDropTarget:[gid isEqualToString:dropTargetGID]];
    }];
}

- (void)drawMinimalTabGroupRunWithChip:(PSMTabBarCell *)chip
                              tabsRect:(NSRect)tabsRect
                               groupID:(NSString *)gid
                              selected:(PSMTabBarCell *)selected
                                 inBar:(PSMTabBarControl *)bar {
    id<PSMTabGroup> group = [bar.tabGroupDataSource tabGroupWithIdentifier:gid];
    NSColor *groupColor = group.color ?: [NSColor systemBlueColor];
    NSString *name = group.name ?: @"";
    const BOOL horizontal = (bar.orientation == PSMTabBarHorizontalOrientation);
    const NSRect chipFrame = chip.frame;
    const NSRect extent = horizontal
        ? NSMakeRect(NSMinX(chipFrame), NSMinY(tabsRect),
                     MAX(0, NSMaxX(tabsRect) - NSMinX(chipFrame)), NSHeight(tabsRect))
        : NSMakeRect(NSMinX(tabsRect), NSMinY(chipFrame),
                     NSWidth(tabsRect), MAX(0, NSMaxY(tabsRect) - NSMinY(chipFrame)));

    // A faint wash over the member tabs, leaving the selected tab untouched so
    // it keeps reading as one surface with the content.
    [NSGraphicsContext saveGraphicsState];
    NSBezierPath *washClip = [NSBezierPath bezierPathWithRect:tabsRect];
    if (selected && !selected.isInOverflowMenu && NSIntersectsRect(selected.frame, tabsRect)) {
        [washClip appendBezierPathWithRect:selected.frame];
        washClip.windingRule = NSWindingRuleEvenOdd;
    }
    [washClip addClip];
    [[groupColor colorWithAlphaComponent:kPSMMinimalGroupWashAlpha] set];
    NSRectFillUsingOperation(tabsRect, NSCompositingOperationSourceOver);
    [NSGraphicsContext restoreGraphicsState];

    // The chip: a tinted capsule with the name, or a dot when unnamed.
    NSRect capsule;
    if (name.length == 0) {
        capsule = [self minimalCapsuleRectInChipFrame:chipFrame width:kPSMMinimalGroupDotSize bar:bar];
        const CGFloat d = MIN(kPSMMinimalGroupDotSize, MIN(NSWidth(capsule), NSHeight(capsule)));
        if (d > 0) {
            NSRect dot = NSMakeRect(NSMinX(capsule), NSMidY(capsule) - d / 2.0, d, d);
            [groupColor set];
            [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
        }
    } else {
        const CGFloat textWidth = [self minimalGroupTextWidth:name font:[self minimalGroupNameFont]];
        capsule = [self minimalCapsuleRectInChipFrame:chipFrame
                                                width:textWidth + kPSMMinimalGroupChipPad * 2
                                                  bar:bar];
        if (NSWidth(capsule) > 0 && NSHeight(capsule) > 0) {
            NSColor *fill = [self minimalTintOfGroupColor:groupColor fraction:kPSMMinimalGroupChipFillFraction];
            [fill set];
            const CGFloat radius = NSHeight(capsule) / 2.0;
            [[NSBezierPath bezierPathWithRoundedRect:capsule xRadius:radius yRadius:radius] fill];
            [self drawMinimalGroupName:name
                                inRect:NSInsetRect(capsule, kPSMMinimalGroupChipPad, 0)
                             cellFrame:chipFrame
                                 color:[self minimalGroupLabelColorForGroupColor:groupColor fill:fill]];
        }
    }

    // The membership strip, from the chip cell's leading edge to the end of the
    // last member.
    [groupColor set];
    NSRectFill([self minimalStripRectForExtent:extent depth:[self minimalStripDepthForChip:chip] bar:bar]);
}

- (void)drawMinimalCollapsedTabGroupChip:(PSMTabBarCell *)chip
                             memberCount:(NSInteger)count
                                 groupID:(NSString *)gid
                                   inBar:(PSMTabBarControl *)bar
                            isDropTarget:(BOOL)isDropTarget {
    id<PSMTabGroup> group = [bar.tabGroupDataSource tabGroupWithIdentifier:gid];
    NSColor *groupColor = group.color ?: [NSColor systemBlueColor];
    NSString *name = group.name ?: @"";
    NSFont *nameFont = [self minimalGroupNameFont];
    const CGFloat trailing = [self minimalCollapsedTrailingWidthForCount:count];
    const CGFloat leadingPad = (name.length > 0) ? kPSMMinimalGroupChipPad : kPSMMinimalGroupChevronTrailPad;
    const CGFloat nameWidth = (name.length > 0)
        ? [self minimalGroupTextWidth:name font:nameFont] + kPSMMinimalGroupBadgeGap
        : 0;
    const NSRect capsule = [self minimalCapsuleRectInChipFrame:chip.frame
                                                         width:leadingPad + nameWidth + trailing
                                                           bar:bar];
    if (NSWidth(capsule) <= 0 || NSHeight(capsule) <= 0) {
        return;
    }
    const CGFloat radius = NSHeight(capsule) / 2.0;
    NSBezierPath *capsulePath = [NSBezierPath bezierPathWithRoundedRect:capsule xRadius:radius yRadius:radius];
    NSColor *fill = [self minimalTintOfGroupColor:groupColor fraction:kPSMMinimalGroupChipFillFraction];
    [fill set];
    [capsulePath fill];

    NSColor *labelColor = [self minimalGroupLabelColorForGroupColor:groupColor fill:fill];
    const CGFloat midY = NSMidY(capsule);

    // Lay out from the trailing edge so the badge and chevron stay visible when
    // the capsule is squeezed; the name truncates instead.
    const CGFloat chevronX = NSMaxX(capsule) - kPSMMinimalGroupChevronTrailPad - kPSMMinimalGroupChevronWidth;
    const NSSize badgeSize = [self minimalGroupBadgeSizeForCount:count];
    const NSRect badge = NSMakeRect(chevronX - kPSMMinimalGroupChevronGap - badgeSize.width,
                                    round(midY - badgeSize.height / 2.0),
                                    badgeSize.width,
                                    badgeSize.height);

    [self drawMinimalGroupName:name
                        inRect:NSMakeRect(NSMinX(capsule) + leadingPad,
                                          NSMinY(capsule),
                                          MAX(0, NSMinX(badge) - kPSMMinimalGroupBadgeGap - NSMinX(capsule) - leadingPad),
                                          NSHeight(capsule))
                     cellFrame:chip.frame
                         color:labelColor];

    // Count badge.
    if (NSMinX(badge) >= NSMinX(capsule)) {
        NSColor *badgeFill = [self minimalTintOfGroupColor:groupColor fraction:kPSMMinimalGroupBadgeFillFraction];
        [badgeFill set];
        const CGFloat badgeRadius = badgeSize.height / 2.0;
        [[NSBezierPath bezierPathWithRoundedRect:badge xRadius:badgeRadius yRadius:badgeRadius] fill];
        NSFont *badgeFont = [self minimalGroupBadgeFont];
        NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
        para.alignment = NSTextAlignmentCenter;
        const CGFloat textHeight = ceil(badgeFont.ascender - badgeFont.descender);
        [[@(count) stringValue] drawInRect:NSMakeRect(NSMinX(badge), NSMidY(badge) - textHeight / 2.0,
                                                      NSWidth(badge), textHeight)
                            withAttributes:@{ NSFontAttributeName: badgeFont,
                                              NSForegroundColorAttributeName: [self minimalGroupLabelColorForGroupColor:groupColor fill:badgeFill],
                                              NSParagraphStyleAttributeName: para }];
    }

    // Right-pointing chevron: the group is collapsed and can be opened. The view
    // is flipped, so y grows downward.
    const CGFloat half = 3;
    NSBezierPath *chevron = [NSBezierPath bezierPath];
    [chevron moveToPoint:NSMakePoint(chevronX + 1, midY - half)];
    [chevron lineToPoint:NSMakePoint(chevronX + 1 + half, midY)];
    [chevron lineToPoint:NSMakePoint(chevronX + 1, midY + half)];
    chevron.lineWidth = 1.5;
    chevron.lineCapStyle = NSLineCapStyleRound;
    chevron.lineJoinStyle = NSLineJoinStyleRound;
    [labelColor setStroke];
    [chevron stroke];

    // Drop-target feedback: a dragged tab is poised to join this collapsed group.
    if (isDropTarget) {
        NSBezierPath *ring = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(capsule, -1.5, -1.5)
                                                             xRadius:radius + 1.5
                                                             yRadius:radius + 1.5];
        ring.lineWidth = 2;
        [[NSColor controlAccentColor] setStroke];
        [ring stroke];
    }
}

#pragma mark -

- (NSRect)adjustedCellRect:(NSRect)rect generic:(NSRect)generic {
    return rect;
}

- (NSAppearance *)accessoryAppearance {
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

- (CGFloat)verticalTabGroupHeaderHeight {
    return [iTermAdvancedSettingsModel compactMinimalTabBarHeight];
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
    if (self.tabBar.orientation == PSMTabBarHorizontalOrientation && self.tabBar.cells.count > 0) {
        // Fill only the area between the start and end insets. Those insets are painted with their own
        // colors just below; filling the background under them and then painting the insets on top
        // would stack two partly transparent fills into a darker band on a transparent window. This
        // matters especially for the scroll margins (the leading decoration band and the add-tab-button
        // gap), which are painted through this same path.
        const CGFloat insetLeft = NSMaxX([self startInsetFrame]);
        const CGFloat insetRight = NSMinX([self endInsetFrame]);
        const CGFloat minX = MAX(NSMinX(rect), insetLeft);
        const CGFloat maxX = MIN(NSMaxX(rect), insetRight);
        if (maxX > minX) {
            NSRectFillUsingOperation(NSMakeRect(minX, NSMinY(rect), maxX - minX, NSHeight(rect)),
                                     NSCompositingOperationSourceOver);
        }
    } else {
        NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);
    }

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
    if (bar.orientation != PSMTabBarHorizontalOrientation) {
        // Vertical: the end inset is the empty area below the last tab (and
        // behind the overflow button). It should read as the sidebar's tab
        // background, so always use the non-selected tab color. The selected-
        // color branch below is a horizontal concern (the selected tab scrolled
        // into the overflow) and here it painted this strip lighter -- the "last
        // tab bleeding into the overflow area" bug.
        color = [self nonSelectedTabColor];
    } else {
        PSMTabBarCell *cell = [self selectedCellInTabBarControl:bar];
        if (cell == nil || cell.isInOverflowMenu) {
            // Must be one of the overflow tabs
            color = [self selectedTabColor];
        } else {
            color = [self nonSelectedTabColor];
        }
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
        if (!cell.isInOverflowMenu && !cell.isCollapsedHidden && cell.state == NSControlStateValueOn) {
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
        // Extend to the leading margin so a first tab scrolled under the window decorations is covered
        // by the decoration color, rather than leaving a gap that the background fill would paint with
        // the darker selected-background base (a distracting dark box on a transparent window).
        const CGFloat right = MAX(NSMinX(cell.frame), [self leftMarginForTabBarControl]);
        return NSMakeRect(0, 0, right, cell.frame.size.height);
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
        // Clamp to the scroll viewport so a last tab scrolled under the add-tab button is covered by the
        // decoration color, rather than leaving a gap that the background fill would paint with the
        // darker selected-background base (a distracting dark box on a transparent window).
        CGFloat left = NSMaxX(cell.frame);
        const CGFloat viewport = self.tabBar.scrollViewportLength;
        if (left > viewport) {
            left = viewport;
        }
        return NSMakeRect(left,
                          0,
                          self.tabBar.frame.size.width - left,
                          cell.frame.size.height);
    } else {
        // Vertical tab bar: the end inset is everything below the last visible
        // tab, all the way to the bottom -- including the gap left when tabs
        // don't divide the bar height evenly and the overflow button's area.
        // (Covering only the button's slab left that gap painted with the
        // lighter selected-background base, so the last tab appeared to bleed
        // into the overflow area.) The overflow button draws on top of this.
        return NSMakeRect(0,
                          NSMaxY(cell.frame),
                          NSWidth(cell.frame),
                          NSHeight(self.tabBar.frame) - NSMaxY(cell.frame));
    }
}

- (PSMTabBarCell *)firstVisibleCell {
    PSMTabBarControl *bar = self.tabBar;
    for (PSMTabBarCell *cell in bar.cells) {
        if (!cell.isCollapsedHidden) {
            return cell;
        }
    }
    return nil;
}

- (PSMTabBarCell *)lastVisibleCell {
    PSMTabBarControl *bar = self.tabBar;
    for (PSMTabBarCell *cell in bar.cells.reverseObjectEnumerator) {
        // Mirror -[PSMTabBarControl _shouldDrawCell]: a collapsed group's trailing
        // members stay in the cell list with a zero-size frame but isInOverflowMenu==NO.
        // Skipping only overflow cells would return such a zero-height member when a
        // collapsed group is the rightmost item, giving endInsetFrame zero height so the
        // add-tab-button margin never gets painted (a white rectangle shows through).
        if (!cell.isInOverflowMenu && !cell.isCollapsedHidden) {
            return cell;
        }
    }
    return nil;
}

- (PSMTabBarCell *)selectedCellInTabBarControl:(PSMTabBarControl *)bar {
    for (PSMTabBarCell *cell in bar.cells) {
        // A tab bar search hides a selected tab that doesn't match; draw no
        // selected tab then, rather than outlining an empty spot. Keep looking
        // past a hidden one, which may be stale.
        if (cell.state == NSControlStateValueOn && !cell.isCollapsedHidden) {
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

    if (horizontalOrientation && NSIsEmptyRect(clipRect)) {
        // Background-only pass for a horizontal bar (empty cell clip rect), used to paint a scroll
        // margin: the leading decoration band on the left and the add-tab-button gap on the right.
        // Draw only the bar-edge line, which is meant to span across the whole bar (under the button
        // on a top bar, over it on a bottom bar); never the vertical tab-framing strokes, which must
        // stop at the tabs. The real pass (non-empty clip rect, clipped to the tab region) draws the
        // full notch, so a selected last tab whose right edge sits at the button margin gets no stray
        // vertical border there.
        [self drawScrollMarginEdgeLineForBar:bar];
        return;
    }

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

    if (horizontalOrientation) {
        [self drawActiveTabButtonEdgeBorderForBar:bar];
    }
}

// Draws just the bar's edge line (the horizontal dividing line) across the full width, at the same
// position the selected-tab notch would put it: the bottom edge for a top bar, the top edge for a
// bottom bar. The caller clips this to a scroll-margin strip, so it fills the edge line where the
// notch is intentionally skipped, without any vertical strokes crossing the add-tab button.
- (void)drawScrollMarginEdgeLineForBar:(PSMTabBarControl *)bar {
    PSMTabBarCell *const cell = [self selectedCellInTabBarControl:bar];
    if (!cell || cell.isInOverflowMenu) {
        return;
    }
    const CGFloat y = (bar.tabLocation == PSMTab_BottomTab) ? 0.5 : NSMaxY(cell.frame) - 0.5;
    NSBezierPath *const path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(0, y)];
    [path lineToPoint:NSMakePoint(NSMaxX(bar.frame), y)];
    [[self outlineColor] set];
    [path stroke];
}

// Caps the active tab with a right vertical border just to the LEFT of the add-tab button whenever the
// tab's right edge reaches that button edge: its left part is still visible but its right border would
// land at (or under) the button. The notch draws its own right border at the tab's true right edge,
// NSMaxX + 0.5; once that is at or past the viewport edge the tab-region clip drops it, leaving the tab
// open on the right. This draws a stand-in at the viewport edge so the active tab still reads as closed
// right where it meets the button. Drawn in the tab-region pass so it lands left of the button rather
// than behind it. A tab whose right border is still comfortably inside the region (the notch draws it)
// or that is fully past the button (invisible) gets nothing here.
- (void)drawActiveTabButtonEdgeBorderForBar:(PSMTabBarControl *)bar {
    PSMTabBarCell *const cell = [self selectedCellInTabBarControl:bar];
    if (!cell || cell.isInOverflowMenu) {
        return;
    }
    const CGFloat viewport = bar.scrollViewportLength;
    if (NSMinX(cell.frame) >= viewport || NSMaxX(cell.frame) <= viewport - 0.5) {
        return;
    }
    const CGFloat x = viewport - 0.5;
    // Extend half a point past the bar-edge line (the bottom for a top bar, the top for a bottom bar)
    // so the cap reaches the line's outer edge and forms a clean corner instead of stopping at its
    // center.
    const BOOL bottomTab = (bar.tabLocation == PSMTab_BottomTab);
    const CGFloat yTop = bottomTab ? 0.0 : 0.5;
    const CGFloat yBottom = bottomTab ? NSMaxY(cell.frame) - 0.5 : NSMaxY(cell.frame);
    NSBezierPath *const path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(x, yTop)];
    [path lineToPoint:NSMakePoint(x, yBottom)];
    [[self outlineColor] set];
    [path stroke];
}

- (void)drawDividerBetweenTabBarAndContent:(NSRect)rect bar:(PSMTabBarControl *)bar {
}

- (BOOL)shouldDrawTopLineSelected:(BOOL)selected
                         attached:(BOOL)attached
                         position:(PSMTabPosition)position {
    switch (position) {
        case PSMTab_BottomTab:
            return NO;

        case PSMTab_LeftTab:
        case PSMTab_RightTab:
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
