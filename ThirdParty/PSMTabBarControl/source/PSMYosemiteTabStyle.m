//
//  PSMYosemiteTabStyle.m
//  PSMTabBarControl
//
//  Created by John Pannell on 2/17/06.
//  Copyright 2006 Positive Spin Media. All rights reserved.
//

#import "PSMYosemiteTabStyle.h"
#import "PSMTabBarCell.h"
#import "PSMTabBarControl.h"
#import <objc/runtime.h>

#define kPSMMetalObjectCounterRadius 7.0
#define kPSMMetalCounterMinWidth 20

@interface NSAttributedString(PSM)
- (NSAttributedString *)attributedStringWithTextAlignment:(NSTextAlignment)textAlignment;
@end

@implementation NSAttributedString(PSM)

- (NSAttributedString *)attributedStringWithTextAlignment:(NSTextAlignment)textAlignment {
    if (self.length == 0) {
        return self;
    }
    NSDictionary *immutableAttributes = [self attributesAtIndex:0 effectiveRange:nil];
    if (!immutableAttributes) {
        return self;
    }

    NSMutableDictionary *attributes = [[immutableAttributes mutableCopy] autorelease];
    NSMutableParagraphStyle *paragraphStyle = [[attributes[NSParagraphStyleAttributeName] mutableCopy] autorelease];
    if (!paragraphStyle) {
        paragraphStyle = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
    }
    paragraphStyle.alignment = textAlignment;
    NSMutableAttributedString *temp = [[self mutableCopy] autorelease];
    attributes[NSParagraphStyleAttributeName] = paragraphStyle;
    [temp setAttributes:attributes range:NSMakeRange(0, temp.length)];
    return temp;
}

@end

@interface PSMTabBarCell(PSMYosemiteTabStyle)

@property(nonatomic) NSAttributedString *previousAttributedString;
@property(nonatomic) CGFloat previousWidthOfAttributedString;

@end

@implementation PSMTabBarCell(PSMYosemiteTabStyle)

- (NSMutableDictionary *)psm_yosemiteAssociatedDictionary {
    NSMutableDictionary *dictionary = objc_getAssociatedObject(self, _cmd);
    if (!dictionary) {
        dictionary = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, _cmd, dictionary, OBJC_ASSOCIATION_RETAIN);
    }
    return dictionary;
}

- (NSAttributedString *)previousAttributedString {
    return self.psm_yosemiteAssociatedDictionary[@"attributedString"];
}

- (void)setPreviousAttributedString:(NSAttributedString *)previousAttributedString {
    self.psm_yosemiteAssociatedDictionary[@"attributedString"] = [[previousAttributedString copy] autorelease];
}

- (CGFloat)previousWidthOfAttributedString {
    return [self.psm_yosemiteAssociatedDictionary[@"attributedStringWidth"] doubleValue];
}

- (void)setPreviousWidthOfAttributedString:(CGFloat)previousWidthOfAttributedString {
    self.psm_yosemiteAssociatedDictionary[@"attributedStringWidth"] = @(previousWidthOfAttributedString);
}

@end

@implementation PSMYosemiteTabStyle {
    NSImage *_closeButton;
    NSImage *_closeButtonDown;
    NSImage *_closeButtonOver;
    NSImage *_addTabButtonImage;
    NSImage *_addTabButtonPressedImage;
    NSImage *_addTabButtonRolloverImage;

    NSDictionary *_objectCountStringAttributes;

    PSMTabBarOrientation _orientation;
    PSMTabBarControl *_tabBar;
}

- (NSString *)name {
    return @"Yosemite";
}

#pragma mark -
#pragma mark Creation/Destruction

- (id)init {
    if ((self = [super init]))  {
        // Load close buttons 
        _closeButton = [[NSImage imageNamed:@"TabClose_Front"] retain];
        _closeButtonDown = [[NSImage imageNamed:@"TabClose_Front_Pressed"] retain];
        _closeButtonOver = [[NSImage imageNamed:@"TabClose_Front_Rollover"] retain];

        // Load "new tab" buttons
        _addTabButtonImage = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:@"TabNewMetal"]];
        _addTabButtonPressedImage = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:@"TabNewMetalPressed"]];
        _addTabButtonRolloverImage = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:@"TabNewMetalRollover"]];
    }
    return self;
}

