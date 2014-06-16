//
//  PSMAquaTabStyle.m
//  PSMTabBarControl
//
//  Created by John Pannell on 2/17/06.
//  Copyright 2006 Positive Spin Media. All rights reserved.
//

#import "PSMAquaTabStyle.h"
#import "PSMTabBarCell.h"
#import "PSMTabBarControl.h"

#define kPSMAquaObjectCounterRadius 7.0
#define kPSMAquaCounterMinWidth 20

@interface NSColor (CGColorAdditions)
/**
 Return CGColor representation of the NSColor in the RGB color space
 It has a silly name because OS 10.8 defines -[NSColor CGColor].
 */
@property (readonly) CGColorRef PSMCGColor;
@end

@implementation NSColor (CGColorAdditions)

- (CGColorRef)PSMCGColor
{
  NSColor *colorRGB = [self colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  CGFloat components[4];
  [colorRGB getRed:&components[0] green:&components[1] blue:&components[2] alpha:&components[3]];
  CGColorSpaceRef theColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
  CGColorRef theColor = CGColorCreate(theColorSpace, components);
  CGColorSpaceRelease(theColorSpace);
  return (CGColorRef)[(id)theColor autorelease];
}

@end

static CGImageRef CGImageCreateWithNSImage(NSImage *image, CGRect sourceRect) {
  NSSize imageSize = [image size];

  CGContextRef bitmapContext = CGBitmapContextCreate(NULL,
                                                     imageSize.width,
                                                     imageSize.height,
                                                     8,
                                                     0,
                                                     [[NSColorSpace genericRGBColorSpace] CGColorSpace],
                                                     kCGBitmapByteOrder32Host | kCGImageAlphaPremultipliedFirst);

  [NSGraphicsContext saveGraphicsState];
  [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithGraphicsPort:bitmapContext
                                                                                  flipped:NO]];
  [image drawInRect:NSMakeRect(0, 0, imageSize.width, imageSize.height)
           fromRect:NSRectFromCGRect(sourceRect)
          operation:NSCompositeCopy
           fraction:1.0];
  [NSGraphicsContext restoreGraphicsState];

  CGImageRef cgImage = CGBitmapContextCreateImage(bitmapContext);
  CGContextRelease(bitmapContext);
  return cgImage;
}

@implementation PSMAquaTabStyle

- (NSString *)name
{
    return @"Aqua";
}

#pragma mark -
#pragma mark Creation/Destruction

- (id) init
{
    if((self = [super init]))
    {
        [self loadImagesWithHorizontalOrientation:YES];
    }
    return self;
}

- (NSImage *)rotatedImage:(NSImage *)image {
    NSRect bounds = NSMakeRect(0, 0, image.size.width, image.size.height);
    NSImageRep *bestRep = [image bestRepresentationForRect:bounds
                                                   context:[NSGraphicsContext currentContext]
                                                     hints:nil];
    NSSize rotatedSize = NSMakeSize(bestRep.pixelsHigh, bestRep.pixelsWide);

    NSImage *rotatedImage = [[[NSImage alloc] initWithSize:rotatedSize] autorelease];

    [rotatedImage lockFocus];

    NSAffineTransform *theTransform = [NSAffineTransform transform];
    NSPoint rotatedCenter = NSMakePoint(rotatedSize.width / 2, rotatedSize.height / 2);

    [theTransform translateXBy:rotatedCenter.x yBy:rotatedCenter.y];
    [theTransform rotateByDegrees:90];
    [theTransform translateXBy:-rotatedCenter.y yBy:-rotatedCenter.x];
    [theTransform concat];

    [bestRep drawInRect:NSMakeRect(0, 0, rotatedSize.height, rotatedSize.width)];

    [rotatedImage unlockFocus];

    return rotatedImage;
}

- (NSImage *)newImageNamed:(NSString *)baseName flipped:(BOOL)flipped {
    NSString *name = [NSString stringWithFormat:@"%@%@", baseName, _imagesHaveHorizontalOrientation ? @"" : @"_vertical"];
    NSImage *image = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:name]];
    if (flipped) {
        [image setFlipped:YES];
    }
    return image;
}

