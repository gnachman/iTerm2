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
#import "NSBezierPath_AMShading.h"

#define kPSMDarkObjectCounterRadius 7.0
#define kPSMDarkCounterMinWidth 20
#define kPSMDarkLeftMargin 0.0

@interface PSMDarkTabStyle (Private)
- (void)drawInteriorWithTabCell:(PSMTabBarCell *)cell inView:(NSView*)controlView;
@end

@implementation PSMDarkTabStyle

- (NSColor *)colorBG
{
    return [NSColor colorWithCalibratedWhite:0.08 alpha:1];
}

- (NSColor *)colorFG
{
    return [NSColor colorWithCalibratedWhite:1.00 alpha:1];
}

- (NSColor *)colorBGSelected
{
    return [NSColor colorWithCalibratedWhite:0.50 alpha:1];
}

- (NSColor *)colorBorder
{
    return [NSColor colorWithCalibratedWhite:0.02 alpha:1];
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

#pragma mark -
#pragma mark Creation/Destruction

- (id) init
{
    if((self = [super init]))
    {
        darkCloseButton = [[NSImage imageNamed:@"AquaTabClose_Front"] retain];
        darkCloseButtonDown = [[NSImage imageNamed:@"AquaTabClose_Front_Pressed"] retain];
        darkCloseButtonOver = [[NSImage imageNamed:@"AquaTabClose_Front_Rollover"] retain];

        _addTabButtonImage = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:@"AquaTabNew"]];
        _addTabButtonPressedImage = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:@"AquaTabNewPressed"]];
        _addTabButtonRolloverImage = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:@"AquaTabNewRollover"]];

        leftMargin = kPSMDarkLeftMargin;
    }
    return self;
}

- (void)dealloc
{
    [darkCloseButton release];
    [darkCloseButtonDown release];
    [darkCloseButtonOver release];
    [_addTabButtonImage release];
    [_addTabButtonPressedImage release];
    [_addTabButtonRolloverImage release];

    [super dealloc];
}

#pragma mark -
#pragma mark Control Specific

- (void)setLeftMarginForTabBarControl:(float)margin
{
    leftMargin = margin;
}

- (float)leftMarginForTabBarControl
{
    return leftMargin;
}

- (float)rightMarginForTabBarControl
{
    return 24.0f;
}

- (float)topMarginForTabBarControl
{
    return 10.0f;
}

#pragma mark -
#pragma mark Add Tab Button

- (NSImage *)addTabButtonImage
{
    return _addTabButtonImage;
}

- (NSImage *)addTabButtonPressedImage
{
    return _addTabButtonPressedImage;
}

- (NSImage *)addTabButtonRolloverImage
{
    return _addTabButtonRolloverImage;
}

#pragma mark -
#pragma mark Cell Specific

- (NSRect)dragRectForTabCell:(PSMTabBarCell *)cell orientation:(PSMTabBarOrientation)orientation
{
    NSRect dragRect = [cell frame];
    dragRect.size.width++;
    return dragRect;
}

- (NSRect)closeButtonRectForTabCell:(PSMTabBarCell *)cell
{
    NSRect cellFrame = [cell frame];

    if ([cell hasCloseButton] == NO) {
        return NSZeroRect;
    }

    NSRect result;
    result.size = [darkCloseButton size];
    result.origin.x = cellFrame.origin.x + MARGIN_X;
    result.origin.y = cellFrame.origin.y + MARGIN_Y + 1.0;

    return result;
}

- (NSRect)iconRectForTabCell:(PSMTabBarCell *)cell
{
    NSRect cellFrame = [cell frame];

    if ([cell hasIcon] == NO) {
        return NSZeroRect;
    }

    NSRect result;
    result.size = NSMakeSize(kPSMTabBarIconWidth, kPSMTabBarIconWidth);
    result.origin.x = cellFrame.origin.x + MARGIN_X;
    result.origin.y = cellFrame.origin.y + MARGIN_Y - 1.0;

    if([cell hasCloseButton] && ![cell isCloseButtonSuppressed])
        result.origin.x += [darkCloseButton size].width + kPSMTabBarCellPadding;

    return result;
}

