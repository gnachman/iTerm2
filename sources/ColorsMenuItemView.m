/*
 **  ColorsMenuItemView.m
 **
 **  Copyright (c) 2012
 **
 **  Author: Andrea Bonomi
 **
 **  Project: iTerm
 **
 **  Description: Colored Tabs.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import "ColorsMenuItemView.h"

#import "NSAppearance+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSObject+iTerm.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"

@implementation iTermTabColorMenuItem

- (ColorsMenuItemView *)colorsView {
    return [ColorsMenuItemView castFrom:self.view];
}

@end

@interface ColorsMenuItemView()
@property(nonatomic, retain) NSColor *color;
@end

@implementation ColorsMenuItemView {
    NSTrackingArea *_trackingArea;
    NSInteger _selectedIndex;
    BOOL _mouseDown;
    NSInteger _mouseDownIndex;
}

// Layout constants
static const int kColumnsPerRow = 8;          // reset + 7 colors = 8 cells per row
static const int kRowDistanceY = 18;          // vertical spacing between rows
static const int kOffsetX_PreBigSur = 20;
static const int kOffsetX_BigSur = 24;
static const int kOffsetX_BigSur_NoneChecked = 10;
static const int kOffsetX_Sonoma = 24;
static const int kOffsetX_Sonoma_NoneChecked = 14;
static const int kOffsetY = 10;
static const int kColorAreaDistanceX = 18;
static const int kColorAreaDimension = 12;
static const int kColorAreaBorder = 1;
static const int kDefaultColorStokeWidth = 2;
static const int kMenuFontSize = 14;
static const int kSeparatorGap = 8;           // gap containing the | separator

const int kMenuLabelOffsetY = 20;

const CGFloat iTermColorsMenuItemViewDisabledAlpha = 0.3;

- (void)viewDidMoveToWindow {
    _selectedIndex = NSNotFound;
    [super viewDidMoveToWindow];
    [self updateTrackingAreas];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) {
        [self removeTrackingArea:_trackingArea];
    }


    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:(NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited |
                                                          NSTrackingActiveAlways) owner:self userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

#pragma mark - Cell indices

// Cell index layout:
//   0           = reset (X)
//   1..N        = preset colors
//   N+1         = picker (eyedropper icon)
//   N+2         = current custom color (only when hasCustomColor)
- (BOOL)hasCustomColor {
    if (!self.currentColor) return NO;
    const NSInteger count = [self displayedColorCount];
    for (NSInteger i = 1; i <= count; i++) {
        if ([self.currentColor isApproximatelyEqualToColor:[self colorAtIndex:i enabled:YES] epsilon:1/65535.0]) {
            return NO;
        }
    }
    return YES;
}

- (NSInteger)pickerCellIndex {
    return 1 + [self displayedColorCount];
}

- (NSInteger)customColorCellIndex {
    return [self pickerCellIndex] + 1;
}

- (NSInteger)indexForPoint:(NSPoint)p {
    // Check preset cells (index 0 = reset, followed by colors)
    const NSInteger presetCount = 1 + [self displayedColorCount];
    for (NSInteger i = 0; i < presetCount; i++) {
        if (NSPointInRect(p, [self rectForCellIndex:i enlarged:YES])) {
            return i;
        }
    }
    // Check the picker cell
    if (NSPointInRect(p, [self rectForCellIndex:[self pickerCellIndex] enlarged:YES])) {
        return [self pickerCellIndex];
    }
    // Check the custom color cell
    if ([self hasCustomColor]) {
        if (NSPointInRect(p, [self rectForCellIndex:[self customColorCellIndex] enlarged:YES])) {
            return [self customColorCellIndex];
        }
    }
    return NSNotFound;
}

- (BOOL)enabled {
    NSMenuItem *enclosingMenuItem = [self enclosingMenuItem];
    return enclosingMenuItem.isEnabled;
}

- (void)mouseDown:(NSEvent *)event {
    if (!self.enabled) {
        return;
    }
    _mouseDown = YES;
    _mouseDownIndex = [self indexForPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    [self setNeedsDisplay:YES];
    [super mouseDown:event];
}

- (void)mouseMoved:(NSEvent *)event {
    [self updateSelectedIndexForEvent:event];
}

- (void)mouseEntered:(NSEvent *)event {
    _selectedIndex = NSNotFound;
    [self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent *)event {
    _selectedIndex = NSNotFound;
    [self setNeedsDisplay:YES];
}

- (void)updateSelectedIndexForEvent:(NSEvent *)event {
    const NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    const NSInteger currentIndex = [self indexForPoint:point];
    if (currentIndex != _selectedIndex) {
        _selectedIndex = currentIndex;
        [self setNeedsDisplay:YES];
    }
}

- (CGFloat)colorXOffset {
    if (@available(macOS 14, *)) {
        if ([self anySiblingIsChecked]) {
            return kOffsetX_Sonoma;
        } else {
            return kOffsetX_Sonoma_NoneChecked;
        }
    }
    if (@available(macOS 10.16, *)) {
        if ([self anySiblingIsChecked]) {
            return kOffsetX_BigSur;
        }
        return kOffsetX_BigSur_NoneChecked;
    }
    return kOffsetX_PreBigSur;
}

#pragma mark - Cell positioning

- (NSRect)rectForCellIndex:(NSInteger)cellIndex enlarged:(BOOL)enlarged {
    if (cellIndex == NSNotFound) {
        return NSZeroRect;
    }
    CGFloat growth = enlarged ? 2 : 0;
    const NSInteger presetCellCount = 1 + [self displayedColorCount];
    const NSInteger presetRowCount = (presetCellCount + (kColumnsPerRow - 1)) / kColumnsPerRow;

    // Right group: [separator] [picker] [custom?]
    // Positioned right after the last preset cell.
    NSInteger lastPresetIndex = presetCellCount - 1;
    NSInteger lastColumn = lastPresetIndex % kColumnsPerRow;
    const CGFloat rightGroupBaseX = self.colorXOffset + kColorAreaDistanceX * (lastColumn + 1) + kSeparatorGap;
    const CGFloat rightGroupY = kOffsetY;

    // Picker cell (eyedropper icon, right after separator)
    if (cellIndex == [self pickerCellIndex]) {
        return NSMakeRect(rightGroupBaseX - growth,
                          rightGroupY - growth,
                          kColorAreaDimension + growth * 2,
                          kColorAreaDimension + growth * 2);
    }

    // Custom color cell (right after picker)
    if ([self hasCustomColor] && cellIndex == [self customColorCellIndex]) {
        CGFloat customX = rightGroupBaseX + kColorAreaDistanceX;
        return NSMakeRect(customX - growth,
                          rightGroupY - growth,
                          kColorAreaDimension + growth * 2,
                          kColorAreaDimension + growth * 2);
    }

    // Preset cells (including reset at index 0)
    NSInteger column = cellIndex % kColumnsPerRow;
    NSInteger row = presetRowCount - (cellIndex / kColumnsPerRow) - 1;
    const CGFloat x = self.colorXOffset + kColorAreaDistanceX * column - growth;
    const CGFloat y = kOffsetY + (kRowDistanceY * row) - growth;
    return NSMakeRect(x, y,
                      kColorAreaDimension + growth * 2,
                      kColorAreaDimension + growth * 2);
}

// Number of colors we will display (max 31)
- (NSInteger)displayedColorCount {
    return MIN((NSInteger)self.colors.count, 31);
}

// Total cells including the reset cell (presets only)
- (NSInteger)totalCellCount {
    return 1 + [self displayedColorCount];
}

- (NSColor *)outlineColorForColor:(NSColor *)color enabled:(BOOL)enabled {
    if (self.effectiveAppearance.it_isDark) {
        const CGFloat perceivedBrightness = color.perceivedBrightness;
        const CGFloat outlineBrightness = color.brightnessComponent + 0.1 + (0.05 * pow(20, perceivedBrightness));
        return [NSColor colorWithHue:color.hueComponent
                          saturation:color.saturationComponent * 0.8
                          brightness:outlineBrightness
                               alpha:enabled ? 1 : iTermColorsMenuItemViewDisabledAlpha];
    }
    const CGFloat brightness = color.brightnessComponent;
    const CGFloat perceivedBrightness = color.perceivedBrightness;
    const CGFloat outlineBrightness = brightness * (1 - 0.025 * pow(40, perceivedBrightness));
    return [NSColor colorWithHue:color.hueComponent
                      saturation:MAX(1, color.saturationComponent * 1.1)
                      brightness:outlineBrightness
                           alpha:enabled ? 1 : iTermColorsMenuItemViewDisabledAlpha];
}

- (NSColor *)outlineColorAtIndex:(NSInteger)i enabled:(BOOL)enabled {
    return [self outlineColorForColor:[self colorAtIndex:i enabled:enabled] enabled:enabled];
}

#pragma mark - Drawing

// Draw the menu item (label and colors)
- (void)drawRect:(NSRect)rect {
    const BOOL enabled = self.enabled;

    // draw the "x" (reset color to default)
    CGFloat savedWidth = [NSBezierPath defaultLineWidth];

    NSColor *color;
    if (0 == _selectedIndex) {
        color = self.effectiveAppearance.it_isDark ? [NSColor whiteColor] : [NSColor blackColor];
    } else {
        color = self.effectiveAppearance.it_isDark ? [NSColor lightGrayColor] : [NSColor colorWithWhite:0.35 alpha:1];
    }
    if (!enabled) {
        color = [color colorWithAlphaComponent:iTermColorsMenuItemViewDisabledAlpha];
    }
    [color set];
    [NSBezierPath setDefaultLineWidth:1];
    const NSRect noColorRect = NSInsetRect([self rectForCellIndex:0 enlarged:(enabled && _selectedIndex == 0)],
                                           0.5,
                                           0.5);
    [NSBezierPath strokeRect:noColorRect];
    [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMaxX(noColorRect), NSMinY(noColorRect))
                              toPoint:NSMakePoint(NSMinX(noColorRect), NSMaxY(noColorRect))];

    [NSBezierPath setDefaultLineWidth:kDefaultColorStokeWidth];
    // draw the preset colors (indices 1..displayedColorCount)
    const NSInteger colorCount = [self displayedColorCount];
    for (NSInteger i = 1; i <= colorCount; i++) {
        [self drawPresetColorCell:i enabled:enabled];
    }

    // Draw the separator line between presets and the right group
    [self drawSeparator:enabled];

    // Draw the color picker cell (eyedropper icon)
    [self drawPickerCell:enabled];

    // Draw the current custom color cell (if present)
    [self drawCustomColorCell:enabled];

    // draw the menu label
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    if (@available(macOS 26, *)) {
        attributes[NSForegroundColorAttributeName] = [NSColor controlTextColor];
    } else {
        attributes[NSForegroundColorAttributeName] = [NSColor textColor];
    }
    attributes[NSFontAttributeName] = [NSFont menuFontOfSize:kMenuFontSize];

    NSMenu *rootMenu = self.enclosingMenuItem.menu;
    while (rootMenu.supermenu) {
        rootMenu = rootMenu.supermenu;
    }
    if (!enabled) {
        const CGFloat alpha = self.effectiveAppearance.it_isDark ? 0.30 : 0.25;
        attributes[NSForegroundColorAttributeName] = [attributes[NSForegroundColorAttributeName] colorWithAlphaComponent:alpha];
    }
    NSString *labelTitle = @"Tab Color:";
    const CGFloat x = [self colorXOffset];
    [labelTitle drawAtPoint:NSMakePoint(x, [ColorsMenuItemView preferredSize].height - kMenuLabelOffsetY) withAttributes:attributes];
    [NSBezierPath setDefaultLineWidth:savedWidth];
}

- (void)drawSeparator:(BOOL)enabled {
    const NSInteger presetCellCount = 1 + [self displayedColorCount];
    NSInteger lastColumn = (presetCellCount - 1) % kColumnsPerRow;
    const CGFloat sepX = self.colorXOffset + kColorAreaDistanceX * (lastColumn + 1) + kSeparatorGap / 2.0;
    const CGFloat sepTop = kOffsetY + kColorAreaDimension;
    const CGFloat sepBottom = kOffsetY;

    NSColor *sepColor;
    if (self.effectiveAppearance.it_isDark) {
        sepColor = [NSColor colorWithWhite:1.0 alpha:enabled ? 0.2 : 0.1];
    } else {
        sepColor = [NSColor colorWithWhite:0.0 alpha:enabled ? 0.15 : 0.08];
    }
    [sepColor set];
    [NSBezierPath setDefaultLineWidth:1];
    [NSBezierPath strokeLineFromPoint:NSMakePoint(sepX, sepBottom)
                              toPoint:NSMakePoint(sepX, sepTop)];
}

- (void)drawPresetColorCell:(NSInteger)i enabled:(BOOL)enabled {
    const BOOL highlighted = enabled && i == _selectedIndex;
    const NSRect outlineArea = [self rectForCellIndex:i enlarged:highlighted];
    // draw the outline
    [[self outlineColorAtIndex:i enabled:enabled] set];
    NSRectFill(outlineArea);

    // draw the color
    const NSRect colorArea = NSInsetRect(outlineArea, kColorAreaBorder, kColorAreaBorder);
    NSColor *color = [self colorAtIndex:i enabled:enabled];
    [color set];
    NSRectFill(colorArea);

    BOOL showCheck;
    if (_mouseDown && _selectedIndex != NSNotFound) {
        showCheck = highlighted;
    } else {
        // Use an approximate check so it can round-trip through tmux.
        showCheck = [self.currentColor isApproximatelyEqualToColor:[self colorAtIndex:i enabled:YES] epsilon:1/65535.0];
        if (_mouseDown) {
            showCheck = NO;
        }
    }
    if (enabled && showCheck) {
        [self drawCheckmarkInRect:outlineArea colorArea:colorArea color:color];
    }
}

- (void)drawPickerCell:(BOOL)enabled {
    const NSInteger pickerIndex = [self pickerCellIndex];
    const BOOL highlighted = enabled && pickerIndex == _selectedIndex;
    const NSRect cellRect = [self rectForCellIndex:pickerIndex enlarged:highlighted];

    static NSImage *cachedEyedropper;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cachedEyedropper = [NSImage imageWithSystemSymbolName:@"eyedropper"
                                     accessibilityDescription:@"Color Picker"];
        if (!cachedEyedropper) {
            cachedEyedropper = [NSImage imageNamed:NSImageNameColorPanel];
        }
        NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:kColorAreaDimension weight:NSFontWeightRegular];
        cachedEyedropper = [cachedEyedropper imageWithSymbolConfiguration:config];
    });

    NSColor *tintColor;
    if (highlighted) {
        tintColor = self.effectiveAppearance.it_isDark ? [NSColor whiteColor] : [NSColor blackColor];
    } else {
        tintColor = self.effectiveAppearance.it_isDark ? [NSColor lightGrayColor] : [NSColor colorWithWhite:0.35 alpha:1];
    }
    if (!enabled) {
        tintColor = [tintColor colorWithAlphaComponent:iTermColorsMenuItemViewDisabledAlpha];
    }

    NSImage *tinted = [cachedEyedropper it_imageWithTintColor:tintColor];
    NSSize imageSize = tinted.size;
    NSRect drawRect = NSMakeRect(NSMidX(cellRect) - imageSize.width / 2,
                                 NSMidY(cellRect) - imageSize.height / 2,
                                 imageSize.width,
                                 imageSize.height);
    [tinted drawInRect:drawRect];
}

- (void)drawCustomColorCell:(BOOL)enabled {
    if (![self hasCustomColor]) return;

    const NSInteger cellIndex = [self customColorCellIndex];
    const BOOL highlighted = enabled && cellIndex == _selectedIndex;
    const NSRect outlineArea = [self rectForCellIndex:cellIndex enlarged:highlighted];

    NSColor *customColor = self.currentColor;

    // Draw outline
    [[self outlineColorForColor:customColor enabled:enabled] set];
    NSRectFill(outlineArea);

    // Draw fill
    const NSRect colorArea = NSInsetRect(outlineArea, kColorAreaBorder, kColorAreaBorder);
    NSColor *fillColor = enabled ? customColor : [customColor colorWithAlphaComponent:iTermColorsMenuItemViewDisabledAlpha];
    [fillColor set];
    NSRectFill(colorArea);

    // Always show checkmark on custom cell since it IS the current color
    BOOL showCheck;
    if (_mouseDown && _selectedIndex != NSNotFound) {
        showCheck = highlighted;
    } else {
        showCheck = !_mouseDown;
    }
    if (enabled && showCheck) {
        [self drawCheckmarkInRect:outlineArea colorArea:colorArea color:fillColor];
    }
}

- (void)drawCheckmarkInRect:(NSRect)outlineArea colorArea:(NSRect)colorArea color:(NSColor *)color {
    static NSImage *lightImage;
    static NSImage *darkImage;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lightImage = [[NSImage imageNamed:NSImageNameMenuOnStateTemplate] it_imageWithTintColor:[NSColor whiteColor]];
        darkImage = [[NSImage imageNamed:NSImageNameMenuOnStateTemplate] it_imageWithTintColor:[NSColor blackColor]];
    });
    CGFloat threshold = self.effectiveAppearance.it_isDark ? 0.0 : 0.7;
    NSImage *image = color.perceivedBrightness < threshold ? lightImage : darkImage;
    const NSSize checkSize = NSInsetRect(colorArea, 1, 1).size;
    NSRect rect = NSMakeRect(NSMidX(outlineArea) - checkSize.width / 2,
                             NSMidY(outlineArea) - checkSize.height / 2,
                             checkSize.width,
                             checkSize.height);
    [image drawInRect:rect];
}

#pragma mark - Helpers

- (BOOL)anySiblingIsChecked {
    return [self.enclosingMenuItem.parentItem.submenu.itemArray anyWithBlock:^BOOL(NSMenuItem *item) {
        return item.state != NSControlStateValueOff;
    }];
}

- (NSColor *)colorAtIndex:(NSUInteger)index enabled:(BOOL)enabled {
    const CGFloat alpha = enabled ? 1 : iTermColorsMenuItemViewDisabledAlpha;
    const NSInteger maxIndex = [self displayedColorCount];
    if (index <= 0 || index > maxIndex) {
        return nil;  // 0 -> reset; anything beyond visible colors is nil
    }
    return [self.colors[index - 1] colorWithAlphaComponent:alpha];
}

- (NSArray<NSColor *> *)colors {
    NSArray<NSColor *> *result = [[[iTermAdvancedSettingsModel tabColorMenuOptions] componentsSeparatedByString:@" "] mapWithBlock:^id(NSString *anObject) {
        return [NSColor colorFromHexString:anObject];
    }];
    if (result.count == 0) {
        // Fallback for if the string is totally broken.
        return @[
            [[NSColor colorWithSRGBRed:251.0/255.0 green:107.0/255.0 blue:98.0/255.0 alpha:1] it_colorInDefaultColorSpace],
            [[NSColor colorWithSRGBRed:246.0/255.0 green:172.0/255.0 blue:71.0/255.0 alpha:1] it_colorInDefaultColorSpace],
            [[NSColor colorWithSRGBRed:240.0/255.0 green:220.0/255.0 blue:79.0/255.0 alpha:1] it_colorInDefaultColorSpace],
            [[NSColor colorWithSRGBRed:181.0/255.0 green:215.0/255.0 blue:73.0/255.0 alpha:1] it_colorInDefaultColorSpace],
            [[NSColor colorWithSRGBRed:95.0/255.0 green:163.0/255.0 blue:248.0/255.0 alpha:1] it_colorInDefaultColorSpace],
            [[NSColor colorWithSRGBRed:193.0/255.0 green:142.0/255.0 blue:217.0/255.0 alpha:1] it_colorInDefaultColorSpace],
            [[NSColor colorWithSRGBRed:120.0/255.0 green:120.0/255.0 blue:120.0/255.0 alpha:1] it_colorInDefaultColorSpace],
        ];
    }
    return result;
}

+ (NSSize)preferredSize {
    ColorsMenuItemView *tmp = [[ColorsMenuItemView alloc] initWithFrame:NSZeroRect];
    const NSInteger presetCellCount = [tmp totalCellCount];
    const NSInteger presetRowCount = (presetCellCount + (kColumnsPerRow - 1)) / kColumnsPerRow;
    const CGFloat baseHeight = 50;
    const CGFloat height = baseHeight + (MAX(1, presetRowCount) - 1) * kRowDistanceY;
    // presets + separator gap + picker + custom cell space
    return NSMakeSize(180 + kSeparatorGap + kColorAreaDistanceX * 2 + kColorAreaDimension, height);
}

#pragma mark - Mouse handling

- (void)mouseUp:(NSEvent*) event {
    if (!self.enabled) {
        return;
    }
    _mouseDown = NO;
    [self setNeedsDisplay:YES];

    NSInteger i = [self indexForPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if (i != _mouseDownIndex || i == NSNotFound) {
        [super mouseUp:event];
        return;
    }

    // Picker cell — open color picker via delegate
    if (i == [self pickerCellIndex]) {
        NSMenuItem *enclosingMenuItem = [self enclosingMenuItem];
        NSMenu *menu = [enclosingMenuItem menu];
        [menu cancelTracking];
        [self.delegate colorsMenuItemViewDidRequestColorPicker:self];
        return;
    }

    // Custom color cell — also open color picker (color is already applied)
    if ([self hasCustomColor] && i == [self customColorCellIndex]) {
        NSMenuItem *enclosingMenuItem = [self enclosingMenuItem];
        NSMenu *menu = [enclosingMenuItem menu];
        [menu cancelTracking];
        [self.delegate colorsMenuItemViewDidRequestColorPicker:self];
        return;
    }

    // Preset color or reset cell
    NSMenuItem *enclosingMenuItem = [self enclosingMenuItem];
    NSMenu *menu = [enclosingMenuItem menu];
    NSInteger menuIndex = [menu indexOfItem:enclosingMenuItem];
    self.color = [self colorAtIndex:i enabled:YES];
    [menu cancelTracking];
    [menu performActionForItemAtIndex:menuIndex];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.enabled) {
        return;
    }
    _mouseDownIndex = [self indexForPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    [self updateSelectedIndexForEvent:event];
}

@end
