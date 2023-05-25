//
//  PSMYosemiteTabStyle.m
//  PSMTabBarControl
//
//  Created by John Pannell on 2/17/06.
//  Copyright 2006 Positive Spin Media. All rights reserved.
//

#import "PSMYosemiteTabStyle.h"

#import "NSColor+PSM.h"
#import "PSMRolloverButton.h"
#import "PSMTabBarCell.h"
#import "PSMTabBarControl.h"
#import <objc/runtime.h>

#define kPSMMetalObjectCounterRadius 7.0
#define kPSMMetalCounterMinWidth 20

@interface NSImage (External)
- (NSImage *)it_cachingImageWithTintColor:(NSColor *)tintColor key:(const void *)key;
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
        _closeButton.template = YES;
        _closeButtonDown = [[[NSBundle bundleForClass:self.class] imageForResource:@"TabClose_Front_Pressed"] retain];
        _closeButtonDown.template = YES;
        _closeButtonOver = [[[NSBundle bundleForClass:self.class] imageForResource:@"TabClose_Front_Rollover"] retain];
        _closeButtonOver.template = YES;

        // Load "new tab" buttons
        NSString *addTabImageName = @"YosemiteAddTab";
        if (@available(macOS 10.16, *)) {
            addTabImageName = @"BigSurAddTab";
        }
        _addTabButtonImage = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:addTabImageName]];
        _addTabButtonPressedImage = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:addTabImageName]];
        _addTabButtonRolloverImage = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:addTabImageName]];
        if (@available(macOS 10.16, *)) {
            _addTabButtonImage.template = YES;
            _addTabButtonPressedImage.template = YES;
            _addTabButtonRolloverImage.template = YES;
        }
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

- (NSAppearance *)accessoryAppearance {
    return nil;
}

#pragma mark - Control Specific

- (float)leftMarginForTabBarControl {
    return self.tabBar.insets.left;
}

- (float)rightMarginForTabBarControlWithOverflow:(BOOL)withOverflow
                                    addTabButton:(BOOL)withAddTabButton {
    if (withOverflow || withAddTabButton) {
        return 24.0f;
    }
    return 0;
}

// For vertical orientation
- (float)topMarginForTabBarControl {
    return self.tabBar.insets.top;
}