- (NSRect)indicatorRectForTabCell:(PSMTabBarCell *)cell
{
    NSRect cellFrame = [cell frame];

    if ([[cell indicator] isHidden]) {
        return NSZeroRect;
    }

    NSRect result;
    result.size = NSMakeSize(kPSMTabBarIndicatorWidth, kPSMTabBarIndicatorWidth);
    result.origin.x = cellFrame.origin.x + cellFrame.size.width - MARGIN_X - kPSMTabBarIndicatorWidth;
    result.origin.y = cellFrame.origin.y + MARGIN_Y - 1.0;

    return result;
}

- (NSRect)objectCounterRectForTabCell:(PSMTabBarCell *)cell
{
    NSRect cellFrame = [cell frame];

    if ([cell count] == 0) {
        return NSZeroRect;
    }

    float countWidth = [[self attributedObjectCountValueForTabCell:cell] size].width;
    countWidth += (2 * kPSMDarkObjectCounterRadius - 6.0);
    if(countWidth < kPSMDarkCounterMinWidth)
        countWidth = kPSMDarkCounterMinWidth;

    NSRect result;
    result.size = NSMakeSize(countWidth, 2 * kPSMDarkObjectCounterRadius); // temp
    result.origin.x = cellFrame.origin.x + cellFrame.size.width - MARGIN_X - result.size.width;
    result.origin.y = cellFrame.origin.y + MARGIN_Y + 1.0;

    if(![[cell indicator] isHidden])
        result.origin.x -= kPSMTabBarIndicatorWidth + kPSMTabBarCellPadding;

    return result;
}


- (float)minimumWidthOfTabCell:(PSMTabBarCell *)cell
{
    float resultWidth = 0.0;

    // left margin
    resultWidth = MARGIN_X;

    // close button?
    if([cell hasCloseButton] && ![cell isCloseButtonSuppressed])
        resultWidth += [darkCloseButton size].width + kPSMTabBarCellPadding;

    // icon?
    if([cell hasIcon])
        resultWidth += kPSMTabBarIconWidth + kPSMTabBarCellPadding;

    // the label
    resultWidth += kPSMMinimumTitleWidth;

    // object counter?
    if([cell count] > 0)
        resultWidth += [self objectCounterRectForTabCell:cell].size.width + kPSMTabBarCellPadding;

    // indicator?
    if ([[cell indicator] isHidden] == NO)
        resultWidth += kPSMTabBarCellPadding + kPSMTabBarIndicatorWidth;

    // right margin
    resultWidth += MARGIN_X;

    return ceil(resultWidth);
}

- (float)desiredWidthOfTabCell:(PSMTabBarCell *)cell
{
    float resultWidth = 0.0;

    // left margin
    resultWidth = MARGIN_X;

    // close button?
    if ([cell hasCloseButton] && ![cell isCloseButtonSuppressed])
        resultWidth += [darkCloseButton size].width + kPSMTabBarCellPadding;

    // icon?
    if([cell hasIcon])
        resultWidth += kPSMTabBarIconWidth + kPSMTabBarCellPadding;

    // the label
    resultWidth += [[cell attributedStringValue] size].width;

    // object counter?
    if([cell count] > 0)
        resultWidth += [self objectCounterRectForTabCell:cell].size.width + kPSMTabBarCellPadding;

    // indicator?
    if ([[cell indicator] isHidden] == NO)
        resultWidth += kPSMTabBarCellPadding + kPSMTabBarIndicatorWidth;

    // right margin
    resultWidth += MARGIN_X;

    return ceil(resultWidth);
}

#pragma mark -
#pragma mark Cell Values

