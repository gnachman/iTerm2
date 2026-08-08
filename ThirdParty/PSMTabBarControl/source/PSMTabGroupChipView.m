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
static const CGFloat PSMTabGroupChipVerticalHeight = 28;

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
    // Inset the capsule so it's centered in the cell with a margin on all
    // sides (the vertical margin separates it from the tabs above/below).
    NSRect bounds = NSInsetRect(frame, 4, 5);
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
    NSFont *font = [self chipFont];
    NSMutableParagraphStyle *para = [[[NSMutableParagraphStyle alloc] init] autorelease];
    // Left-align so the chip label lines up with the tab labels below it.
    para.alignment = NSTextAlignmentLeft;
    para.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary *attrs = @{ NSFontAttributeName: font,
                             NSForegroundColorAttributeName: textColor,
                             NSParagraphStyleAttributeName: para };
    const CGFloat inset = PSMTabGroupChipHInset;
    // Vertically center on the cap height (control is flipped): put the
    // line box top so the glyph body straddles the capsule's midline.
    const CGFloat textTop = NSMidY(bounds) - font.ascender + font.capHeight / 2.0;
    NSRect textRect = NSMakeRect(NSMinX(bounds) + inset,
                                 textTop,
                                 MAX(0, NSWidth(bounds) - inset * 2),
                                 NSHeight(bounds));
    [name drawInRect:textRect withAttributes:attrs];
}

@end