- (void)dealloc {
    [_closeButton release];
    [_closeButtonDown release];
    [_closeButtonOver release];
    [_addTabButtonImage release];
    [_addTabButtonPressedImage release];
    [_addTabButtonRolloverImage release];

    [super dealloc];
}

#pragma mark - Control Specific

- (float)leftMarginForTabBarControl {
    return 0.0f;
}

- (float)rightMarginForTabBarControl {
    // Leaves space for overflow control.
    return 24.0f;
}

// For vertical orientation
- (float)topMarginForTabBarControl {
    return 0.0f;
}

#pragma mark - Add Tab Button

- (NSImage *)addTabButtonImage {
    return _addTabButtonImage;
}

- (NSImage *)addTabButtonPressedImage {
    return _addTabButtonPressedImage;
}

- (NSImage *)addTabButtonRolloverImage {
    return _addTabButtonRolloverImage;
}

#pragma mark - Cell Specific

- (NSRect)dragRectForTabCell:(PSMTabBarCell *)cell
                 orientation:(PSMTabBarOrientation)tabOrientation {
    NSRect dragRect = [cell frame];
    dragRect.size.width++;

    if ([cell tabState] & PSMTab_SelectedMask) {
        if (tabOrientation == PSMTabBarHorizontalOrientation) {
            dragRect.size.height -= 2.0;
        } else {
            dragRect.size.height += 1.0;
            dragRect.origin.y -= 1.0;
            dragRect.origin.x += 2.0;
            dragRect.size.width -= 3.0;
        }
    } else if (tabOrientation == PSMTabBarVerticalOrientation) {
        dragRect.origin.x--;
    }

    return dragRect;
}

- (NSRect)closeButtonRectForTabCell:(PSMTabBarCell *)cell {
    NSRect cellFrame = [cell frame];

    if ([cell hasCloseButton] == NO) {
        return NSZeroRect;
    }

    NSRect result;
    result.size = [_closeButton size];
    result.origin.x = cellFrame.origin.x + kSPMTabBarCellInternalXMargin;
    result.origin.y = cellFrame.origin.y + floor((cellFrame.size.height - result.size.height) / 2.0);

    return result;
}

- (NSRect)iconRectForTabCell:(PSMTabBarCell *)cell {
    NSRect cellFrame = [cell frame];

    if ([cell hasIcon] == NO) {
        return NSZeroRect;
    }

    CGFloat minX;
    if ([cell count]) {
        NSRect objectCounterRect = [self objectCounterRectForTabCell:cell];
        minX = NSMinX(objectCounterRect);
    } else if (![[cell indicator] isHidden]) {
        minX = NSMinX([self indicatorRectForTabCell:cell]) - kSPMTabBarCellInternalXMargin;
    } else {
        minX = NSMaxX(cellFrame) - kSPMTabBarCellInternalXMargin;
    }
    NSRect result;
    result.size = NSMakeSize(kPSMTabBarIconWidth, kPSMTabBarIconWidth);
    result.origin.x = minX - kPSMTabBarCellIconPadding - kPSMTabBarIconWidth;
    result.origin.y = cellFrame.origin.y + floor((cellFrame.size.height - result.size.height) / 2.0);

    return result;
}

- (NSRect)indicatorRectForTabCell:(PSMTabBarCell *)cell {
    NSRect cellFrame = [cell frame];

    CGFloat minX;
    if ([cell count]) {
        // Indicator to the left of the tab number
        NSRect objectCounterRect = [self objectCounterRectForTabCell:cell];
        minX = NSMinX(objectCounterRect);
    } else {
        // Indicator on the right edge of the tab.
        minX = NSMaxX(cellFrame) - kSPMTabBarCellInternalXMargin;
    }
    NSRect result;
    result.size = NSMakeSize(kPSMTabBarIndicatorWidth, kPSMTabBarIndicatorWidth);
    result.origin.x = minX - kPSMTabBarCellIconPadding - kPSMTabBarIndicatorWidth;
    result.origin.y = cellFrame.origin.y + floor((cellFrame.size.height - result.size.height) / 2.0);

    return result;
}