- (void)loadImagesWithHorizontalOrientation:(BOOL)horizontal
{
    _imagesHaveHorizontalOrientation = horizontal;

    // Aqua Tabs Images
    aquaTabBg = [self newImageNamed:@"AquaTabsBackground" flipped:YES];

    NSSize bgSize = [aquaTabBg size];
    noborderBg = [[NSImage alloc] initWithSize:NSMakeSize(bgSize.width, bgSize.height - 2)];
    if (horizontal) {
        [noborderBg lockFocus];
        [aquaTabBg compositeToPoint:NSMakePoint(0, 0)
                           fromRect:NSMakeRect(0, 1, bgSize.width, bgSize.height-2)
                          operation:NSCompositeSourceOver];
        [noborderBg unlockFocus];
        [noborderBg setSize:NSMakeSize(300, 28)];
    } else {
        [noborderBg lockFocus];
        [aquaTabBg compositeToPoint:NSMakePoint(0, 0)
                           fromRect:NSMakeRect(1, 0, bgSize.width-2, bgSize.height)
                          operation:NSCompositeSourceOver];
        [noborderBg unlockFocus];
        [noborderBg setSize:NSMakeSize(28, 300)];
    }

    aquaTabBgDown = [self newImageNamed:@"AquaTabsDown" flipped:YES];

    aquaTabBgDownGraphite = [self newImageNamed:@"AquaTabsDownGraphite" flipped:YES];

    aquaTabBgDownNonKey = [self newImageNamed:@"AquaTabsDownNonKey" flipped:YES];

    aquaDividerDown = [self newImageNamed:@"AquaTabsSeparatorDown" flipped:NO];

    aquaDivider = [self newImageNamed:@"AquaTabsSeparator" flipped:NO];

    aquaCloseButton = [[NSImage imageNamed:@"AquaTabClose_Front"] retain];
    aquaCloseButtonDown = [[NSImage imageNamed:@"AquaTabClose_Front_Pressed"] retain];
    aquaCloseButtonOver = [[NSImage imageNamed:@"AquaTabClose_Front_Rollover"] retain];

    _addTabButtonImage = [self newImageNamed:@"AquaTabNew" flipped:NO];
    _addTabButtonPressedImage = [self newImageNamed:@"AquaTabNewPressed" flipped:NO];
    _addTabButtonRolloverImage = [self newImageNamed:@"AquaTabNewRollover" flipped:NO];
}

- (void)dealloc
{
    [aquaTabBg release];
    [aquaTabBgDown release];
    [aquaDividerDown release];
    [aquaDivider release];
    [aquaCloseButton release];
    [aquaCloseButtonDown release];
    [aquaCloseButtonOver release];
    [_addTabButtonImage release];
    [_addTabButtonPressedImage release];
    [_addTabButtonRolloverImage release];

    [super dealloc];
}

#pragma mark -
#pragma mark Control Specifics

- (float)leftMarginForTabBarControl
{
    return 0.0f;
}

- (float)rightMarginForTabBarControl
{
    return 24.0f;
}

- (float)topMarginForTabBarControl
{
    return 0.0f;
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
#pragma mark Cell Specifics

- (NSRect)dragRectForTabCell:(PSMTabBarCell *)cell orientation:(PSMTabBarOrientation)orientation
{
    return [cell frame];
}

- (NSRect)closeButtonRectForTabCell:(PSMTabBarCell *)cell
{
    NSRect cellFrame = [cell frame];

    if ([cell hasCloseButton] == NO) {
        return NSZeroRect;
    }

    NSRect result;
    result.size = [aquaCloseButton size];
    result.origin.x = cellFrame.origin.x + MARGIN_X;
    result.origin.y = cellFrame.origin.y + MARGIN_Y + 2.0;

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
    result.origin.y = cellFrame.origin.y + MARGIN_Y;

    if([cell hasCloseButton] && ![cell isCloseButtonSuppressed])
        result.origin.x += [aquaCloseButton size].width + kPSMTabBarCellPadding;

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
    result.origin.y = cellFrame.origin.y + MARGIN_Y;

    return result;
}

- (NSRect)objectCounterRectForTabCell:(PSMTabBarCell *)cell
{
    NSRect cellFrame = [cell frame];

    if ([cell count] == 0) {
        return NSZeroRect;
    }

    float countWidth = [[self attributedObjectCountValueForTabCell:cell] size].width;
    countWidth += (2 * kPSMAquaObjectCounterRadius - 6.0);
    if(countWidth < kPSMAquaCounterMinWidth)
        countWidth = kPSMAquaCounterMinWidth;

    NSRect result;
    result.size = NSMakeSize(countWidth, 2 * kPSMAquaObjectCounterRadius); // temp
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
    if ([cell hasCloseButton] && ![cell isCloseButtonSuppressed])
        resultWidth += [aquaCloseButton size].width + kPSMTabBarCellPadding;

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
        resultWidth += [aquaCloseButton size].width + kPSMTabBarCellPadding;

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
    [attrStr addAttribute:NSFontAttributeName value:[NSFont fontWithName:@"Helvetica" size:11.0] range:range];
    [attrStr addAttribute:NSForegroundColorAttributeName value:[[NSColor blackColor] colorWithAlphaComponent:0.85] range:range];

    return attrStr;
}

- (NSAttributedString *)attributedStringValueForTabCell:(PSMTabBarCell *)cell
{
    NSMutableAttributedString *attrStr;
    NSString * contents = [cell stringValue];
    attrStr = [[[NSMutableAttributedString alloc] initWithString:contents] autorelease];
    NSRange range = NSMakeRange(0, [contents length]);

    [attrStr addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:11.0] range:range];

    // Paragraph Style for Truncating Long Text
    static NSMutableParagraphStyle *TruncatingTailParagraphStyle = nil;
    if (!TruncatingTailParagraphStyle) {
        TruncatingTailParagraphStyle = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] retain];
        [TruncatingTailParagraphStyle setLineBreakMode:NSLineBreakByTruncatingTail];
        [TruncatingTailParagraphStyle setAlignment:NSCenterTextAlignment];
    }
    [attrStr addAttribute:NSParagraphStyleAttributeName value:TruncatingTailParagraphStyle range:range];

    return attrStr;
}