- (CGFloat)edgeDragHeight {
    NSNumber *size = [self.tabBar.delegate tabView:self.tabBar valueOfOption:PSMTabBarControlOptionDragEdgeHeight];
    return size.doubleValue;
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
        if (tabOrientation != PSMTabBarHorizontalOrientation) {
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
    if (cell.controlView.window.backingScaleFactor > 1) {
        result.origin.y += 0.5;
    }

    return result;
}

- (CGFloat)retinaRoundUpCell:(PSMTabBarCell *)cell value:(CGFloat)value {
    NSWindow *window = cell.controlView.window;
    if (!window) {
        return ceil(value);
    }
    CGFloat scale = window.backingScaleFactor;
    if (!scale) {
        scale = [[NSScreen mainScreen] backingScaleFactor];
    }
    if (!scale) {
        scale = 1;
    }
    return ceil(scale * value) / scale;
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

    float countWidth = [self retinaRoundUpCell:cell value:[[self attributedObjectCountValueForTabCell:cell] size].width];
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
    const NSInteger count = cell.count;
    NSString *contents = [@(count) stringValue];
    NSString *const modifierString = [cell modifierString];
    if (modifierString.length > 0 && count < 9) {
        contents = [modifierString stringByAppendingString:contents];
    } else if (modifierString.length > 0 && [cell isLast]) {
        contents = [modifierString stringByAppendingString:@"9"];
    } else {
        contents = @"";
    }
    NSDictionary *attributes =
        @{ NSFontAttributeName: [NSFont systemFontOfSize:self.fontSize],
           NSForegroundColorAttributeName: [self textColorForCell:cell] };
    return [[[NSAttributedString alloc] initWithString:contents attributes:attributes] autorelease];
}

- (NSColor *)textColorDefaultSelected:(BOOL)selected backgroundColor:(NSColor *)backgroundColor windowIsMainAndAppIsActive:(BOOL)mainAndActive {
    CGFloat value;
    if (mainAndActive) {
        value = 0;
    } else {
        if (selected) {
            value = 189;
        } else {
            value = 164;
        }
    }
    return [NSColor colorWithSRGBRed:value/255.0 green:value/255.0 blue:value/255.0 alpha:1];
}

- (NSColor *)textColorForCell:(PSMTabBarCell *)cell {
    DLog(@"cell=%@", cell);
    const BOOL selected = (cell.state == NSControlStateValueOn);
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
            if (cellBrightness > 0.5) {
                // Light tab
                return [NSColor colorWithWhite:0 alpha:prominence];
            } else {
                // Dark tab
                return [NSColor colorWithWhite:1 alpha:prominence];
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

- (PSMCachedTitleInputs *)cachedTitleInputsForTabCell:(PSMTabBarCell *)cell {
    const BOOL parseHTML = [[_tabBar.delegate tabView:_tabBar valueOfOption:PSMTabBarControlOptionHTMLTabTitles] boolValue];
    PSMCachedTitleInputs *inputs = [[[PSMCachedTitleInputs alloc] initWithTitle:cell.stringValue
                                                                truncationStyle:cell.truncationStyle
                                                                          color:[self textColorForCell:cell]
                                                                        graphic:[(id)[[cell representedObject] identifier] psmTabGraphic]
                                                                    orientation:_orientation
                                                                       fontSize:self.fontSize
                                                                      parseHTML:parseHTML] autorelease];
    return inputs;
}

- (PSMCachedTitleInputs *)cachedSubtitleInputsForTabCell:(PSMTabBarCell *)cell {
    if (!cell.subtitleString) {
        return nil;
    }
    const BOOL parseHTML = [[_tabBar.delegate tabView:_tabBar valueOfOption:PSMTabBarControlOptionHTMLTabTitles] boolValue];
    NSColor *color = [self textColorForCell:cell];
    PSMCachedTitleInputs *inputs = [[[PSMCachedTitleInputs alloc] initWithTitle:cell.subtitleString ?: @""
                                                                truncationStyle:cell.truncationStyle
                                                                          color:[color colorWithAlphaComponent:color.alphaComponent * 0.7]
                                                                        graphic:nil
                                                                    orientation:_orientation
                                                                       fontSize:self.subtitleFontSize
                                                                      parseHTML:parseHTML] autorelease];
    return inputs;
}

- (CGFloat)fontSize {
    NSNumber *override = [_tabBar.delegate tabView:_tabBar valueOfOption:PSMTabBarControlOptionFontSizeOverride];
    if (override) {
        return override.doubleValue;
    }
    return 11.0;
}

- (CGFloat)subtitleFontSize {
    return round(self.fontSize * 0.8);
}

#pragma mark - Drawing

- (NSColor *)topLineColorSelected:(BOOL)selected {
    const BOOL keyMainAndActive = self.windowIsMainAndAppIsActive;
    if (@available(macOS 10.16, *)) {
        return [NSColor clearColor];
    }
    if (keyMainAndActive) {
        return [NSColor colorWithSRGBRed:180.0/255.0 green:180.0/255.0 blue:180.0/255.0 alpha:1];
    } else {
        return [NSColor colorWithSRGBRed:209.0/255.0 green:209.0/255.0 blue:209.0/255.0 alpha:1];
    }
}

- (NSColor *)verticalLineColorSelected:(BOOL)selected {
    const BOOL keyMainAndActive = self.windowIsMainAndAppIsActive;
    if (@available(macOS 10.16, *)) {
        return [NSColor colorWithWhite:0 alpha:0.07];
    }
    if (keyMainAndActive) {
        return [NSColor colorWithSRGBRed:174.0/255.0 green:174.0/255.0 blue:174.0/255.0 alpha:1];
    } else {
        return [NSColor colorWithSRGBRed:209.0/255.0 green:209.0/255.0 blue:209.0/255.0 alpha:1];
    }
}

- (NSColor *)bottomLineColorSelected:(BOOL)selected {
    if (@available(macOS 12.0, *)) {
        return [NSColor colorWithSRGBRed:230.0/255.0 green:230.0/255.0 blue:230.0/255.0 alpha:1];
    } else if (@available(macOS 10.16, *)) {
        return [NSColor colorWithSRGBRed:180.0/255.0 green:180.0/255.0 blue:180.0/255.0 alpha:1];
    } else {
        return [NSColor colorWithWhite:0 alpha:0.15];
    }
}

- (NSColor *)bigSurBackgroundColorSelected:(BOOL)selected highlightAmount:(CGFloat)highlightAmount NS_AVAILABLE_MAC(10_16) {
    if (selected) {
        // Reveal the visual effect view with material NSVisualEffectMaterialTitlebar beneath the tab bar.
        // Per NSColor.h, windowFrameColor is described as:
        // Historically used as the color of the window chrome, which is no longer able to be represented by a color. No longer used.
        return [NSColor clearColor];
    }
    // `base` gives how much darker the unselected tab is as an alpha value.
    CGFloat base = [[_tabBar.delegate tabView:_tabBar valueOfOption:PSMTabBarControlOptionLightModeInactiveTabDarkness] doubleValue];
    return [NSColor colorWithWhite:0 alpha:base + (1 - base) * (highlightAmount * 0.05)];
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
    if (@available(macOS 10.16, *)) {
        return [self bigSurBackgroundColorSelected:selected highlightAmount:highlightAmount];
    } else  {
        return [self mojaveBackgroundColorSelected:selected highlightAmount:highlightAmount];
    }
}

- (void)drawHorizontalLineInFrame:(NSRect)rect y:(CGFloat)y {
    NSRectFillUsingOperation(NSMakeRect(NSMinX(rect), y, rect.size.width + 1, 1),
                             NSCompositingOperationSourceOver);
}

- (void)drawVerticalLineInFrame:(NSRect)rect x:(CGFloat)x {
    CGFloat topInset = 1;
    CGFloat bottomInset = 0;
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

- (void)drawShadowForUnselectedTabInRect:(NSRect)backgroundRect {
    const CGFloat shadowHeight = 4;
    NSRect shadowRect = backgroundRect;
    shadowRect.size.height = shadowHeight;
    static NSImage *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        image = [[[NSBundle bundleForClass:[self class]] imageForResource:@"UnselectedTabShadow"] retain];
    });
    [image drawInRect:shadowRect];
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
    if (!horizontal) {
        // The bar background color is extended by a half point to get a two-tone effect with the
        // right-side line but here we want to remove it completely.
        backgroundRect.size.width += 0.5;
    }
    NSRectFill(backgroundRect);

    if (tabColor) {
        NSColor *color = [self cellBackgroundColorForTabColor:tabColor selected:selected];
        // Alpha the inactive tab's colors a bit to make it clear which tab is active.
        [color set];
        NSRectFillUsingOperation(cellFrame, NSCompositingOperationSourceOver);
    }

    if (@available(macOS 10.16, *)) {
        if (!selected && _orientation == PSMTabBarHorizontalOrientation) {
            [self drawShadowForUnselectedTabInRect:backgroundRect];
        }
    }
}

- (NSEdgeInsets)backgroundInsetsWithHorizontalOrientation:(BOOL)horizontal {
    NSEdgeInsets insets = NSEdgeInsetsZero;
    if (@available(macOS 10.16, *)) {
        return insets;
    } else {
        insets.top = 1;
        insets.bottom = 1;
        insets.left = 1;
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
        if (isFirst && NSMinX(cellFrame) > 1) {
            shouldDrawLeftLine = YES;
        } else {
            // Because alpha is less than 1, we don't want to double-draw. I don't think
            // drawing the left line is necessary in earlier macOS versions either but I
            // don't feel like adding any risk at the moment.
            shouldDrawLeftLine = NO;
        }
        if (shouldDrawLeftLine) {
            // Left line
            [[self verticalLineColorSelected:selected] set];
            [self drawVerticalLineInFrame:cellFrame x:NSMinX(cellFrame)];
        }
        // Right line
        [[self verticalLineColorSelected:selected] set];
        CGFloat rightAdjustment = 0;
        if (@available(macOS 10.16, *)) {
            rightAdjustment = isLast ? 0 : 1;
        }
        [self drawVerticalLineInFrame:cellFrame x:NSMaxX(cellFrame) - rightAdjustment];

        // Top line
        [[self topLineColorSelected:selected] set];
        // Bottom line
        if (@available(macOS 10.16, *)) { } else {
            const BOOL drawBottomLine = [[_tabBar.delegate tabView:_tabBar valueOfOption:PSMTabBarControlOptionColoredDrawBottomLineForHorizontalTabBar] boolValue];
            if (drawBottomLine) {
                [[self bottomLineColorSelected:selected] set];
                [self drawHorizontalLineInFrame:cellFrame y:NSMaxY(cellFrame) - 1];
            }
        }
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
    }
}

- (NSEdgeInsets)insetsForTabBarDividers {
    return NSEdgeInsetsMake(0, 0.5, 0, 2);
}

- (void)drawTabCell:(PSMTabBarCell *)cell highlightAmount:(CGFloat)highlightAmount {
    // TODO: Test hidden control, whose height is less than 2. Maybe it happens while dragging?
    [self drawCellBackgroundAndFrameHorizontallyOriented:(_orientation == PSMTabBarHorizontalOrientation)
                                                  inRect:cell.frame
                                                selected:([cell state] == NSControlStateValueOn)
                                            withTabColor:[cell tabColor]
                                                 isFirst:cell == _tabBar.cells.firstObject
                                                  isLast:cell == _tabBar.cells.lastObject
                                         highlightAmount:highlightAmount];
    [self drawInteriorWithTabCell:cell inView:[cell controlView] highlightAmount:highlightAmount];
}

- (CGFloat)tabColorBrightness:(PSMTabBarCell *)cell {
    NSColor *color = [self effectiveBackgroundColorForTabWithTabColor:cell.tabColor
                                                             selected:(cell.state == NSControlStateValueOn)
                                                      highlightAmount:0
                                                               window:cell.controlView.window];
    if (@available(macOS 10.16, *)) {
        // This gets blended over a NSVisualEffectView, whose color is a mystery. Assume it's
        // related to light/dark mode.
        NSAppearanceName bestMatch = [_tabBar.effectiveAppearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameDarkAqua,
                                                                                                       NSAppearanceNameVibrantDark,
                                                                                                       NSAppearanceNameAqua,
                                                                                                       NSAppearanceNameVibrantLight ]];
        const CGFloat frontAlpha = color.alphaComponent;
        CGFloat backBrightness;
        const CGFloat frontBrightness = [color it_hspBrightness];
        if ([bestMatch isEqualToString:NSAppearanceNameDarkAqua] ||
            [bestMatch isEqualToString:NSAppearanceNameVibrantDark]) {
            backBrightness = 0;
        } else {
            backBrightness = 1;
        }
        return backBrightness * (1 - frontAlpha) + frontAlpha * frontBrightness;
    } else {
        return [color it_hspBrightness];
    }
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
    NSColor *closeButtonTintColor;
    const void *colorKey;
    if ([self tabColorBrightness:cell] < 0.5) {
        colorKey = "light";
        closeButtonTintColor = [NSColor whiteColor];
    } else {
        colorKey = "dark";
        closeButtonTintColor = [NSColor blackColor];
    }
    closeButton = [closeButton it_cachingImageWithTintColor:closeButtonTintColor
                                                        key:colorKey];

    CGFloat reservedSpace = 0;
    closeButtonSize = [closeButton size];
    PSMCachedTitle *cachedTitle = cell.cachedTitle;

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
    CGFloat closeButtonAlpha = 0;
    if ([cell hasCloseButton] && [cell closeButtonVisible]) {
        if (cell.isCloseButtonSuppressed) {
            closeButtonAlpha = highlightAmount;
        } else {
            closeButtonAlpha = 1;
        }
        const BOOL keyMainAndActive = self.windowIsMainAndAppIsActive;
        if (!keyMainAndActive) {
            closeButtonAlpha /= 2;
        }
        [closeButton drawAtPoint:closeButtonRect.origin
                        fromRect:NSZeroRect
                       operation:NSCompositingOperationSourceOver
                        fraction:closeButtonAlpha];

    }
    // Draw graphic icon (i.e., the app icon, not new-output indicator icon) over close button.
    if (cachedTitle.inputs.graphic) {
        const CGFloat width = [self drawGraphicWithCellFrame:cellFrame
                                                       image:cachedTitle.inputs.graphic
                                                       alpha:1 - closeButtonAlpha];
        if (_orientation == PSMTabBarHorizontalOrientation) {
            reservedSpace = MAX(reservedSpace, width);
        } else {
            labelPosition = MAX(labelPosition, width + kPSMTabBarCellPadding);
        }
    }

    // icon
    BOOL drewIcon = NO;
    NSRect iconRect = NSZeroRect;
    if ([cell hasIcon]) {
        // There is an icon. Draw it as long as the amount of space left for the label is more than
        // the size of the icon. This is a heuristic to roughly prioritize the label over the icon.
        const CGFloat labelWidth = [self widthForLabelInCell:cell
                                               labelPosition:labelPosition
                                                     hasIcon:YES
                                                    iconRect:iconRect
                                                 cachedTitle:cachedTitle
                                               reservedSpace:reservedSpace
                                                boundingSize:NULL
                                                    truncate:NULL];
        NSImage *icon = [(id)[[cell representedObject] identifier] icon];
        const CGFloat minimumLabelWidth =
        [[self.tabBar.delegate tabView:self.tabBar
                         valueOfOption:PSMTabBarControlOptionMinimumSpaceForLabel] doubleValue];
        if (labelWidth > minimumLabelWidth) {
            drewIcon = YES;
            iconRect = [self iconRectForTabCell:cell];

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
    CGFloat mainLabelHeight = 0;
    PSMCachedTitle *cachedSubtitle = cell.cachedSubtitle;
    const CGFloat labelOffset = [self willDrawSubtitle:cachedSubtitle] ? [self verticalOffsetForTitleWhenSubtitlePresent] : 0;
    if (!cachedTitle.isEmpty) {
        NSRect labelRect;
        labelRect.origin.x = labelPosition;
        NSSize boundingSize;
        BOOL truncate;
        labelRect.size.width = [self widthForLabelInCell:cell
                                           labelPosition:labelPosition
                                                 hasIcon:drewIcon
                                                iconRect:iconRect
                                             cachedTitle:cachedTitle
                                           reservedSpace:reservedSpace
                                            boundingSize:&boundingSize
                                                truncate:&truncate];
        labelRect.origin.y = cellFrame.origin.y + floor((cellFrame.size.height - boundingSize.height) / 2.0) + labelOffset;
        labelRect.size.height = boundingSize.height;

        NSAttributedString *attributedString = [cachedTitle attributedStringForcingLeftAlignment:truncate
                                                                               truncatedForWidth:labelRect.size.width];
        if (truncate) {
            labelRect.origin.x += reservedSpace;
        }

        [attributedString drawInRect:labelRect];
        mainLabelHeight = NSHeight(labelRect);
    }

    if ([self supportsMultiLineLabels]) {
        [self drawSubtitle:cachedSubtitle
                         x:labelPosition
                      cell:cell
                   hasIcon:drewIcon
                  iconRect:iconRect
             reservedSpace:reservedSpace
                 cellFrame:cellFrame
               labelOffset:labelOffset
           mainLabelHeight:mainLabelHeight];
    }
}

- (CGFloat)verticalOffsetForTitleWhenSubtitlePresent {
    return -5;
}

- (CGFloat)verticalOffsetForSubtitle {
    return -2;
}

- (BOOL)supportsMultiLineLabels {
    return NSHeight(self.tabBar.bounds) >= 28;
}

- (BOOL)willDrawSubtitle:(PSMCachedTitle *)subtitle {
    return [self supportsMultiLineLabels] && subtitle && !subtitle.isEmpty;
}

- (void)drawSubtitle:(PSMCachedTitle *)cachedSubtitle
                   x:(CGFloat)labelPosition
                cell:(PSMTabBarCell *)cell
             hasIcon:(BOOL)drewIcon
            iconRect:(NSRect)iconRect
       reservedSpace:(CGFloat)reservedSpace
           cellFrame:(NSRect)cellFrame
         labelOffset:(CGFloat)labelOffset
     mainLabelHeight:(CGFloat)mainLabelHeight {
    if (cachedSubtitle.isEmpty) {
        return;
    }
    NSRect labelRect;
    labelRect.origin.x = labelPosition;
    NSSize boundingSize;
    BOOL truncate;
    labelRect.size.width = [self widthForLabelInCell:cell
                                       labelPosition:labelPosition
                                             hasIcon:drewIcon
                                            iconRect:iconRect
                                         cachedTitle:cachedSubtitle
                                       reservedSpace:reservedSpace
                                        boundingSize:&boundingSize
                                            truncate:&truncate];
    labelRect.origin.y = cellFrame.origin.y + floor((cellFrame.size.height - boundingSize.height) / 2.0) + labelOffset + mainLabelHeight + [self verticalOffsetForSubtitle];
    labelRect.size.height = boundingSize.height;

    NSAttributedString *attributedString = [cachedSubtitle attributedStringForcingLeftAlignment:truncate
                                                                              truncatedForWidth:labelRect.size.width];
    if (truncate) {
        labelRect.origin.x += reservedSpace;
    }

    [attributedString drawInRect:labelRect];
}

- (CGFloat)drawGraphicWithCellFrame:(NSRect)cellFrame
                              image:(NSImage *)image
                              alpha:(CGFloat)alpha {
    NSRect rect = NSMakeRect(NSMinX(cellFrame) + 6,
                             NSMinY(cellFrame) + (NSHeight(cellFrame) - image.size.height) / 2.0,
                             image.size.width,
                             image.size.height);
    [image drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:alpha respectFlipped:YES hints:nil];
    return NSWidth(rect) + kPSMTabBarCellPadding + 2;
}

- (CGFloat)widthForLabelInCell:(PSMTabBarCell *)cell
                 labelPosition:(CGFloat)labelPosition
                       hasIcon:(BOOL)drewIcon
                      iconRect:(NSRect)iconRect
                   cachedTitle:(PSMCachedTitle *)cachedTitle
                 reservedSpace:(CGFloat)reservedSpace
                  boundingSize:(NSSize *)boundingSizeOut
                      truncate:(BOOL *)truncateOut {
    const NSRect cellFrame = cell.frame;
    NSRect labelRect = NSMakeRect(labelPosition,
                                  0,
                                  cellFrame.size.width - (labelPosition - cellFrame.origin.x) - kPSMTabBarCellPadding,
                                  cellFrame.size.height);
    if (drewIcon) {
        // Reduce size of label if there is an icon or activity indicator
        labelRect.size.width -= iconRect.size.width + kPSMTabBarCellIconPadding;
    } else if (![[cell indicator] isHidden]) {
        labelRect.size.width -= cell.indicator.frame.size.width + kPSMTabBarCellIconPadding;
    }

    if ([cell count] > 0) {
        labelRect.size.width -= ([self objectCounterRectForTabCell:cell].size.width + kPSMTabBarCellPadding);
    }

    NSSize boundingSize = [cachedTitle boundingRectWithSize:labelRect.size].size;

    BOOL truncate = NO;
    if (_orientation == PSMTabBarHorizontalOrientation) {
        CGFloat effectiveLeftMargin = (labelRect.size.width - boundingSize.width) / 2;
        if (effectiveLeftMargin < reservedSpace) {
            labelRect.size.width -= reservedSpace;
            truncate = YES;
        }
    }
    if (truncateOut) {
        *truncateOut = truncate;
    }

    if (boundingSizeOut) {
        *boundingSizeOut = boundingSize;
    }
    return labelRect.size.width;
}

- (NSColor *)tabBarColor {
    const BOOL keyMainAndActive = self.windowIsMainAndAppIsActive;
    if (@available(macOS 10.16, *)) {
        return [NSColor colorWithSRGBRed:225.0 / 255.0
                                   green:225.0 / 255.0
                                    blue:225.0 / 255.0
                                   alpha:1];
    } else {
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
    NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);

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
        // Draw a divider between the tabbar and the content.
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
        horizontal:(BOOL)horizontal
      withOverflow:(BOOL)withOverflow {
    if (_orientation != [bar orientation]) {
        _orientation = [bar orientation];
    }

    if (_tabBar != bar) {
        _tabBar = bar;
    }

    // Background to the right of the rightmost tab and left of the leftmost tab.
    NSColor *marginColor = [self backgroundColorSelected:NO highlightAmount:0];
    [self drawBackgroundInRect:clipRect color:marginColor horizontal:horizontal];

    // Draw line above tab bar.
    NSColor *topLineColor = [self topLineColorSelected:NO];
    [topLineColor set];
    NSRect insetRect;
    if (@available(macOS 10.16, *)) {
        insetRect = clipRect;
    } else {
        insetRect = NSInsetRect(rect, 1, 0);
        insetRect.size.width -= 1;
    }
    if (@available(macOS 10.16, *)) { } else {
        const NSRect insetClipIntersection = NSIntersectionRect(clipRect, insetRect);
        [self drawHorizontalLineInFrame:insetClipIntersection y:0];
    }

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

    const BOOL attachedToTitleBar = [[bar.delegate tabView:bar valueOfOption:PSMTabBarControlOptionAttachedToTitleBar] boolValue];
    // draw cells
    for (int i = 0; i < 2; i++) {
        NSInteger stateToDraw = (i == 0 ? NSControlStateValueOn : NSControlStateValueOff);
        for (PSMTabBarCell *cell in [bar cells]) {
            if (![cell isInOverflowMenu] && NSIntersectsRect(NSInsetRect([cell frame], -1, -1), clipRect)) {
                if (cell.state == stateToDraw) {
                    [cell drawWithFrame:[cell frame] inView:bar];
                    if (@available(macOS 10.16, *)) {
                        if ([self shouldDrawTopLineSelected:(stateToDraw == NSControlStateValueOn) attached:attachedToTitleBar position:bar.tabLocation]) {
                            [topLineColor set];
                            NSRectFill(NSMakeRect(NSMinX(cell.frame), 0, NSWidth(cell.frame), 1));
                        }
                    }
                    if (stateToDraw == NSControlStateValueOn) {
                        // Can quit early since only one can be selected
                        break;
                    }
                }
            }
        }
    }

    if (@available(macOS 10.16, *)) {
        if (bar.showAddTabButton && attachedToTitleBar) {
            NSRect frame = bar.addTabButton.frame;
            frame.size.width = NSWidth(bar.bounds) - NSMinX(frame);
            [topLineColor set];
            frame.size.width = INFINITY;
            frame = NSIntersectionRect(frame, NSIntersectionRect(clipRect, insetRect));
            NSRectFill(NSMakeRect(NSMinX(frame), 0, NSWidth(frame), 1));
        }
    }

    [self drawDividerBetweenTabBarAndContent:rect bar:bar];

    for (PSMTabBarCell *cell in [bar cells]) {
        if (![cell isInOverflowMenu] && NSIntersectsRect([cell frame], clipRect) && cell.state == NSControlStateValueOn) {
            [cell drawPostHocDecorationsOnSelectedCell:cell tabBarControl:bar];
        }
    }
}

- (void)drawDividerBetweenTabBarAndContent:(NSRect)rect bar:(PSMTabBarControl *)bar {
    if (_orientation != PSMTabBarHorizontalOrientation) {
        [[self bottomLineColorSelected:NO] set];
        NSRect rightLineRect = rect;
        rightLineRect.origin.y -= 1;
        [self drawVerticalLineInFrame:rightLineRect x:NSMaxX(rect) - 1];
    } else {
        if (@available(macOS 10.16, *)) {
            switch (bar.tabLocation) {
                case PSMTab_LeftTab:
                    break;
                case PSMTab_TopTab:
                    // Bottom line
                    [[self bottomLineColorSelected:YES] set];
                    NSRectFill(NSMakeRect(0, NSMaxY(rect) - 1, NSWidth(rect), 1));
                    break;
                case PSMTab_BottomTab:
                    // Top line
                    [[self bottomLineColorSelected:YES] set];
                    NSRectFill(NSMakeRect(0, NSMinY(rect), NSWidth(rect), 1));
                    break;
            }
        }
    }
}

- (BOOL)shouldDrawTopLineSelected:(BOOL)selected
                         attached:(BOOL)attached
                         position:(PSMTabPosition)position NS_AVAILABLE_MAC(10_16) {
    switch (position) {
        case PSMTab_BottomTab:
        case PSMTab_LeftTab:
            return YES;

        case PSMTab_TopTab:
            if (!attached) {
                return NO;
            }
            if (!selected) {
                return YES;
            }
            // Leave out the line on the selected tab when it's attached to the tabbar so it looks like
            // it's the same surface.
            return NO;
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
