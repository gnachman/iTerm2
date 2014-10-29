//
//  PSMDarkTabStyle.m
//  iTerm
//
//  Created by Brian Mock on 10/28/14.
//
//

#import "PSMDarkTabStyle.h"
#import "PSMTabBarCell.h"
#import "PSMTabBarControl.h"

#define kPSMDarkObjectCounterRadius 7.0
#define kPSMDarkCounterMinWidth 20
#define kPSMDarkLeftMargin 0.0

@interface PSMDarkTabStyle (Private)
- (void)drawInteriorWithTabCell:(PSMTabBarCell *)cell inView:(NSView*)controlView;
@end

@implementation PSMDarkTabStyle

- (NSColor *)colorBG
{
    return [NSColor colorWithCalibratedWhite:0.15 alpha:1];
}

- (NSColor *)colorFG
{
    return [NSColor colorWithCalibratedWhite:1.00 alpha:1];
}

- (NSColor *)colorFGSelected
{
    return [NSColor colorWithCalibratedWhite:1.00 alpha:0.80];
}

- (NSColor *)colorBGSelected
{
    return [NSColor colorWithCalibratedWhite:0.50 alpha:1];
}

- (NSColor *)colorBorder
{
    return [NSColor colorWithCalibratedWhite:0.05 alpha:1];
}

- (NSString *)fontName
{
    return @"Menlo";
}

- (NSFont *)tabFont
{
    return [NSFont fontWithName:[self fontName] size:11.0];
}

- (NSString *)name
{
    return @"Dark";
}

- (NSColor *)textColorForCell:(PSMTabBarCell *)cell
{
    return cell.state == NSOnState
        ? [self colorFG]
        : [self colorFGSelected];
}

- (void)drawBackgroundInRect:(NSRect)rect
                       color:(NSColor *)backgroundColor
                  horizontal:(BOOL)horizontal
{
    [[self colorBG] set];
    NSRectFill(rect);
}

- (void)drawTabBar:(PSMTabBarControl *)bar
            inRect:(NSRect)rect
        horizontal:(BOOL)horizontal
{
    [[self colorBG] set];
    [super drawTabBar:bar inRect:rect horizontal:horizontal];
    [[self colorBorder] set];
    NSRect topEdge = NSMakeRect(NSMinX(rect),
                                NSMinY(rect),
                                NSWidth(rect),
                                1);
    NSRect bottomEdge = NSMakeRect(NSMinX(rect),
                                   NSMaxY(rect) - 1,
                                   NSWidth(rect),
                                   1);
    NSRect rightEdge = NSMakeRect(NSMaxX(rect) - 1,
                                  NSMinY(rect),
                                  1,
                                  NSHeight(rect));
    if (horizontal) {
        NSRectFill(topEdge);
        NSRectFill(bottomEdge);
    } else {
        NSRectFill(rightEdge);
    }
}

- (void)drawCellBackgroundAndFrameHorizontallyOriented:(BOOL)horizontal
                                                inRect:(NSRect)cellFrame
                                              selected:(BOOL)selected
                                          withTabColor:(NSColor *)tabColor
{
    NSColor *color = selected
        ? [self colorBGSelected]
        : [self colorBG];
    [color set];
    NSRect backgroundRect = NSMakeRect(NSMinX(cellFrame),
                                       NSMinY(cellFrame),
                                       NSWidth(cellFrame),
                                       NSHeight(cellFrame));
    NSRect rightEdge = NSMakeRect(NSMaxX(cellFrame) - 1,
                                  NSMinY(cellFrame),
                                  1,
                                  NSHeight(cellFrame));
    NSRect bottomEdge = NSMakeRect(NSMinX(cellFrame),
                                   NSMaxY(cellFrame) - 1,
                                   NSWidth(cellFrame),
                                   1);
    NSRectFill(backgroundRect);

    [[self colorBorder] set];
    if (horizontal) {
        NSRectFill(rightEdge);
    } else {
        NSRectFill(bottomEdge);
    }

    if (tabColor) {
        if (selected) {
            [[tabColor colorWithAlphaComponent:0.8] set];
        } else {
            [[tabColor colorWithAlphaComponent:0.4] set];
        }
        NSRect colorRect = backgroundRect;
        colorRect.size.width -= 1;
        NSRectFillUsingOperation(colorRect, NSCompositeSourceOver);
    }
}

@end