#pragma mark -
#pragma mark Drawing

- (void)drawBackgroundImage:(NSImage *)bgImage
            tintedWithColor:(NSColor *)tabColor
                     inRect:(NSRect)cellFrame
{
    [NSGraphicsContext saveGraphicsState];
    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
    if (tabColor) {
        CGContextSetBlendMode(context, kCGBlendModeNormal);
        CGContextSetFillColorWithColor(context, [tabColor PSMCGColor]);
        CGContextFillRect(context, NSRectToCGRect(NSMakeRect(cellFrame.origin.x + 0.5,
                                                             cellFrame.origin.y + 0.5,
                                                             cellFrame.size.width,
                                                             cellFrame.size.height)));

        CGImageRef cgBgImage = CGImageCreateWithNSImage(bgImage, CGRectMake(0, 0, 1, bgImage.size.height));
        CGContextSetBlendMode(context, kCGBlendModeLuminosity);
        CGContextSetAlpha(context, 0.7);
        CGContextDrawImage(context, NSRectToCGRect(cellFrame), cgBgImage);
        CFRelease(cgBgImage);
    } else {
        [bgImage drawInRect:cellFrame
                   fromRect:_imagesHaveHorizontalOrientation ? NSMakeRect(0, 0, 1, bgImage.size.height)
                                                             : NSMakeRect(0, 0, bgImage.size.width, 1)
                  operation:NSCompositeSourceOver
                   fraction:1.0];
    }

    if (!_imagesHaveHorizontalOrientation) {
        [self drawVerticalMarginsInFrame:NSMakeRect(cellFrame.origin.x,
                                                    cellFrame.origin.y,
                                                    cellFrame.size.width,
                                                    cellFrame.size.height)];
    }
    [NSGraphicsContext restoreGraphicsState];
}