- (NSAttributedString *)attributedObjectCountValueForTabCell:(PSMTabBarCell *)cell
{
    NSMutableAttributedString *attrStr;
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_4
    NSNumberFormatter *nf = [[[NSNumberFormatter alloc] init] autorelease];
    [nf setLocalizesFormat:YES];
    [nf setFormat:@"0"];
    [nf setHasThousandSeparators:YES];
    NSString *contents = [nf stringFromNumber:[NSNumber numberWithInt:[cell count]]];
#else
    NSString *contents = [NSString stringWithFormat:@"%d", [cell count]];
#endif
    if ([cell count] < 9) {
        contents = [NSString stringWithFormat:@"%@%@", [cell modifierString], contents];
    } else if ([cell isLast]) {
        contents = [NSString stringWithFormat:@"%@9", [cell modifierString]];
    } else {
        contents = @"";
    }
    attrStr = [[[NSMutableAttributedString alloc] initWithString:contents] autorelease];
    NSRange range = NSMakeRange(0, [contents length]);

    // Add font attribute
    [attrStr addAttribute:NSFontAttributeName value:[self tabFont] range:range];
    [attrStr addAttribute:NSForegroundColorAttributeName value:[self colorFG] range:range];

    return attrStr;
}

- (NSAttributedString *)attributedStringValueForTabCell:(PSMTabBarCell *)cell
{
    NSMutableAttributedString *attrStr;
    NSString * contents = [cell stringValue];
    attrStr = [[[NSMutableAttributedString alloc] initWithString:contents] autorelease];
    NSRange range = NSMakeRange(0, [contents length]);

    [attrStr addAttribute:NSFontAttributeName value:[self tabFont] range:range];
    [attrStr addAttribute:NSForegroundColorAttributeName value:[self colorFG] range:range];

    // Paragraph Style for Truncating Long Text
    static NSMutableParagraphStyle *TruncatingTailParagraphStyle = nil;
    if (!TruncatingTailParagraphStyle) {
        TruncatingTailParagraphStyle = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] retain];
        [TruncatingTailParagraphStyle setLineBreakMode:NSLineBreakByTruncatingTail];
    }
    [attrStr addAttribute:NSParagraphStyleAttributeName value:TruncatingTailParagraphStyle range:range];

    return attrStr;
}

#pragma mark -
#pragma mark ---- drawing ----

- (void)overlayTabColor:(NSColor *)tabColor
                inFrame:(NSRect)cellFrame
                  alpha:(CGFloat)alpha
{
    [[tabColor colorWithAlphaComponent:alpha] set];
    NSRectFillUsingOperation(NSMakeRect(cellFrame.origin.x + 0.5,
                                        cellFrame.origin.y + 0.5,
                                        cellFrame.size.width,
                                        cellFrame.size.height),
                             NSCompositeSourceOver);
}

- (void)drawTabCell:(PSMTabBarCell *)cell
{
    NSRect cellFrame = [cell frame];

    // Adjust tab size so it doesn't bleed into edges of tab bar,
    // leaving the borders visible.
    cellFrame.origin.y += 1.0;
    cellFrame.size.height -= 2.0;

    // TODO: use [cell isHighlighted] to change hover color.
    // TODO: use [NSApp isActive] to change inactive window color.
    if ([cell state] == NSOnState) {
        [[self colorBGSelected] set];
    } else {
        [[self colorBG] set];
    }
    NSRectFill(cellFrame);

    [self drawInteriorWithTabCell:cell inView:[cell controlView]];
}


