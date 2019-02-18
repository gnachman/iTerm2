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

@interface NSColor (PSMYosemiteTabStyle)

- (NSColor *)it_srgbForColorInWindow:(NSWindow *)window;

@end

@implementation NSColor (PSMYosemiteTabStyle)

// http://www.nbdtech.com/Blog/archive/2008/04/27/Calculating-the-Perceived-Brightness-of-a-Color.aspx
// http://alienryderflex.com/hsp.html
- (NSColor *)it_srgbForColorInWindow:(NSWindow *)window {
    if ([self isEqual:window.backgroundColor]) {
        if ([window.effectiveAppearance.name isEqualToString:NSAppearanceNameVibrantDark]) {
            return [NSColor colorWithSRGBRed:0.25 green:0.25 blue:0.25 alpha:1];
        } else {
            return [NSColor colorWithSRGBRed:0.75 green:0.75 blue:0.75 alpha:1];
        }
    } else {
        return [self colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    }
}

- (CGFloat)it_hspBrightness {
    NSColor *safeColor = [self colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    const CGFloat r = safeColor.redComponent;
    const CGFloat g = safeColor.greenComponent;
    const CGFloat b = safeColor.blueComponent;
    return sqrt(r * r * .241 +
                g * g * .691 +
                b * b * .068);
}

@end

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
}

@synthesize tabBar = _tabBar;

- (NSString *)name {
    return @"Yosemite";
}

#pragma mark -
#pragma mark Creation/Destruction

- (id)init {
    if ((self = [super init]))  {
        // Load close buttons 
        _closeButton = [[[NSBundle bundleForClass:self.class] imageForResource:@"TabClose_Front"] retain];
        _closeButtonDown = [[[NSBundle bundleForClass:self.class] imageForResource:@"TabClose_Front_Pressed"] retain];
        _closeButtonOver = [[[NSBundle bundleForClass:self.class] imageForResource:@"TabClose_Front_Rollover"] retain];

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

#pragma mark - Utility

- (BOOL)windowIsMainAndAppIsActive {
    return (self.tabBar.window.isMainWindow &&
            [NSApp isActive]);
}

#pragma mark - Control Specific

- (float)leftMarginForTabBarControl {
    return self.tabBar.insets.left;
}

- (float)rightMarginForTabBarControl {
    // Leaves space for overflow control.
    return 24.0f;
}

// For vertical orientation
- (float)topMarginForTabBarControl {
    return self.tabBar.insets.top;
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
    result.origin.y = cellFrame.origin.y + floor((cellFrame.size.height - result.size.height) / 2.0) - 1;

    return result;
}

- (NSRect)graphicRectForTabCell:(PSMTabBarCell *)cell x:(CGFloat)xOrigin {
    NSRect cellFrame = [cell frame];
    
    CGFloat minX = xOrigin;
    NSRect result;
    result.size = PSMTabBarGraphicSize;
    result.origin.x = minX;
    result.origin.y = cellFrame.origin.y + floor((cellFrame.size.height - result.size.height) / 2.0) - 1;
    
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

- (NSColor *)textColorDefaultSelected:(BOOL)selected backgroundColor:(NSColor *)backgroundColor windowIsMainAndAppIsActive:(BOOL)mainAndActive {
    CGFloat value;
    if (mainAndActive) {
        value = 0;
    } else {
        if (selected) {
            if (@available(macOS 10.14, *)) {
                value = 189;
            } else {
                value = 0;
            }
        } else {
            if (@available(macOS 10.14, *)) {
                value = 164;
            } else {
                value = 100;
            }
        }
    }
    return [NSColor colorWithSRGBRed:value/255.0 green:value/255.0 blue:value/255.0 alpha:1];
}

- (NSColor *)textColorForCell:(PSMTabBarCell *)cell {
    DLog(@"cell=%@", cell);
    const BOOL selected = (cell.state == NSOnState);
    if ([self anyTabHasColor]) {
        DLog(@"anyTabHasColor. computing tab color brightness.");
        CGFloat cellBrightness = [self tabColorBrightness:cell];
        DLog(@"brightness of %@ is %@", cell, @(cellBrightness));
        if (selected) {
            DLog(@"is selected");
            // Select cell when any cell has a tab color
            if (cellBrightness > 0.5) {
                DLog(@"is bright. USE BLACK TEXT COLOR");
                // bright tab
                return [NSColor blackColor];
            } else {
                DLog(@"is dark. Use white text");
                // dark tab
                return [NSColor whiteColor];
            }
        } else {
            DLog(@"Not selected");
            // Non-selected cell when any cell has a tab color
            CGFloat prominence = [[_tabBar.delegate tabView:_tabBar valueOfOption:PSMTabBarControlOptionColoredUnselectedTabTextProminence] doubleValue];
            if (@available(macOS 10.14, *)) {
                if (cellBrightness > 0.5) {
                    // Light tab
                    return [NSColor colorWithWhite:0 alpha:prominence];
                } else {
                    // Dark tab
                    return [NSColor colorWithWhite:1 alpha:prominence];
                }
            } else {
                // 10.13 and earlier. Don't count on it blending competently.
                CGFloat delta = prominence ?: 0.1;
                if (cellBrightness > 0.5) {
                    // Light tab
                    return [NSColor colorWithWhite:cellBrightness - delta alpha:1];
                } else {
                    // Dark tab
                    return [NSColor colorWithWhite:cellBrightness + delta alpha:1];
                }
            }
        }
    } else {
        DLog(@"No tab has color");
        // No cell has a tab color
        const BOOL mainAndActive = self.windowIsMainAndAppIsActive;
        if (selected) {
            DLog(@"selected");
            return [self textColorDefaultSelected:YES backgroundColor:nil windowIsMainAndAppIsActive:mainAndActive];
        } else {
            DLog(@"not selected");
            return [self textColorDefaultSelected:NO backgroundColor:nil windowIsMainAndAppIsActive:mainAndActive];
        }
    }
}

- (NSAttributedString *)attributedStringValueForTabCell:(PSMTabBarCell *)cell {
    // Paragraph Style for Truncating Long Text
    NSMutableParagraphStyle *truncatingTailParagraphStyle =
        [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
    [truncatingTailParagraphStyle setLineBreakMode:[cell truncationStyle]];
    if (_orientation == PSMTabBarHorizontalOrientation) {
        [truncatingTailParagraphStyle setAlignment:NSTextAlignmentCenter];
    } else {
        [truncatingTailParagraphStyle setAlignment:NSTextAlignmentLeft];
    }

    // graphic
    NSImage *graphic = [(id)[[cell representedObject] identifier] psmTabGraphic];

    NSFont *font = [NSFont systemFontOfSize:self.fontSize];
    DLog(@"Computing text color for cell %@ with title %@", cell, cell.stringValue);
    NSDictionary *attributes = @{ NSFontAttributeName: font,
                                  NSForegroundColorAttributeName: [self textColorForCell:cell],
                                  NSParagraphStyleAttributeName: truncatingTailParagraphStyle };
    NSAttributedString *textAttributedString = [[[NSAttributedString alloc] initWithString:[cell stringValue]
                                                                                attributes:attributes] autorelease];
    if (!graphic) {
        return textAttributedString;
    }
    
    NSTextAttachment *textAttachment = [[[NSTextAttachment alloc] init] autorelease];
    textAttachment.image = graphic;
    textAttachment.bounds = NSMakeRect(0,
                                       - (graphic.size.height - font.capHeight) / 2.0,
                                       graphic.size.width,
                                       graphic.size.height);
    NSAttributedString *graphicAttributedString = [NSAttributedString attributedStringWithAttachment:textAttachment];

    NSAttributedString *space = [[[NSAttributedString alloc] initWithString:@"\u2002"
                                                                 attributes:attributes] autorelease];
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [result appendAttributedString:graphicAttributedString];
    [result appendAttributedString:space];
    [result appendAttributedString:textAttributedString];
    [result enumerateAttribute:NSAttachmentAttributeName
                       inRange:NSMakeRange(0, result.length)
                       options:0
                    usingBlock:^(id  _Nullable attachment, NSRange range, BOOL * _Nonnull stop) {
                        if ([attachment isKindOfClass:[NSTextAttachment class]]) {
                            [result addAttribute:NSParagraphStyleAttributeName
                                           value:truncatingTailParagraphStyle
                                           range:range];
                        }
                    }];

    return result;
}

- (CGFloat)fontSize {
    return 11.0;
}

#pragma mark - Drawing

- (NSColor *)topLineColorSelected:(BOOL)selected {
    const BOOL keyMainAndActive = self.windowIsMainAndAppIsActive;
    if (@available(macOS 10.14, *)) {
        if (keyMainAndActive) {
            return [NSColor colorWithSRGBRed:180.0/255.0 green:180.0/255.0 blue:180.0/255.0 alpha:1];
        } else {
            return [NSColor colorWithSRGBRed:209.0/255.0 green:209.0/255.0 blue:209.0/255.0 alpha:1];
        }
    } else {
        if (keyMainAndActive) {
            if (selected) {
                return [NSColor colorWithSRGBRed:189/255.0 green:189/255.0 blue:189/255.0 alpha:1];
            } else {
                return [NSColor colorWithSRGBRed:160/255.0 green:160/255.0 blue:160/255.0 alpha:1];
            }
        } else {
            return [NSColor colorWithSRGBRed:219/255.0 green:219/255.0 blue:219/255.0 alpha:1];
        }
    }
}

- (NSColor *)verticalLineColorSelected:(BOOL)selected {
    const BOOL keyMainAndActive = self.windowIsMainAndAppIsActive;
    if (@available(macOS 10.14, *)) {
        if (keyMainAndActive) {
            return [NSColor colorWithSRGBRed:174.0/255.0 green:174.0/255.0 blue:174.0/255.0 alpha:1];
        } else {
            return [NSColor colorWithSRGBRed:209.0/255.0 green:209.0/255.0 blue:209.0/255.0 alpha:1];
        }
    } else {
        if (keyMainAndActive) {
            return [NSColor colorWithSRGBRed:160/255.0 green:160/255.0 blue:160/255.0 alpha:1];
        } else {
            return [NSColor colorWithSRGBRed:219/255.0 green:219/255.0 blue:219/255.0 alpha:1];
        }
    }
}

- (NSColor *)bottomLineColorSelected:(BOOL)selected {
    if (@available(macOS 10.14, *)) {
        return [NSColor colorWithWhite:0 alpha:0.15];
    } else {
        const BOOL keyMainAndActive = self.windowIsMainAndAppIsActive;
        if (keyMainAndActive) {
            return [NSColor colorWithSRGBRed:160/255.0 green:160/255.0 blue:160/255.0 alpha:1];
        } else {
            return [NSColor colorWithSRGBRed:210/255.0 green:210/255.0 blue:210/255.0 alpha:1];
        }
    }
}

- (NSColor *)legacyBackgroundColorSelected:(BOOL)selected highlightAmount:(CGFloat)highlightAmount NS_DEPRECATED_MAC(10_12, 10_13) {
    if (selected) {
        if (@available(macOS 10.14, *)) {
            const CGFloat value = 246.0 / 255.0;
            return [NSColor colorWithSRGBRed:value green:value blue:value alpha:1];
        }
        if (_tabBar.window.backgroundColor) {
            return _tabBar.window.backgroundColor;
        } else {
            return [NSColor windowBackgroundColor];
        }
    } else {
        CGFloat value;
        const BOOL keyMainAndActive = self.windowIsMainAndAppIsActive;
        if (keyMainAndActive) {
            value = 190/255.0 - highlightAmount * 0.048;
        } else {
            // Make inactive windows' background color lighter
            if (@available(macOS 10.14, *)) {
                value = 221/255.0 - highlightAmount * 0.048;
            } else {
                value = 236/255.0 - highlightAmount * 0.048;
            }
        }
        return [NSColor colorWithSRGBRed:value green:value blue:value alpha:1];
    }
}
- (NSColor *)mojaveBackgroundColorSelected:(BOOL)selected highlightAmount:(CGFloat)highlightAmount NS_AVAILABLE_MAC(10_14) {
    CGFloat colors[3];
    const BOOL keyMainAndActive = self.windowIsMainAndAppIsActive;
    if (keyMainAndActive) {
        if (selected) {
            colors[0] = 210.0 / 255.0;
            colors[1] = 210.0 / 255.0;
            colors[2] = 210.0 / 255.0;
        } else {
            NSColor *color = self.tabBarColor;
            colors[0] = color.redComponent;
            colors[1] = color.greenComponent;
            colors[2] = color.blueComponent;
        }
    } else {
        if (selected) {
            colors[0] = 246.0 / 255.0;
            colors[1] = 246.0 / 255.0;
            colors[2] = 246.0 / 255.0;
        } else {
            NSColor *color = self.tabBarColor;
            colors[0] = color.redComponent;
            colors[1] = color.greenComponent;
            colors[2] = color.blueComponent;
        }
    }
    CGFloat highlightedColors[3] = { 0, 0, 0 };
    CGFloat a = 0;
    if (!selected) {
        a = highlightAmount * 0.05;
    }
    for (int i = 0; i < 3; i++) {
        colors[i] = colors[i] * (1.0 - a) + highlightedColors[i] * a;
    }

    return [NSColor colorWithSRGBRed:colors[0]
                               green:colors[1]
                                blue:colors[2]
                               alpha:1];
}

- (NSColor *)backgroundColorSelected:(BOOL)selected highlightAmount:(CGFloat)highlightAmount {
    if (@available(macOS 10.14, *)) {
        return [self mojaveBackgroundColorSelected:selected highlightAmount:highlightAmount];
    } else {
        return [self legacyBackgroundColorSelected:selected highlightAmount:highlightAmount];
    }
}

- (void)drawHorizontalLineInFrame:(NSRect)rect y:(CGFloat)y {
    NSRectFillUsingOperation(NSMakeRect(NSMinX(rect), y, rect.size.width + 1, 1),
                             NSCompositingOperationSourceOver);
}

- (void)drawVerticalLineInFrame:(NSRect)rect x:(CGFloat)x {
    CGFloat topInset = 1;
    CGFloat bottomInset = 1;
    if (@available(macOS 10.14, *)) {
        bottomInset = 0;
    }
    NSRect modifiedRect = NSMakeRect(x, NSMinY(rect) + topInset, 1, rect.size.height - topInset - bottomInset);
    NSRectFillUsingOperation(modifiedRect, NSCompositingOperationSourceOver);
}

- (NSColor *)cellBackgroundColorForTabColor:(NSColor *)tabColor
                                    selected:(BOOL)selected {
    // Alpha the non-key window's tab colors a bit to make it clearer which window is key.
    CGFloat alpha;
    const BOOL keyMainAndActive = self.windowIsMainAndAppIsActive;
    if (keyMainAndActive) {
        if (selected) {
            alpha = 1;
        } else {
            alpha = 0.4;
        }
    } else {
        if (selected) {
            alpha = 0.6;
        } else {
            alpha = 0.3;
        }
    }
    CGFloat components[4];
    [tabColor getComponents:components];
    for (int i = 0; i < 3; i++) {
        components[i] = components[i] * alpha + 0.5 * (1 - alpha);
    }
    NSColor *color = [NSColor colorWithColorSpace:tabColor.colorSpace components:components count:4];
    return color;
}

- (NSColor *)effectiveBackgroundColorForTabWithTabColor:(NSColor *)tabColor
                                               selected:(BOOL)selected
                                        highlightAmount:(CGFloat)highlightAmount
                                                 window:(NSWindow *)window {
    DLog(@"Computing effective background color for tab with color %@ selected=%@ highlight=%@", tabColor, @(selected), @(highlightAmount));
    NSColor *base = [[self backgroundColorSelected:selected highlightAmount:highlightAmount] it_srgbForColorInWindow:window];
    DLog(@"base=%@", base);
    if (tabColor) {
        NSColor *cellbg = [self cellBackgroundColorForTabColor:tabColor selected:selected];
        DLog(@"cellbg=%@", cellbg);
        NSColor *overcoat = [cellbg it_srgbForColorInWindow:window];
        DLog(@"overcoat=%@", overcoat);
        const CGFloat a = overcoat.alphaComponent;
        const CGFloat q = 1-a;
        CGFloat r = q * base.redComponent + a * overcoat.redComponent;
        CGFloat g = q * base.greenComponent + a * overcoat.greenComponent;
        CGFloat b = q * base.blueComponent + a * overcoat.blueComponent;
        CGFloat components[4] = { r, g, b, 1 };
        NSColor *result = [NSColor colorWithColorSpace:tabColor.colorSpace components:components count:4];
        DLog(@"return %@", result);
        return result;
    } else {
        DLog(@"return base %@", base);
        return base;
    }
}

- (void)drawCellBackgroundSelected:(BOOL)selected
                            inRect:(NSRect)cellFrame
                      withTabColor:(NSColor *)tabColor
                   highlightAmount:(CGFloat)highlightAmount
                        horizontal:(BOOL)horizontal {
    [[self backgroundColorSelected:selected highlightAmount:highlightAmount] set];
    NSRect backgroundRect = cellFrame;
    NSEdgeInsets backgroundInsets = [self backgroundInsetsWithHorizontalOrientation:horizontal];
    backgroundRect.origin.x += backgroundInsets.left;
    backgroundRect.origin.y += backgroundInsets.top;
    backgroundRect.size.width -= backgroundInsets.left + backgroundInsets.right;
    backgroundRect.size.height -= backgroundInsets.top + backgroundInsets.bottom;
    NSRectFill(backgroundRect);

    if (tabColor) {
        NSColor *color = [self cellBackgroundColorForTabColor:tabColor selected:selected];
        // Alpha the inactive tab's colors a bit to make it clear which tab is active.
        [color set];
        NSRectFillUsingOperation(cellFrame, NSCompositingOperationSourceOver);
    }
}

- (NSEdgeInsets)backgroundInsetsWithHorizontalOrientation:(BOOL)horizontal {
    NSEdgeInsets insets = NSEdgeInsetsZero;
    if (@available(macOS 10.14, *)) {
        insets.top = 1;
        insets.bottom = 1;
        insets.left = 1;
    } else {
      // 10.13 and earlier
      return insets;
    }
    if (!horizontal) {
        insets.left = 0.5;
        insets.top = 0;
        insets.right = 1;
    }
    return insets;
}


- (void)drawCellBackgroundAndFrameHorizontallyOriented:(BOOL)horizontal
                                                inRect:(NSRect)cellFrame
                                              selected:(BOOL)selected
                                          withTabColor:(NSColor *)tabColor
                                               isFirst:(BOOL)isFirst
                                                isLast:(BOOL)isLast
                                       highlightAmount:(CGFloat)highlightAmount {
    [self drawCellBackgroundSelected:selected
                              inRect:cellFrame
                        withTabColor:tabColor
                     highlightAmount:highlightAmount
                          horizontal:horizontal];

    if (horizontal) {
        BOOL shouldDrawLeftLine;
        if (@available(macOS 10.14, *)) {
            // Because alpha is less than 1, we don't want to double-draw. I don't think
            // drawing the left line is necessary in earlier macOS versions either but I
            // don't feel like adding any risk at the moment.
            shouldDrawLeftLine = NO;
        } else {
            shouldDrawLeftLine = !isFirst;
        }
        if (shouldDrawLeftLine) {
            // Left line
            [[self verticalLineColorSelected:selected] set];
            [self drawVerticalLineInFrame:cellFrame x:NSMinX(cellFrame)];
        }
        // Right line
        CGFloat adjustment = 0;
        [[self verticalLineColorSelected:selected] set];
        [self drawVerticalLineInFrame:cellFrame x:NSMaxX(cellFrame) + adjustment];

        // Top line
        [[self topLineColorSelected:selected] set];
        if (@available(macOS 10.14, *)) {} else {
            // 10.13 and earlier
            if (isLast) {
                NSRect rect = cellFrame;
                rect.size.width -= 1;
                [self drawHorizontalLineInFrame:rect y:NSMinY(cellFrame)];
            } else {
                [self drawHorizontalLineInFrame:cellFrame y:NSMinY(cellFrame)];
            }
        }
        // Bottom line
        [[self bottomLineColorSelected:selected] set];
        [self drawHorizontalLineInFrame:cellFrame y:NSMaxY(cellFrame) - 1];
    } else {
        // Bottom line
        [[self verticalLineColorSelected:selected] set];
        const NSEdgeInsets insets = [self insetsForTabBarDividers];
        cellFrame.origin.x += insets.left;
        cellFrame.size.width -= (insets.left + insets.right);
        [self drawHorizontalLineInFrame:cellFrame y:NSMaxY(cellFrame) - 1];
        cellFrame.origin.x -= insets.left;
        cellFrame.size.width += (insets.left + insets.right);

        cellFrame.size.width -= 1;
        cellFrame.origin.y -= 1;
        cellFrame.size.height += 2;

        // Left line
        if (@available(macOS 10.14, *)) {} else {
            // 10.13 and earlier
            [[self topLineColorSelected:selected] set];
            [self drawVerticalLineInFrame:cellFrame x:NSMinX(cellFrame)];

            // Right line
            [[self bottomLineColorSelected:selected] set];
            [self drawVerticalLineInFrame:cellFrame x:NSMaxX(cellFrame)];
        }
    }
}

- (NSEdgeInsets)insetsForTabBarDividers {
    if (@available(macOS 10.14, *)) {
        return NSEdgeInsetsMake(0, 0.5, 0, 2);
    } else {
        return NSEdgeInsetsMake(0, 1, 0, 2);
    }
}

- (void)drawTabCell:(PSMTabBarCell *)cell highlightAmount:(CGFloat)highlightAmount {
    // TODO: Test hidden control, whose height is less than 2. Maybe it happens while dragging?
    [self drawCellBackgroundAndFrameHorizontallyOriented:(_orientation == PSMTabBarHorizontalOrientation)
                                                  inRect:cell.frame
                                                selected:([cell state] == NSOnState)
                                            withTabColor:[cell tabColor]
                                                 isFirst:cell == _tabBar.cells.firstObject
                                                  isLast:cell == _tabBar.cells.lastObject
                                         highlightAmount:highlightAmount];
    [self drawInteriorWithTabCell:cell inView:[cell controlView] highlightAmount:highlightAmount];
}

- (CGFloat)tabColorBrightness:(PSMTabBarCell *)cell {
    return [[self effectiveBackgroundColorForTabWithTabColor:cell.tabColor
                                                    selected:(cell.state == NSOnState)
                                             highlightAmount:0
                                                      window:cell.controlView.window] it_hspBrightness];
}

- (BOOL)anyTabHasColor {
    return [_tabBar.cells indexOfObjectPassingTest:^BOOL(PSMTabBarCell * _Nonnull cell, NSUInteger idx, BOOL * _Nonnull stop) {
        return cell.tabColor != nil;
    }] != NSNotFound;
}

- (void)drawPostHocDecorationsOnSelectedCell:(PSMTabBarCell *)cell
                               tabBarControl:(PSMTabBarControl *)bar {
    if (self.anyTabHasColor) {
        const CGFloat brightness = [self tabColorBrightness:cell];
        NSRect rect = NSInsetRect(cell.frame, -0.5, 0.5);
        NSBezierPath *path;

        NSColor *outerColor;
        NSColor *innerColor;
        NSNumber *strengthNumber = [bar.delegate tabView:bar valueOfOption:PSMTabBarControlOptionColoredSelectedTabOutlineStrength] ?: @0.5;
        CGFloat strength = strengthNumber.doubleValue;
        const BOOL keyMainAndActive = self.windowIsMainAndAppIsActive;
        const CGFloat alpha = MIN(MAX(strength, 0), 1) * (keyMainAndActive ? 1 : 0.6);
        if (brightness > 0.5) {
            outerColor = [NSColor colorWithWhite:1 alpha:alpha];
            innerColor = [NSColor colorWithWhite:0 alpha:alpha];
        } else {
            outerColor = [NSColor colorWithWhite:0 alpha:alpha];
            innerColor = [NSColor colorWithWhite:1 alpha:alpha];
        }

        [outerColor set];
        const CGFloat width = MIN(MAX(strength, 1), 3);
        rect = NSInsetRect(rect, width - 1, width - 1);
        path = [NSBezierPath bezierPathWithRect:rect];
        [path setLineWidth:width];
        [path stroke];

        [innerColor set];
        rect = NSInsetRect(rect, width, width);
        path = [NSBezierPath bezierPathWithRect:rect];
        [path setLineWidth:width];
        [path stroke];
    }
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
                       operation:NSCompositingOperationSourceOver
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
               operation:NSCompositingOperationSourceOver
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
                attributedString = [attributedString attributedStringWithTextAlignment:NSTextAlignmentLeft];

                labelRect.origin.x += reservedSpace;
                labelRect.size.width -= reservedSpace;
            }
        }

        attributedString = [self truncateAttributedStringIfNeeded:attributedString forWidth:labelRect.size.width];
        [attributedString drawInRect:labelRect];
    }
}

// In the neverending saga of Cocoa embarassing itself, if there isn't enough space for a text
// attachment and the text that follows it, they are drawn overlapping.
- (NSAttributedString *)truncateAttributedStringIfNeeded:(NSAttributedString *)attributedString
                                                forWidth:(CGFloat)width {
    __block BOOL truncate = NO;
    [attributedString enumerateAttribute:NSAttachmentAttributeName
                                 inRange:NSMakeRange(0, 1)
                                 options:0
                              usingBlock:^(id  _Nullable value, NSRange range, BOOL * _Nonnull stop) {
                                  if (![value isKindOfClass:[NSTextAttachment class]]) {
                                      return;
                                  }
                                  NSTextAttachment *attachment = value;
                                  truncate = (attachment.image.size.width * 2 > width);
                              }];
    if (truncate) {
        return [attributedString attributedSubstringFromRange:NSMakeRange(0, 1)];
    }
    return attributedString;
}

- (NSColor *)tabBarColor {
    const BOOL keyMainAndActive = self.windowIsMainAndAppIsActive;
    if (@available(macOS 10.14, *)) {
        if (keyMainAndActive) {
            return [NSColor colorWithSRGBRed:188.0 / 255.0
                                       green:188.0 / 255.0
                                        blue:188.0 / 255.0
                                       alpha:1];
        } else {
            return [NSColor colorWithSRGBRed:221.0 / 255.0
                                       green:221.0 / 255.0
                                        blue:221.0 / 255.0
                                       alpha:1];
        }
    } else {
        if (keyMainAndActive) {
            return [NSColor colorWithCalibratedWhite:0.0 alpha:0.2];
        } else {
            return [NSColor colorWithCalibratedWhite:236 / 255.0 alpha:1];
        }
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
    if (@available(macOS 10.14, *)) {
        NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);
    } else {
        NSRectFillUsingOperation(rect, NSCompositingOperationSourceAtop);
    }

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
          clipRect:(NSRect)clipRect
        horizontal:(BOOL)horizontal {
    if (_orientation != [bar orientation]) {
        _orientation = [bar orientation];
    }

    if (_tabBar != bar) {
        _tabBar = bar;
    }

    [self drawBackgroundInRect:clipRect color:[self tabBarColor] horizontal:horizontal];
    [[self topLineColorSelected:NO] set];

    NSRect insetRect;
    if (@available(macOS 10.14, *)) {
        insetRect = NSInsetRect(rect, 1, 0);
        insetRect.size.width -= 1;
    } else {
        insetRect = clipRect;
    }
    [self drawHorizontalLineInFrame:NSIntersectionRect(clipRect, insetRect) y:0];

    // no tab view == not connected
    if (![bar tabView]) {
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
        [centeredParagraphStyle setAlignment:NSTextAlignmentCenter];
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
            if (![cell isInOverflowMenu] && NSIntersectsRect(NSInsetRect([cell frame], -1, -1), clipRect)) {
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
    if (@available(macOS 10.14, *)) {
        if (_orientation != PSMTabBarHorizontalOrientation) {
            [[self bottomLineColorSelected:NO] set];
            NSRect rightLineRect = rect;
            rightLineRect.origin.y -= 1;
            [self drawVerticalLineInFrame:rightLineRect x:NSMaxX(rect) - 1];
        }
    }
    for (PSMTabBarCell *cell in [bar cells]) {
        if (![cell isInOverflowMenu] && NSIntersectsRect([cell frame], clipRect) && cell.state == NSOnState) {
            [cell drawPostHocDecorationsOnSelectedCell:cell tabBarControl:bar];
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