- (void)drawTabCell:(PSMTabBarCell *)cell
{
    NSRect cellFrame = [cell frame];

    NSImage *bgImage = aquaTabBg;
    NSColor* tabColor = [cell tabColor];

    // Selected Tab
    if ([cell state] == NSOnState) {
        NSRect aRect = NSMakeRect(cellFrame.origin.x, cellFrame.origin.y, cellFrame.size.width, cellFrame.size.height-2.5);
        aRect.size.height -= 0.5;

        // proper tint
        NSControlTint currentTint;
        if ([cell controlTint] == NSDefaultControlTint)
            currentTint = [NSColor currentControlTint];
        else
            currentTint = [cell controlTint];

        if (![[[cell controlView] window] isKeyWindow])
            currentTint = NSClearControlTint;

        switch(currentTint){
            case NSGraphiteControlTint:
                bgImage = aquaTabBgDownGraphite;
                break;
            case NSClearControlTint:
                bgImage = aquaTabBgDownNonKey;
                break;
            case NSBlueControlTint:
            default:
                bgImage = aquaTabBgDown;
                break;
        }

        [self drawBackgroundImage:bgImage tintedWithColor:tabColor inRect:cellFrame];

        aRect.size.height+=0.5;

    } else { // Unselected Tab

        NSRect aRect = NSMakeRect(cellFrame.origin.x,
                                  cellFrame.origin.y + 1,
                                  cellFrame.size.width,
                                  cellFrame.size.height - 2);
        if (!_imagesHaveHorizontalOrientation) {
            aRect.size.height += 1;
        }
        if (tabColor) {
            [self drawBackgroundImage:bgImage tintedWithColor:tabColor inRect:cellFrame];
        }

        // Rollover
        if ([cell isHighlighted]) {
            [[NSColor colorWithCalibratedWhite:0.0 alpha:0.1] set];
            NSRectFillUsingOperation(aRect, NSCompositeSourceAtop);
        }
    }

    NSPoint dividerOrigin;
    if (_imagesHaveHorizontalOrientation) {
        dividerOrigin = NSMakePoint(NSMaxX(cellFrame) - 1, NSMaxY(cellFrame));
        [aquaDivider compositeToPoint:dividerOrigin
                            operation:NSCompositeSourceOver];
    } else {
        dividerOrigin = NSMakePoint(NSMinX(cellFrame), NSMaxY(cellFrame));
        [aquaDivider drawInRect:NSMakeRect(dividerOrigin.x,
                                           dividerOrigin.y,
                                           cellFrame.size.width,
                                           1)
                       fromRect:NSMakeRect(0, 0, aquaDivider.size.width, aquaDivider.size.height)
                      operation:NSCompositeSourceOver
                       fraction:1];
        [self drawVerticalMarginsInFrame:NSMakeRect(dividerOrigin.x,
                                                    dividerOrigin.y,
                                                    cellFrame.size.width,
                                                    cellFrame.size.height)];
    }

    [self drawInteriorWithTabCell:cell inView:[cell controlView]];
}

- (void)drawVerticalMarginsInFrame:(NSRect)rect {
    [[NSColor colorWithRed:174.0 / 255.0
                     green:174.0 / 255.0
                      blue:174.0 / 255.0
                     alpha:1] set];
    NSRectFill(NSMakeRect(rect.origin.x, rect.origin.y, 1, rect.size.height));
    NSRectFill(NSMakeRect(rect.origin.x + rect.size.width - 1, rect.origin.y, 1, rect.size.height));
}

- (void)drawBackgroundInRect:(NSRect)rect color:(NSColor*)color horizontal:(BOOL)horizontal
{
    if (horizontal != _imagesHaveHorizontalOrientation) {
        [self loadImagesWithHorizontalOrientation:horizontal];
    }
    [aquaTabBg drawInRect:rect
                 fromRect:horizontal ? NSMakeRect(0, 0, 1, aquaTabBg.size.height) : NSMakeRect(0, 0, aquaTabBg.size.width, 1)
                operation:NSCompositeSourceOver
                 fraction:1.0];
    if (!_imagesHaveHorizontalOrientation) {
        [self drawVerticalMarginsInFrame:NSMakeRect(rect.origin.x,
                                                    rect.origin.y,
                                                    rect.size.width,
                                                    rect.size.height)];
    }
}

- (void)fillPath:(NSBezierPath*)path
{
    [[NSColor colorWithPatternImage:noborderBg] set];
    [path fill];
    [[NSColor colorWithCalibratedRed:150.0/255.0
                               green:150.0/255.0
                                blue:150.0/255.0
                               alpha:1] set];
    [path stroke];
}

- (void)drawTabBar:(PSMTabBarControl *)bar inRect:(NSRect)rect horizontal:(BOOL)horizontal
{
    PSMTabBarCell* activeCell = nil;
    for (PSMTabBarCell *cell in [bar cells]) {
        if ([cell state] == NSOnState) {
            activeCell = cell;
            break;
        }
    }
    [self drawBackgroundInRect:rect color:[activeCell tabColor] horizontal:horizontal];

    // no tab view == not connected
    if(![bar tabView]){
        NSRect labelRect = rect;
        labelRect.size.height -= 4.0;
        labelRect.origin.y += 4.0;
        NSString *contents = @"PSMTabBarControl";
        NSMutableAttributedString *attrStr = [[[NSMutableAttributedString alloc] initWithString:contents] autorelease];
        NSRange range = NSMakeRange(0, [contents length]);
        [attrStr addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:11.0] range:range];

        NSMutableParagraphStyle *centeredParagraphStyle = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
        [centeredParagraphStyle setAlignment:NSCenterTextAlignment];

        [attrStr addAttribute:NSParagraphStyleAttributeName value:centeredParagraphStyle range:range];
        [attrStr drawInRect:labelRect];
        return;
    }

    // Draw cells
    for (PSMTabBarCell *cell in [bar cells] ) {
        if (![cell isInOverflowMenu] && NSIntersectsRect([cell frame], rect)) {
            [cell drawWithFrame:[cell frame] inView:bar];
        }
    }
}