- (NSRect)objectCounterRectForTabCell:(PSMTabBarCell *)cell {
    NSRect cellFrame = [cell frame];

    if ([cell count] == 0) {
        return NSZeroRect;
    }

    float countWidth = [[self attributedObjectCountValueForTabCell:cell] size].width;
    countWidth += (2 * kPSMMetalObjectCounterRadius - 6.0);
    if (countWidth < kPSMMetalCounterMinWidth) {
        countWidth = kPSMMetalCounterMinWidth;
    }

    NSRect result;
    result.size = NSMakeSize(countWidth, 2 * kPSMMetalObjectCounterRadius); // temp
    result.origin.x = cellFrame.origin.x + cellFrame.size.width - kSPMTabBarCellInternalXMargin - result.size.width;
    result.origin.y = cellFrame.origin.y + floor((cellFrame.size.height - result.size.height) / 2.0);

    return result;
}

- (CGFloat)widthOfLeftMatterInCell:(PSMTabBarCell *)cell {
    CGFloat resultWidth = 0.0;

    // left margin
    resultWidth = kSPMTabBarCellInternalXMargin;

    // close button?
    resultWidth += [_closeButton size].width + kPSMTabBarCellPadding;

    // icon?
    if ([cell hasIcon]) {
        resultWidth += kPSMTabBarIconWidth + kPSMTabBarCellIconPadding;
    }
    return resultWidth;
}

- (CGFloat)widthOfRightMatterInCell:(PSMTabBarCell *)cell {
    CGFloat resultWidth = 0;
    // object counter?
    if ([cell count] > 0) {
        resultWidth += [self objectCounterRectForTabCell:cell].size.width + kPSMTabBarCellPadding;
    } else {
        resultWidth += [_closeButton size].width + kPSMTabBarCellPadding;
    }

    // indicator?
    if ([[cell indicator] isHidden] == NO) {
        resultWidth += kPSMTabBarCellPadding + kPSMTabBarIndicatorWidth;
    }

    // right margin
    resultWidth += kSPMTabBarCellInternalXMargin;
    return resultWidth;
}

- (float)minimumWidthOfTabCell:(PSMTabBarCell *)cell {
    return ceil([self widthOfLeftMatterInCell:cell] +
                kPSMMinimumTitleWidth +
                [self widthOfRightMatterInCell:cell]);
}

- (CGFloat)widthOfAttributedStringInCell:(PSMTabBarCell *)cell {
    NSAttributedString *attributedString = [cell attributedStringValue];
    if (![cell.previousAttributedString isEqualToAttributedString:attributedString]) {
        cell.previousAttributedString = attributedString;
        CGFloat width = [attributedString size].width;
        cell.previousWidthOfAttributedString = width;
        return width;
    } else {
        return cell.previousWidthOfAttributedString;
    }
}

- (float)desiredWidthOfTabCell:(PSMTabBarCell *)cell {
    return ceil([self widthOfLeftMatterInCell:cell] +
                [self widthOfAttributedStringInCell:cell] +
                [self widthOfRightMatterInCell:cell]);
}

#pragma mark - Cell Values

- (NSAttributedString *)attributedObjectCountValueForTabCell:(PSMTabBarCell *)cell {
    NSNumberFormatter *nf = [[[NSNumberFormatter alloc] init] autorelease];
    [nf setLocalizesFormat:YES];
    [nf setFormat:@"0"];
    [nf setHasThousandSeparators:YES];
    NSString *contents = [nf stringFromNumber:[NSNumber numberWithInt:[cell count]]];
    if ([cell count] < 9) {
        contents = [NSString stringWithFormat:@"%@%@", [cell modifierString], contents];
    } else if ([cell isLast]) {
        contents = [NSString stringWithFormat:@"%@9", [cell modifierString]];
    } else {
        contents = @"";
    }
    NSDictionary *attributes =
        @{ NSFontAttributeName: [NSFont systemFontOfSize:self.fontSize],
           NSForegroundColorAttributeName: [self textColorForCell:cell] };
    return [[[NSMutableAttributedString alloc] initWithString:contents
                                                   attributes:attributes]
               autorelease];
}