- (void)drawInteriorWithTabCell:(PSMTabBarCell *)cell inView:(NSView*)controlView
{
    NSRect cellFrame = [cell frame];
    float labelPosition = cellFrame.origin.x + MARGIN_X;

    // close button
    if ([cell hasCloseButton] && ![cell isCloseButtonSuppressed]) {
        NSSize closeButtonSize = NSZeroSize;
        NSRect closeButtonRect = [cell closeButtonRectForFrame:cellFrame];
        NSImage * closeButton = nil;

        closeButton = darkCloseButton;
        if ([cell closeButtonOver]) closeButton = darkCloseButtonOver;
        if ([cell closeButtonPressed]) closeButton = darkCloseButtonDown;

        closeButtonSize = [closeButton size];
        if ([controlView isFlipped]) {
            closeButtonRect.origin.y += closeButtonRect.size.height;
        }

        [closeButton compositeToPoint:closeButtonRect.origin operation:NSCompositeSourceOver fraction:1.0];

        // scoot label over
        labelPosition += closeButtonSize.width + kPSMTabBarCellPadding;
    }

    // icon
    if([cell hasIcon]){
        NSRect iconRect = [self iconRectForTabCell:cell];
        NSImage *icon = [(id)[[cell representedObject] identifier] icon];
        if ([controlView isFlipped]) {
            iconRect.origin.y += iconRect.size.height;
        }

        // center in available space (in case icon image is smaller than kPSMTabBarIconWidth)
        if([icon size].width < kPSMTabBarIconWidth)
            iconRect.origin.x += (kPSMTabBarIconWidth - [icon size].width)/2.0;
        if([icon size].height < kPSMTabBarIconWidth)
            iconRect.origin.y -= (kPSMTabBarIconWidth - [icon size].height)/2.0;

        [icon compositeToPoint:iconRect.origin operation:NSCompositeSourceOver fraction:1.0];

        // scoot label over
        labelPosition += iconRect.size.width + kPSMTabBarCellPadding;
    }

    // object counter
    if([cell count] > 0){
        NSRect myRect = [self objectCounterRectForTabCell:cell];
        myRect.origin.y -= 1.0;

        // draw attributed string centered in area
        NSRect counterStringRect;
        NSAttributedString *counterString = [self attributedObjectCountValueForTabCell:cell];
        counterStringRect.size = [counterString size];
        counterStringRect.origin.x = myRect.origin.x + ((myRect.size.width - counterStringRect.size.width) / 2.0) + 0.25;
        counterStringRect.origin.y = myRect.origin.y + ((myRect.size.height - counterStringRect.size.height) / 2.0) + 0.5;
        [counterString drawInRect:counterStringRect];
    }

    // label rect
    NSRect labelRect;
    labelRect.origin.x = labelPosition;
    labelRect.size.width = cellFrame.size.width - (labelRect.origin.x - cellFrame.origin.x) - kPSMTabBarCellPadding;
    NSSize s = [[cell attributedStringValue] size];
    labelRect.origin.y = cellFrame.origin.y + (cellFrame.size.height-s.height)/2.0 - 1.0;
    labelRect.size.height = s.height;

    if(![[cell indicator] isHidden])
        labelRect.size.width -= (kPSMTabBarIndicatorWidth + kPSMTabBarCellPadding);

    if([cell count] > 0)
        labelRect.size.width -= ([self objectCounterRectForTabCell:cell].size.width + kPSMTabBarCellPadding);

    // label
    [[self attributedStringValueForTabCell:cell] drawInRect:labelRect];
}

// NOTE: This draws the tab bar background.
- (void)drawBackgroundInRect:(NSRect)rect color:(NSColor*)color
{
    // Draw fill color
    [[self colorBG] set];
    NSRectFill(rect);

    [[self colorBorder] set];
    // Bottom border
    [NSBezierPath strokeLineFromPoint:NSMakePoint(rect.origin.x, NSMaxY(rect) - 0.5)
                              toPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect) - 0.5)];
    // Top border
    [NSBezierPath strokeLineFromPoint:NSMakePoint(rect.origin.x, NSMinY(rect) + 0.5)
                              toPoint:NSMakePoint(NSMaxX(rect), NSMinY(rect) + 0.5)];
}

