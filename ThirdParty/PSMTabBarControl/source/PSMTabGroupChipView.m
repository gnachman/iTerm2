//
//  PSMTabGroupChipView.m
//  PSMTabBarControl
//

#import "PSMTabGroupChipView.h"
#import "PSMTabBarControl.h"
#import "PSMTabStyle.h"

@implementation PSMTabGroupChipView

// Horizontal padding around the label inside the chip, and the gap the
// control leaves between the chip and the run's first tab.
static const CGFloat PSMTabGroupChipHInset = 8;
static const CGFloat PSMTabGroupChipTrailingGap = 4;
// Height of the chip that heads a vertical bar's run (it sits above the
// run spanning the bar width), and the gap the control reserves for it.
static const CGFloat PSMTabGroupChipVerticalHeight = 18;

- (BOOL)isFlipped {
    return NO;
}

+ (NSFont *)chipFont {
    return [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
}

- (NSFont *)font {
    return [PSMTabGroupChipView chipFont];
}

// Class method so the tab bar can reserve the leading gap during layout,
// before any chip instance exists. Must match -preferredWidth exactly.
+ (CGFloat)preferredWidthForName:(NSString *)name {
    NSDictionary *attrs = @{ NSFontAttributeName: [self chipFont] };
    const CGFloat textWidth = ceil([(name ?: @"") sizeWithAttributes:attrs].width);
    return textWidth + PSMTabGroupChipHInset * 2 + PSMTabGroupChipTrailingGap;
}

- (CGFloat)preferredWidth {
    return [PSMTabGroupChipView preferredWidthForName:self.groupName];
}

// Height reserved above a vertical bar's run for its chip.
+ (CGFloat)verticalChipHeight {
    return PSMTabGroupChipVerticalHeight;
}

- (void)drawRect:(NSRect)dirtyRect {
    id<PSMTabStyle> style = self.tabBarControl.style;
    if ([style respondsToSelector:@selector(drawTabGroupChipWithName:color:selected:frame:inControl:)]) {
        [style drawTabGroupChipWithName:self.groupName ?: @""
                                  color:self.groupColor ?: [NSColor grayColor]
                               selected:self.selected
                                  frame:self.bounds
                              inControl:self.tabBarControl];
        return;
    }
    [self drawBasicChip];
}

- (void)drawBasicChip {
    [PSMTabGroupChipView drawChipInFrame:self.bounds
                                    name:self.groupName ?: @""
                                   color:self.groupColor ?: [NSColor grayColor]];
}

// Basic chip look, shared by the overlay view and the first-class chip
// cell (PSMTabBarCell drawing). A rounded rect filled with the group
// color and the name in a contrasting color. Used until a tab style
// overrides the chip drawing.
+ (void)drawChipInFrame:(NSRect)frame name:(NSString *)name color:(NSColor *)color {
    color = color ?: [NSColor grayColor];
    // Inset the capsule from the cell edges (a bit more horizontally so
    // the rounded ends aren't clipped and it matches the tab insets).
    NSRect bounds = NSInsetRect(frame, 4, 3);
    if (bounds.size.width <= 0 || NSHeight(bounds) <= 0) {
        return;
    }
    const CGFloat radius = NSHeight(bounds) / 2.0;
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:bounds
                                                        xRadius:radius
                                                        yRadius:radius];
    [color set];
    [path fill];

    if (name.length == 0) {
        return;
    }
    NSColor *rgb = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    const CGFloat brightness = rgb ? (0.299 * rgb.redComponent +
                                      0.587 * rgb.greenComponent +
                                      0.114 * rgb.blueComponent)
                                   : 0.5;
    NSColor *textColor = brightness < 0.55 ? [NSColor whiteColor]
                                           : [NSColor blackColor];
    NSMutableParagraphStyle *para = [[[NSMutableParagraphStyle alloc] init] autorelease];
    para.alignment = NSTextAlignmentCenter;
    para.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary *attrs = @{ NSFontAttributeName: [self chipFont],
                             NSForegroundColorAttributeName: textColor,
                             NSParagraphStyleAttributeName: para };
    // Center vertically; the paragraph style centers horizontally and
    // truncates if the name is wider than the capsule.
    const CGFloat inset = PSMTabGroupChipHInset;
    NSSize textSize = [name sizeWithAttributes:attrs];
    NSRect textRect = NSMakeRect(NSMinX(bounds) + inset,
                                 NSMidY(bounds) - textSize.height / 2.0,
                                 MAX(0, NSWidth(bounds) - inset * 2),
                                 textSize.height);
    [name drawInRect:textRect withAttributes:attrs];
}

@end