- (NSColor *)textColorDefaultSelected:(BOOL)selected {
    if (selected) {
        return [NSColor blackColor];
    } else if ([self isYosemiteOrLater]) {
        return [NSColor colorWithSRGBRed:101/255.0 green:100/255.0 blue:101/255.0 alpha:1];
    } else {
        return [NSColor colorWithSRGBRed:80/255.0 green:100/255.0 blue:101/255.0 alpha:1];
    }
}

- (NSColor *)textColorForCell:(PSMTabBarCell *)cell {
    NSColor *textColor;
    if (cell.state == NSOnState) {
        if (!cell.tabColor) {
            return [self textColorDefaultSelected:YES];
        } else if ([cell.tabColor brightnessComponent] > 0.2) {
            textColor = [NSColor blackColor];
        } else {
            // dark tab
            textColor = [NSColor whiteColor];
        }
    } else {
        textColor = [self textColorDefaultSelected:NO];
    }
    return textColor;
}

- (NSAttributedString *)attributedStringValueForTabCell:(PSMTabBarCell *)cell {
    // Paragraph Style for Truncating Long Text
    NSMutableParagraphStyle *truncatingTailParagraphStyle =
        [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
    [truncatingTailParagraphStyle setLineBreakMode:[cell truncationStyle]];
    if (_orientation == PSMTabBarHorizontalOrientation) {
        [truncatingTailParagraphStyle setAlignment:NSCenterTextAlignment];
    } else {
        [truncatingTailParagraphStyle setAlignment:NSLeftTextAlignment];
    }

    NSDictionary *attributes = @{ NSFontAttributeName: [NSFont systemFontOfSize:self.fontSize],
                                  NSForegroundColorAttributeName: [self textColorForCell:cell],
                                  NSParagraphStyleAttributeName: truncatingTailParagraphStyle };
    return [[[NSAttributedString alloc] initWithString:[cell stringValue]
                                            attributes:attributes] autorelease];
}

- (CGFloat)fontSize {
    return 11.0;
}

#pragma mark - Drawing

- (NSColor *)topLineColorSelected:(BOOL)selected {
    if (_tabBar.window.isKeyWindow && [NSApp isActive]) {
        if (selected) {
            return [NSColor colorWithSRGBRed:189/255.0 green:189/255.0 blue:189/255.0 alpha:1];
        } else {
            return [NSColor colorWithSRGBRed:160/255.0 green:160/255.0 blue:160/255.0 alpha:1];
        }
    } else {
        return [NSColor colorWithSRGBRed:219/255.0 green:219/255.0 blue:219/255.0 alpha:1];
    }
}

- (NSColor *)verticalLineColor {
    if (_tabBar.window.isKeyWindow && [NSApp isActive]) {
        return [NSColor colorWithSRGBRed:160/255.0 green:160/255.0 blue:160/255.0 alpha:1];
    } else {
        return [NSColor colorWithSRGBRed:219/255.0 green:219/255.0 blue:219/255.0 alpha:1];
    }
}

- (NSColor *)bottomLineColorSelected:(BOOL)selected {
    if (_tabBar.window.isKeyWindow && [NSApp isActive]) {
        return [NSColor colorWithSRGBRed:160/255.0 green:160/255.0 blue:160/255.0 alpha:1];
    } else {
        return [NSColor colorWithSRGBRed:210/255.0 green:210/255.0 blue:210/255.0 alpha:1];
    }
}

- (NSColor *)backgroundColorSelected:(BOOL)selected highlightAmount:(CGFloat)highlightAmount {
    if (selected) {
        if (_tabBar.window.backgroundColor) {
            return _tabBar.window.backgroundColor;
        } else {
            return [NSColor windowBackgroundColor];
        }
    } else {
        if ([self isYosemiteOrLater]) {
            CGFloat value;
            if (_tabBar.window.isKeyWindow && [NSApp isActive]) {
                value = 190/255.0 - highlightAmount * 0.048;
            } else {
                // Make inactive windows' background color lighter
                value = 236/255.0 - highlightAmount * 0.048;
            }
            return [NSColor colorWithSRGBRed:value green:value blue:value alpha:1];
        } else {
            // 10.9 and earlier needs a darker color to look good
            CGFloat value = 0.6 - highlightAmount * 0.048;
            return [NSColor colorWithSRGBRed:value green:value blue:value alpha:1];
        }
    }
}

- (BOOL)isYosemiteOrLater {
    return NSClassFromString(@"NSVisualEffectView") != nil;
}

- (void)drawHorizontalLineInFrame:(NSRect)rect y:(CGFloat)y {
    NSRectFill(NSMakeRect(NSMinX(rect), y, rect.size.width + 1, 1));
}

- (void)drawVerticalLineInFrame:(NSRect)rect x:(CGFloat)x {
    NSRectFill(NSMakeRect(x, NSMinY(rect) + 1, 1, rect.size.height - 2));
}

- (void)drawCellBackgroundAndFrameHorizontallyOriented:(BOOL)horizontal
                                                inRect:(NSRect)cellFrame
                                              selected:(BOOL)selected
                                          withTabColor:(NSColor *)tabColor
                                                isLast:(BOOL)isLast
                                       highlightAmount:(CGFloat)highlightAmount {
    [[self backgroundColorSelected:selected highlightAmount:highlightAmount] set];
    NSRectFill(cellFrame);

    if (tabColor) {
        // Alpha the non-key window's tab colors a bit to make it clearer which window is key.
        CGFloat alpha = [_tabBar.window isKeyWindow] ? 0.8 : 0.6;
        
        // Alpha the inactive tab's colors a bit to make it clear which tab is active.
        if (selected) {
            [[tabColor colorWithAlphaComponent:alpha] set];
            NSRectFillUsingOperation(cellFrame, NSCompositeSourceOver);
        } else {
            NSColor *startingColor = [tabColor colorWithAlphaComponent:alpha - 0.2];
            NSColor *endingColor = [tabColor colorWithAlphaComponent:0];
            NSGradient *gradient = [[[NSGradient alloc] initWithStartingColor:startingColor endingColor:endingColor] autorelease];
            [gradient drawInRect:cellFrame angle:-90];
        }
    }

    if (horizontal) {
        BOOL isLeftmostTab = NSMinX(cellFrame) == 0;
        if (!isLeftmostTab) {
            // Left line
            [[self verticalLineColor] set];
            [self drawVerticalLineInFrame:cellFrame x:NSMinX(cellFrame)];
        }
        // Right line
        CGFloat adjustment = 0;
        [[self verticalLineColor] set];
        [self drawVerticalLineInFrame:cellFrame x:NSMaxX(cellFrame) + adjustment];

        // Top line
        [[self topLineColorSelected:selected] set];
        if (isLast) {
            NSRect rect = cellFrame;
            rect.size.width -= 1;
            [self drawHorizontalLineInFrame:rect y:NSMinY(cellFrame)];
        } else {
            [self drawHorizontalLineInFrame:cellFrame y:NSMinY(cellFrame)];
        }

        // Bottom line
        [[self bottomLineColorSelected:selected] set];
        [self drawHorizontalLineInFrame:cellFrame y:NSMaxY(cellFrame) - 1];

    } else {
        // Bottom line
        [[self verticalLineColor] set];
        cellFrame.origin.x += 1;
        cellFrame.size.width -= 3;
        [self drawHorizontalLineInFrame:cellFrame y:NSMaxY(cellFrame) - 1];
        cellFrame.origin.x -= 1;
        cellFrame.size.width += 3;

        cellFrame.size.width -= 1;
        cellFrame.origin.y -= 1;
        cellFrame.size.height += 2;

        // Left line
        [[self topLineColorSelected:selected] set];
        [self drawVerticalLineInFrame:cellFrame x:NSMinX(cellFrame)];

        // Right line
        [[self bottomLineColorSelected:selected] set];
        [self drawVerticalLineInFrame:cellFrame x:NSMaxX(cellFrame)];
    }
}

- (void)drawTabCell:(PSMTabBarCell *)cell highlightAmount:(CGFloat)highlightAmount {
    // TODO: Test hidden control, whose height is less than 2. Maybe it happens while dragging?
    [self drawCellBackgroundAndFrameHorizontallyOriented:(_orientation == PSMTabBarHorizontalOrientation)
                                                  inRect:cell.frame
                                                selected:([cell state] == NSOnState)
                                            withTabColor:[cell tabColor]
                                                  isLast:cell == _tabBar.cells.lastObject
                                         highlightAmount:highlightAmount];

    [self drawInteriorWithTabCell:cell inView:[cell controlView] highlightAmount:highlightAmount];
}


- (void)drawInteriorWithTabCell:(PSMTabBarCell *)cell
                         inView:(NSView*)controlView
                highlightAmount:(CGFloat)highlightAmount {
    NSRect cellFrame = [cell frame];
    float labelPosition = cellFrame.origin.x + kSPMTabBarCellInternalXMargin;

    // close button
    NSSize closeButtonSize = NSZeroSize;
    NSRect closeButtonRect = [cell closeButtonRectForFrame:cellFrame];
    NSImage *closeButton = nil;

    closeButton = _closeButton;
    if ([cell closeButtonOver]) {
        closeButton = _closeButtonOver;
    }
    if ([cell closeButtonPressed]) {
        closeButton = _closeButtonDown;
    }

    CGFloat reservedSpace = 0;
    closeButtonSize = [closeButton size];
    if ([cell hasCloseButton]) {
        if (cell.isCloseButtonSuppressed && _orientation == PSMTabBarHorizontalOrientation) {
            // Do not use this much space on the left for the label, but the label is centered as
            // though it is not reserved if it's not too long.
            //
            //                Center
            //                   V
            // [(reserved)  short-label            ]
            // [(reserved)long-------------label   ]
            reservedSpace = closeButtonSize.width + kPSMTabBarCellPadding;
        } else {
            labelPosition += closeButtonSize.width + kPSMTabBarCellPadding;
        }
    }

    // Draw close button
    if ([cell hasCloseButton] && [cell closeButtonVisible]) {
        CGFloat fraction;
        if (cell.isCloseButtonSuppressed) {
            fraction = highlightAmount;
        } else {
            fraction = 1;
        }
        [closeButton drawAtPoint:closeButtonRect.origin
                        fromRect:NSZeroRect
                       operation:NSCompositeSourceOver
                        fraction:fraction];

    }


    // icon
    NSRect iconRect = NSZeroRect;
    if ([cell hasIcon]) {
        iconRect = [self iconRectForTabCell:cell];
        NSImage *icon = [(id)[[cell representedObject] identifier] icon];

        // center in available space (in case icon image is smaller than kPSMTabBarIconWidth)
        if ([icon size].width < kPSMTabBarIconWidth) {
            iconRect.origin.x += (kPSMTabBarIconWidth - [icon size].width)/2.0;
        }
        if ([icon size].height < kPSMTabBarIconWidth) {
            iconRect.origin.y -= (kPSMTabBarIconWidth - [icon size].height)/2.0;
        }

        [icon drawInRect:iconRect
                fromRect:NSZeroRect
               operation:NSCompositeSourceOver
                fraction:1.0
          respectFlipped:YES
                   hints:nil];
    }

    // object counter
    if ([cell count] > 0) {
        NSRect myRect = [self objectCounterRectForTabCell:cell];
        // draw attributed string centered in area
        NSRect counterStringRect;
        NSAttributedString *counterString = [self attributedObjectCountValueForTabCell:cell];
        counterStringRect.size = [counterString size];
        counterStringRect.origin.x = myRect.origin.x + floor((myRect.size.width - counterStringRect.size.width) / 2.0);
        counterStringRect.origin.y = myRect.origin.y + floor((myRect.size.height - counterStringRect.size.height) / 2.0);
        [counterString drawInRect:counterStringRect];
    }

    // label rect
    NSAttributedString *attributedString = [cell attributedStringValue];
    if (attributedString.length > 0) {
        NSRect labelRect;
        labelRect.origin.x = labelPosition;
        labelRect.size.width = cellFrame.size.width - (labelRect.origin.x - cellFrame.origin.x) - kPSMTabBarCellPadding;
        if ([cell hasIcon]) {
            // Reduce size of label if there is an icon or activity indicator
            labelRect.size.width -= iconRect.size.width + kPSMTabBarCellIconPadding;
        } else if (![[cell indicator] isHidden]) {
            labelRect.size.width -= cell.indicator.frame.size.width + kPSMTabBarCellIconPadding;
        }
        labelRect.size.height = cellFrame.size.height;

        if ([cell count] > 0) {
            labelRect.size.width -= ([self objectCounterRectForTabCell:cell].size.width + kPSMTabBarCellPadding);
        }

        NSSize boundingSize = [attributedString boundingRectWithSize:labelRect.size options:0].size;
        labelRect.origin.y = cellFrame.origin.y + floor((cellFrame.size.height - boundingSize.height) / 2.0);
        labelRect.size.height = boundingSize.height;

        if (_orientation == PSMTabBarHorizontalOrientation) {
            CGFloat effectiveLeftMargin = (labelRect.size.width - boundingSize.width) / 2;
            if (effectiveLeftMargin < reservedSpace) {
                attributedString = [attributedString attributedStringWithTextAlignment:NSLeftTextAlignment];

                labelRect.origin.x += reservedSpace;
                labelRect.size.width -= reservedSpace;
            }
        }

        [attributedString drawInRect:labelRect];
    }
}

- (NSColor *)tabBarColor {
    if (_tabBar.window.isKeyWindow && [NSApp isActive]) {
        return [NSColor colorWithCalibratedWhite:0.0 alpha:0.2];
    } else {
        return [NSColor colorWithCalibratedWhite:236 / 255.0 alpha:1];
    }
}

- (void)drawBackgroundInRect:(NSRect)rect
                       color:(NSColor*)backgroundColor
                  horizontal:(BOOL)horizontal {
    if (_orientation == PSMTabBarVerticalOrientation && [_tabBar frame].size.width < 2) {
        return;
    }

    [NSGraphicsContext saveGraphicsState];
    [[NSGraphicsContext currentContext] setShouldAntialias:NO];

    [backgroundColor set];
    NSRectFillUsingOperation(rect, NSCompositeSourceAtop);

    [[self bottomLineColorSelected:NO] set];
    if (_orientation == PSMTabBarHorizontalOrientation) {
        [NSBezierPath strokeLineFromPoint:NSMakePoint(rect.origin.x,
                                                      rect.origin.y + rect.size.height - 0.5) 
                                  toPoint:NSMakePoint(rect.origin.x + rect.size.width,
                                                      rect.origin.y + rect.size.height - 0.5)];

        [[self topLineColorSelected:NO] set];
        // this looks ok with tabs on top but doesn't appear w/ tabs on bottom for some reason
        [NSBezierPath strokeLineFromPoint:NSMakePoint(rect.origin.x,
                                                      rect.origin.y - 0.5)
                                  toPoint:NSMakePoint(rect.origin.x + rect.size.width,
                                                      rect.origin.y - 0.5)];
    } else {
        [NSBezierPath strokeLineFromPoint:NSMakePoint(rect.origin.x,
                                                      rect.origin.y + 0.5)
                                  toPoint:NSMakePoint(rect.origin.x,
                                                      rect.origin.y + rect.size.height + 0.5)];
        
        [NSBezierPath strokeLineFromPoint:NSMakePoint(rect.origin.x + rect.size.width,
                                                      rect.origin.y + 0.5)
                                  toPoint:NSMakePoint(rect.origin.x + rect.size.width,
                                                      rect.origin.y + rect.size.height + 0.5)];
    }

    [NSGraphicsContext restoreGraphicsState];
}

- (NSColor *)accessoryFillColor {
    return [NSColor windowBackgroundColor];
}

- (NSColor *)accessoryStrokeColor {
    return [NSColor darkGrayColor];
}

- (NSColor *)accessoryTextColor {
    return [NSColor blackColor];
}

- (void)fillPath:(NSBezierPath*)path {
    [[self accessoryFillColor] set];
    [path fill];
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.2] set];
    [path fill];
    [[self accessoryStrokeColor] set];
    [path stroke];
}