- (void)fillPath:(NSBezierPath*)path
{
    if ([[[tabBar tabView] window] isKeyWindow]) {
        [path linearGradientFillWithStartColor:[NSColor colorWithCalibratedWhite:0.843 alpha:1.0]
                                      endColor:[NSColor colorWithCalibratedWhite:0.835 alpha:1.0]];
    } else {
        [[NSColor windowBackgroundColor] set];
        [path fill];
    }
    [[NSColor colorWithCalibratedWhite:0.576 alpha:1.0] set];
    [path stroke];
}

- (void)drawTabBar:(PSMTabBarControl *)bar inRect:(NSRect)rect
{
    PSMTabBarCell* activeCell = nil;
    for (PSMTabBarCell *cell in [bar cells]) {
        if ([cell state] == NSOnState) {
            activeCell = cell;
            break;
        }
    }
    tabBar = bar;
    [self drawBackgroundInRect:rect color:[activeCell tabColor]];

    // no tab view == not connected
    if(![bar tabView]){
        NSRect labelRect = rect;
        labelRect.size.height -= 4.0;
        labelRect.origin.y += 4.0;
        NSMutableAttributedString *attrStr;
        NSString *contents = @"PSMTabBarControl";
        attrStr = [[[NSMutableAttributedString alloc] initWithString:contents] autorelease];
        NSRange range = NSMakeRange(0, [contents length]);
        [attrStr addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:11.0] range:range];
        NSMutableParagraphStyle *centeredParagraphStyle = nil;
        if (!centeredParagraphStyle) {
            centeredParagraphStyle = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
            [centeredParagraphStyle setAlignment:NSCenterTextAlignment];
        }
        [attrStr addAttribute:NSParagraphStyleAttributeName value:centeredParagraphStyle range:range];
        [attrStr drawInRect:labelRect];
        return;
    }

    // draw cells
    NSEnumerator *e = [[bar cells] objectEnumerator];
    PSMTabBarCell *cell;
    while ( (cell = [e nextObject]) ) {
        if (![cell isInOverflowMenu] && NSIntersectsRect([cell frame], rect)) {
            [cell drawWithFrame:[cell frame] inView:bar];
        }
    }
}

#pragma mark -
#pragma mark Archiving

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    //[super encodeWithCoder:aCoder];
    if ([aCoder allowsKeyedCoding]) {
        [aCoder encodeObject:darkCloseButton forKey:@"darkCloseButton"];
        [aCoder encodeObject:darkCloseButtonDown forKey:@"darkCloseButtonDown"];
        [aCoder encodeObject:darkCloseButtonOver forKey:@"darkCloseButtonOver"];
        [aCoder encodeObject:_addTabButtonImage forKey:@"addTabButtonImage"];
        [aCoder encodeObject:_addTabButtonPressedImage forKey:@"addTabButtonPressedImage"];
        [aCoder encodeObject:_addTabButtonRolloverImage forKey:@"addTabButtonRolloverImage"];
    }
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    // self = [super initWithCoder:aDecoder];
    //if (self) {
    if ([aDecoder allowsKeyedCoding]) {
        darkCloseButton = [[aDecoder decodeObjectForKey:@"darkCloseButton"] retain];
        darkCloseButtonDown = [[aDecoder decodeObjectForKey:@"darkCloseButtonDown"] retain];
        darkCloseButtonOver = [[aDecoder decodeObjectForKey:@"darkCloseButtonOver"] retain];
        _addTabButtonImage = [[aDecoder decodeObjectForKey:@"addTabButtonImage"] retain];
        _addTabButtonPressedImage = [[aDecoder decodeObjectForKey:@"addTabButtonPressedImage"] retain];
        _addTabButtonRolloverImage = [[aDecoder decodeObjectForKey:@"addTabButtonRolloverImage"] retain];
    }
    //}
    return self;
}

@end