- (void)drawInteriorWithTabCell:(PSMTabBarCell *)cell inView:(NSView*)controlView
{
    NSRect cellFrame = [cell frame];
    float labelPosition = cellFrame.origin.x + MARGIN_X;

    // close button
    if([cell hasCloseButton] && ![cell isCloseButtonSuppressed]) {
        NSSize closeButtonSize = NSZeroSize;
        NSRect closeButtonRect = [cell closeButtonRectForFrame:cellFrame];
        NSImage *closeButton = nil;

        closeButton = aquaCloseButton;
        if([cell closeButtonOver]) closeButton = aquaCloseButtonOver;
        if([cell closeButtonPressed]) closeButton = aquaCloseButtonDown;

        closeButtonSize = [closeButton size];
        if([controlView isFlipped]) {
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
    labelRect.size.height = cellFrame.size.height;
    labelRect.origin.y = cellFrame.origin.y + MARGIN_Y + 1.0;

    if(![[cell indicator] isHidden])
        labelRect.size.width -= (kPSMTabBarIndicatorWidth + kPSMTabBarCellPadding);

    if([cell count] > 0)
        labelRect.size.width -= ([self objectCounterRectForTabCell:cell].size.width + kPSMTabBarCellPadding);

    // Draw Label
    [[cell attributedStringValue] drawInRect:labelRect];
}

#pragma mark -
#pragma mark Archiving

- (void)encodeWithCoder:(NSCoder *)aCoder {
    //[super encodeWithCoder:aCoder];
    if ([aCoder allowsKeyedCoding]) {
        [aCoder encodeObject:aquaTabBg forKey:@"aquaTabBg"];
        [aCoder encodeObject:aquaTabBgDown forKey:@"aquaTabBgDown"];
        [aCoder encodeObject:aquaTabBgDownGraphite forKey:@"aquaTabBgDownGraphite"];
        [aCoder encodeObject:aquaTabBgDownNonKey forKey:@"aquaTabBgDownNonKey"];
        [aCoder encodeObject:aquaDividerDown forKey:@"aquaDividerDown"];
        [aCoder encodeObject:aquaDivider forKey:@"aquaDivider"];
        [aCoder encodeObject:aquaCloseButton forKey:@"aquaCloseButton"];
        [aCoder encodeObject:aquaCloseButtonDown forKey:@"aquaCloseButtonDown"];
        [aCoder encodeObject:aquaCloseButtonOver forKey:@"aquaCloseButtonOver"];
        [aCoder encodeObject:_addTabButtonImage forKey:@"addTabButtonImage"];
        [aCoder encodeObject:_addTabButtonPressedImage forKey:@"addTabButtonPressedImage"];
        [aCoder encodeObject:_addTabButtonRolloverImage forKey:@"addTabButtonRolloverImage"];
    }
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    //self = [super initWithCoder:aDecoder];
    //if (self) {
        if ([aDecoder allowsKeyedCoding]) {
            aquaTabBg = [[aDecoder decodeObjectForKey:@"aquaTabBg"] retain];
            aquaTabBgDown = [[aDecoder decodeObjectForKey:@"aquaTabBgDown"] retain];
            aquaTabBgDownGraphite = [[aDecoder decodeObjectForKey:@"aquaTabBgDownGraphite"] retain];
            aquaTabBgDownNonKey = [[aDecoder decodeObjectForKey:@"aquaTabBgDownNonKey"] retain];
            aquaDividerDown = [[aDecoder decodeObjectForKey:@"aquaDividerDown"] retain];
            aquaDivider = [[aDecoder decodeObjectForKey:@"aquaDivider"] retain];
            aquaCloseButton = [[aDecoder decodeObjectForKey:@"aquaCloseButton"] retain];
            aquaCloseButtonDown = [[aDecoder decodeObjectForKey:@"aquaCloseButtonDown"] retain];
            aquaCloseButtonOver = [[aDecoder decodeObjectForKey:@"aquaCloseButtonOver"] retain];
            _addTabButtonImage = [[aDecoder decodeObjectForKey:@"addTabButtonImage"] retain];
            _addTabButtonPressedImage = [[aDecoder decodeObjectForKey:@"addTabButtonPressedImage"] retain];
            _addTabButtonRolloverImage = [[aDecoder decodeObjectForKey:@"addTabButtonRolloverImage"] retain];
        }
    //}
    return self;
}

@end