- (BOOL)useLightControls {
    return NO;
}

- (void)drawTabBar:(PSMTabBarControl *)bar
            inRect:(NSRect)rect
        horizontal:(BOOL)horizontal {
    if (_orientation != [bar orientation]) {
        _orientation = [bar orientation];
    }

    if (_tabBar != bar) {
        _tabBar = bar;
    }

    [self drawBackgroundInRect:rect color:[self tabBarColor] horizontal:horizontal];
    [[self topLineColorSelected:NO] set];
    [self drawHorizontalLineInFrame:rect y:NSMinY(rect)];

    // no tab view == not connected
    if (![bar tabView]){
        NSRect labelRect = rect;
        labelRect.size.height -= 4.0;
        labelRect.origin.y += 4.0;
        NSString *contents = @"PSMTabBarControl";
        NSMutableAttributedString *attrStr =
            [[[NSMutableAttributedString alloc] initWithString:contents] autorelease];
        NSRange range = NSMakeRange(0, [contents length]);
        [attrStr addAttribute:NSFontAttributeName
                        value:[NSFont systemFontOfSize:self.fontSize]
                        range:range];
        NSMutableParagraphStyle *centeredParagraphStyle =
            [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
        [centeredParagraphStyle setAlignment:NSCenterTextAlignment];
        [attrStr addAttribute:NSParagraphStyleAttributeName
                        value:centeredParagraphStyle
                        range:range];
        [attrStr drawInRect:labelRect];
        return;
    }

    // draw cells
    for (int i = 0; i < 2; i++) {
        NSInteger stateToDraw = (i == 0 ? NSOnState : NSOffState);
        for (PSMTabBarCell *cell in [bar cells]) {
            if (![cell isInOverflowMenu] && NSIntersectsRect([cell frame], rect)) {
                if (cell.state == stateToDraw) {
                    [cell drawWithFrame:[cell frame] inView:bar];
                    if (stateToDraw == NSOnState) {
                        // Can quit early since only one can be selected
                        break;
                    }
                }
            }
        }
    }
}

#pragma mark - Archiving

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    if ([aCoder allowsKeyedCoding]) {
        [aCoder encodeObject:_closeButton forKey:@"metalCloseButton"];
        [aCoder encodeObject:_closeButtonDown forKey:@"metalCloseButtonDown"];
        [aCoder encodeObject:_closeButtonOver forKey:@"metalCloseButtonOver"];
        [aCoder encodeObject:_addTabButtonImage forKey:@"addTabButtonImage"];
        [aCoder encodeObject:_addTabButtonPressedImage forKey:@"addTabButtonPressedImage"];
        [aCoder encodeObject:_addTabButtonRolloverImage forKey:@"addTabButtonRolloverImage"];
    }
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super init];
    if (self) {
        if ([aDecoder allowsKeyedCoding]) {
            _closeButton = [[aDecoder decodeObjectForKey:@"metalCloseButton"] retain];
            _closeButtonDown = [[aDecoder decodeObjectForKey:@"metalCloseButtonDown"] retain];
            _closeButtonOver = [[aDecoder decodeObjectForKey:@"metalCloseButtonOver"] retain];
            _addTabButtonImage = [[aDecoder decodeObjectForKey:@"addTabButtonImage"] retain];
            _addTabButtonPressedImage = [[aDecoder decodeObjectForKey:@"addTabButtonPressedImage"] retain];
            _addTabButtonRolloverImage = [[aDecoder decodeObjectForKey:@"addTabButtonRolloverImage"] retain];
        }
    }
    return self;
}

@end
