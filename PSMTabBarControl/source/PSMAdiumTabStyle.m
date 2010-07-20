//
//  PSMAdiumTabStyle.m
//  PSMTabBarControl
//
//  Created by Kent Sutherland on 5/26/06.
//  Copyright 2006 Kent Sutherland. All rights reserved.
//

#import "PSMAdiumTabStyle.h"
#import "PSMTabBarCell.h"
#import "PSMTabBarControl.h"
#import "NSBezierPath_AMShading.h"

#define kPSMAdiumObjectCounterRadius 7.0
#define kPSMAdiumCounterMinWidth 20

@implementation PSMAdiumTabStyle

- (NSString *)name
{
    return @"Adium";
}

#pragma mark -
#pragma mark Creation/Destruction

- (id)init
{
    if ( (self = [super init]) ) {
		[self loadImages];
		_drawsUnified = NO;
		_drawsRight = NO;
    }
    return self;
}

- (void)loadImages
{
	_closeButton = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:@"AquaTabClose_Front"]];
	_closeButtonDown = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:@"AquaTabClose_Front_Pressed"]];
	_closeButtonOver = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:@"AquaTabClose_Front_Rollover"]];
	
	_addTabButtonImage = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:@"AquaTabNew"]];
    _addTabButtonPressedImage = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:@"AquaTabNewPressed"]];
    _addTabButtonRolloverImage = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:@"AquaTabNewRollover"]];
	
	_gradientImage = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:@"AdiumGradient"]];
}

- (void)dealloc
{
	[_closeButton release];
	[_closeButtonDown release];
	[_closeButtonOver release];
	
	[_addTabButtonImage release];
	[_addTabButtonPressedImage release];
	[_addTabButtonRolloverImage release];
	
	[_gradientImage release];
	
    [super dealloc];
}

#pragma mark -
#pragma mark Drawing Style Accessors

- (BOOL)drawsUnified
{
	return _drawsUnified;
}

- (void)setDrawsUnified:(BOOL)value
{
	_drawsUnified = value;
}

- (BOOL)drawsRight
{
	return _drawsRight;
}

- (void)setDrawsRight:(BOOL)value
{
	_drawsRight = value;
}

#pragma mark -
#pragma mark Control Specific

- (float)leftMarginForTabBarControl
{
    return 3.0f;
}

- (float)rightMarginForTabBarControl
{
    return [tabBar useOverflowMenu] ? 24.0f : 3.0f;
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

- (NSRect)dragRectForTabCell:(PSMTabBarCell *)cell orientation:(PSMTabBarOrientation)tabOrientation
{
	NSRect dragRect = [cell frame];
	
	if ([cell tabState] & PSMTab_SelectedMask) {
		if (tabOrientation == PSMTabBarHorizontalOrientation) {
			dragRect.size.width++;
			dragRect.size.height -= 2.0;
		}
	}
	
	return dragRect;
}

- (NSRect)closeButtonRectForTabCell:(PSMTabBarCell *)cell
{
	if ([cell hasCloseButton] == NO) {
		return NSZeroRect;
	}

	NSRect cellFrame = [cell frame];
	NSRect result;
	result.size = [_closeButton size];
	result.origin.x = cellFrame.origin.x + MARGIN_X;
	result.origin.y = cellFrame.origin.y + MARGIN_Y + 2.0;

	if ([cell state] == NSOnState) {
		result.origin.y -= 1;
	}

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

	if ([cell hasCloseButton] && ![cell isCloseButtonSuppressed]) {
		result.origin.x += [_closeButton size].width + kPSMTabBarCellPadding;
	}

	if ([cell state] == NSOnState) {
		result.origin.y -= 1;
	}

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

	if ([cell state] == NSOnState) {
		result.origin.y -= 1;
	}

	return result;
}

- (NSRect)objectCounterRectForTabCell:(PSMTabBarCell *)cell
{
	NSRect cellFrame = [cell frame];

	if ([cell count] == 0) {
		return NSZeroRect;
	}

	float countWidth = [[self attributedObjectCountValueForTabCell:cell] size].width;
	countWidth += (2 * kPSMAdiumObjectCounterRadius - 6.0);
	
	if (countWidth < kPSMAdiumCounterMinWidth) {
		countWidth = kPSMAdiumCounterMinWidth;
	}

	NSRect result;
	result.size = NSMakeSize(countWidth, 2 * kPSMAdiumObjectCounterRadius); // temp
	result.origin.x = cellFrame.origin.x + cellFrame.size.width - MARGIN_X - result.size.width;
	result.origin.y = cellFrame.origin.y + MARGIN_Y + 1.0;

	if (![[cell indicator] isHidden]) {
		result.origin.x -= kPSMTabBarIndicatorWidth + kPSMTabBarCellPadding;
	}

	return result;
}

- (float)minimumWidthOfTabCell:(PSMTabBarCell *)cell
{
	float resultWidth = 0.0;

	// left margin
	resultWidth = MARGIN_X;

	// close button?
	if ([cell hasCloseButton] && ![cell isCloseButtonSuppressed]) {
		resultWidth += [_closeButton size].width + kPSMTabBarCellPadding;
	}

	// icon?
	/*if ([cell hasIcon]) {
		resultWidth += kPSMTabBarIconWidth + kPSMTabBarCellPadding;
	}*/

	// the label
	resultWidth += kPSMMinimumTitleWidth;

	// object counter?
	if ([cell count] > 0) {
		resultWidth += [self objectCounterRectForTabCell:cell].size.width + kPSMTabBarCellPadding;
	}

	// indicator?
	if ([[cell indicator] isHidden] == NO) {
		resultWidth += kPSMTabBarCellPadding + kPSMTabBarIndicatorWidth;
	}

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
	if ([cell hasCloseButton] && ![cell isCloseButtonSuppressed]) {
		resultWidth += [_closeButton size].width + kPSMTabBarCellPadding;
	}

	// icon?
	/*if ([cell hasIcon]) {
		resultWidth += kPSMTabBarIconWidth + kPSMTabBarCellPadding;
	}*/

	// the label
	resultWidth += [[cell attributedStringValue] size].width;

	// object counter?
	// we don't make more room for the object counter in this style
	/*if ([cell count] > 0) {
		resultWidth += [self objectCounterRectForTabCell:cell].size.width + kPSMTabBarCellPadding;
	}*/

	// indicator?
	if ([[cell indicator] isHidden] == NO) {
		resultWidth += kPSMTabBarCellPadding + kPSMTabBarIndicatorWidth;
	}

	// right margin
	resultWidth += MARGIN_X;

	return ceil(resultWidth);
}

#pragma mark -
#pragma mark Cell Values

- (NSAttributedString *)attributedObjectCountValueForTabCell:(PSMTabBarCell *)cell
{
	NSMutableAttributedString *attrStr;
	NSFontManager *fm = [NSFontManager sharedFontManager];
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_4
    NSNumberFormatter *nf = [[[NSNumberFormatter alloc] init] autorelease];
    [nf setLocalizesFormat:YES];
    [nf setFormat:@"0"];
    [nf setHasThousandSeparators:YES];
    NSString *contents = [nf stringFromNumber:[NSNumber numberWithInt:[cell count]]];
#else
    NSString *contents = [NSString stringWithFormat:@"%d", [cell count]];
#endif
	attrStr = [[[NSMutableAttributedString alloc] initWithString:contents] autorelease];
	NSRange range = NSMakeRange(0, [contents length]);

	// Add font attribute
	[attrStr addAttribute:NSFontAttributeName value:[fm convertFont:[NSFont fontWithName:@"Helvetica" size:11.0] toHaveTrait:NSBoldFontMask] range:range];
	[attrStr addAttribute:NSForegroundColorAttributeName value:[[NSColor whiteColor] colorWithAlphaComponent:0.85] range:range];

	return attrStr;
}

- (NSAttributedString *)attributedStringValueForTabCell:(PSMTabBarCell *)cell
{
	NSMutableAttributedString *attrStr;
	NSString *contents = [cell stringValue];
	attrStr = [[[NSMutableAttributedString alloc] initWithString:contents] autorelease];
	NSRange range = NSMakeRange(0, [contents length]);

	// Add font attribute
	[attrStr addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:11.0] range:range];
	[attrStr addAttribute:NSForegroundColorAttributeName value:[NSColor controlTextColor] range:range];

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
#pragma mark Cell Drawing

- (void)drawInteriorWithTabCell:(PSMTabBarCell *)cell inView:(NSView*)controlView
{
	NSRect cellFrame = [cell frame];
	float labelPosition = cellFrame.origin.x + MARGIN_X;
	
	//draw the close button and icon combined
	if ([cell hasCloseButton] && ![cell isCloseButtonSuppressed]) {
		NSSize closeButtonSize = NSZeroSize;
		NSRect closeButtonRect = [cell closeButtonRectForFrame:cellFrame];
		NSImage *closeButton = nil;
		
		if ([cell hasIcon]) {
			closeButton = [[[cell representedObject] identifier] icon];
			closeButtonRect.origin.y += 1;
		} else {
			closeButton = _closeButton;
		}
		
		if ([cell closeButtonOver]) {
			closeButton = _closeButtonOver;
		}
		
		if ([cell closeButtonPressed]) {
			closeButton = _closeButtonDown;
		}
		
		closeButtonSize = [closeButton size];
		if ([controlView isFlipped]) {
			closeButtonRect.origin.y += closeButtonRect.size.height;
		}
		
		[closeButton compositeToPoint:closeButtonRect.origin operation:NSCompositeSourceOver fraction:1.0];
		
		// scoot label over by the size of the standard close button
		labelPosition += [_closeButton size].width + kPSMTabBarCellPadding;
	} else if ([cell hasIcon]) {
		NSRect iconRect = [self iconRectForTabCell:cell];
		NSImage *icon = [[[cell representedObject] identifier] icon];
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
	if ([cell count] > 0) {
		[[NSColor colorWithCalibratedWhite:0.3 alpha:0.6] set];
		NSBezierPath *path = [NSBezierPath bezierPath];
		[path setLineWidth:1.0];
		NSRect myRect = [self objectCounterRectForTabCell:cell];
		
		if ([cell state] == NSOnState) {
			myRect.origin.y -= 1.0;
		}
		
		[path moveToPoint:NSMakePoint(myRect.origin.x + kPSMAdiumObjectCounterRadius, myRect.origin.y)];
		[path lineToPoint:NSMakePoint(myRect.origin.x + myRect.size.width - kPSMAdiumObjectCounterRadius, myRect.origin.y)];
		[path appendBezierPathWithArcWithCenter:NSMakePoint(myRect.origin.x + myRect.size.width - kPSMAdiumObjectCounterRadius, myRect.origin.y + kPSMAdiumObjectCounterRadius) radius:kPSMAdiumObjectCounterRadius startAngle:270.0 endAngle:90.0];
		[path lineToPoint:NSMakePoint(myRect.origin.x + kPSMAdiumObjectCounterRadius, myRect.origin.y + myRect.size.height)];
		[path appendBezierPathWithArcWithCenter:NSMakePoint(myRect.origin.x + kPSMAdiumObjectCounterRadius, myRect.origin.y + kPSMAdiumObjectCounterRadius) radius:kPSMAdiumObjectCounterRadius startAngle:90.0 endAngle:270.0];
		[path fill];
		
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
	
	if ([cell state] == NSOnState) {
		labelRect.origin.y -= 1;
	}
	
	if (![[cell indicator] isHidden]) {
		labelRect.size.width -= (kPSMTabBarIndicatorWidth + kPSMTabBarCellPadding);
	}
	
	if ([cell count] > 0) {
		labelRect.size.width -= ([self objectCounterRectForTabCell:cell].size.width + kPSMTabBarCellPadding);
	}
	
	// label
	[[cell attributedStringValue] drawInRect:labelRect];
}

- (void)drawTabCell:(PSMTabBarCell *)cell
{
	NSRect cellFrame = [cell frame];
	NSColor *lineColor = nil;
    NSBezierPath *bezier = [NSBezierPath bezierPath];
    lineColor = [NSColor grayColor];

	[bezier setLineWidth:1.0];

	//disable antialiasing of bezier paths
	[NSGraphicsContext saveGraphicsState];
	[[NSGraphicsContext currentContext] setShouldAntialias:NO];
	
	NSShadow *shadow = [[NSShadow alloc] init];
	[shadow setShadowOffset:NSMakeSize(-2, -2)];
	[shadow setShadowBlurRadius:2];
	[shadow setShadowColor:[NSColor colorWithCalibratedWhite:0.6 alpha:1.0]];

	if ([cell state] == NSOnState) {
		// selected tab
		if (orientation == PSMTabBarHorizontalOrientation) {
			NSRect aRect = NSMakeRect(cellFrame.origin.x, cellFrame.origin.y, cellFrame.size.width, cellFrame.size.height - 2.5);
			
			// background
			if (_drawsUnified) {
				if ([[[tabBar tabView] window] isKeyWindow]) {
					NSBezierPath *path = [NSBezierPath bezierPathWithRect:aRect];
					[path linearGradientFillWithStartColor:[NSColor colorWithCalibratedWhite:0.835 alpha:1.0]
												endColor:[NSColor colorWithCalibratedWhite:0.843 alpha:1.0]];
				} else {
					[[NSColor windowBackgroundColor] set];
					NSRectFill(aRect);
				}
			} else {
				[_gradientImage drawInRect:NSMakeRect(aRect.origin.x, aRect.origin.y, aRect.size.width, aRect.size.height) fromRect:NSMakeRect(0, 0, [_gradientImage size].width, [_gradientImage size].height) operation:NSCompositeSourceOver fraction:1.0];
			}
			
			// frame
			[lineColor set];
			[bezier setLineWidth:1.0];
			[bezier moveToPoint:NSMakePoint(aRect.origin.x, aRect.origin.y)];
			[bezier lineToPoint:NSMakePoint(aRect.origin.x, aRect.origin.y + aRect.size.height)];
			
			[shadow setShadowOffset:NSMakeSize(-2, -2)];
			[shadow set];
			[bezier stroke];
			
			bezier = [NSBezierPath bezierPath];
			[bezier setLineWidth:1.0];
			[bezier moveToPoint:NSMakePoint(aRect.origin.x, aRect.origin.y + aRect.size.height)];
			[bezier lineToPoint:NSMakePoint(aRect.origin.x + aRect.size.width, aRect.origin.y + aRect.size.height)];
			[bezier lineToPoint:NSMakePoint(aRect.origin.x + aRect.size.width, aRect.origin.y)];
			
			if ([[cell controlView] frame].size.height < 2) {
				// special case of hidden control; need line across top of cell
				[bezier moveToPoint:NSMakePoint(aRect.origin.x, aRect.origin.y + 0.5)];
				[bezier lineToPoint:NSMakePoint(aRect.origin.x+aRect.size.width, aRect.origin.y + 0.5)];
			}
			
			[shadow setShadowOffset:NSMakeSize(2, -2)];
			[shadow set];
			[bezier stroke];
		} else {
			NSRect aRect;
			
			if (_drawsRight) {
				aRect = NSMakeRect(cellFrame.origin.x - 1, cellFrame.origin.y, cellFrame.size.width - 3, cellFrame.size.height);
			} else {
				aRect = NSMakeRect(cellFrame.origin.x + 2, cellFrame.origin.y, cellFrame.size.width - 2, cellFrame.size.height);
			}
			
			// background
			if (_drawsUnified) {
				if ([[[tabBar tabView] window] isKeyWindow]) {
					NSBezierPath *path = [NSBezierPath bezierPathWithRect:aRect];
					[path linearGradientFillWithStartColor:[NSColor colorWithCalibratedWhite:0.835 alpha:1.0]
												endColor:[NSColor colorWithCalibratedWhite:0.843 alpha:1.0]];
				} else {
					[[NSColor windowBackgroundColor] set];
					NSRectFill(aRect);
				}
			} else {
				[_gradientImage drawInRect:NSMakeRect(aRect.origin.x, aRect.origin.y, aRect.size.width, aRect.size.height) fromRect:NSMakeRect(0, 0, [_gradientImage size].width, [_gradientImage size].height) operation:NSCompositeSourceOver fraction:1.0];
			}
			
			// frame
			//bottom line
			[lineColor set];
			[bezier setLineWidth:1.0];
			[bezier moveToPoint:NSMakePoint(aRect.origin.x + aRect.size.width, aRect.origin.y)];
			[bezier lineToPoint:NSMakePoint(aRect.origin.x, aRect.origin.y)];
			[shadow setShadowOffset:NSMakeSize(_drawsRight ? 2 : -2, 2)];
			[shadow set];
			[bezier stroke];
			
			//left and top lines
			bezier = [NSBezierPath bezierPath];
			[bezier setLineWidth:1.0];
			if (_drawsRight) {
				[bezier moveToPoint:NSMakePoint(aRect.origin.x + aRect.size.width, aRect.origin.y)];
				[bezier lineToPoint:NSMakePoint(aRect.origin.x + aRect.size.width, aRect.origin.y + aRect.size.height)];
				[bezier lineToPoint:NSMakePoint(aRect.origin.x, aRect.origin.y + aRect.size.height)];
			} else {
				[bezier moveToPoint:NSMakePoint(aRect.origin.x, aRect.origin.y)];
				[bezier lineToPoint:NSMakePoint(aRect.origin.x, aRect.origin.y + aRect.size.height)];
				[bezier lineToPoint:NSMakePoint(aRect.origin.x + aRect.size.width, aRect.origin.y + aRect.size.height)];
			}
			[shadow setShadowOffset:NSMakeSize(_drawsRight ? 2 : -2, -2)];
			[shadow set];
			[bezier stroke];
		}
	} else {
		// unselected tab
		NSRect aRect = NSMakeRect(cellFrame.origin.x, cellFrame.origin.y, cellFrame.size.width, cellFrame.size.height);
		
		// rollover
		if ([cell isHighlighted]) {
			[[NSColor colorWithCalibratedWhite:0.0 alpha:0.1] set];
			NSRectFillUsingOperation(aRect, NSCompositeSourceAtop);
		}
		
		// frame
		[lineColor set];
		
		if (orientation == PSMTabBarHorizontalOrientation) {
			[bezier moveToPoint:NSMakePoint(aRect.origin.x, aRect.origin.y)];
			[bezier lineToPoint:NSMakePoint(aRect.origin.x + aRect.size.width, aRect.origin.y)];
			if (!([cell tabState] & PSMTab_RightIsSelectedMask)) {
				//draw the tab divider
				[bezier lineToPoint:NSMakePoint(aRect.origin.x + aRect.size.width, aRect.origin.y + aRect.size.height)];
			}
		} else {
			if (!([cell tabState] & PSMTab_LeftIsSelectedMask)) {
				[bezier moveToPoint:NSMakePoint(aRect.origin.x, aRect.origin.y)];
				[bezier lineToPoint:NSMakePoint(aRect.origin.x + aRect.size.width, aRect.origin.y)];
			}
			
			if (!([cell tabState] & PSMTab_RightIsSelectedMask)) {
				[bezier moveToPoint:NSMakePoint(aRect.origin.x, aRect.origin.y + aRect.size.height)];
				[bezier lineToPoint:NSMakePoint(aRect.origin.x + aRect.size.width, aRect.origin.y + aRect.size.height)];
			}
		}
		[bezier stroke];
	}
	
	[NSGraphicsContext restoreGraphicsState];
	[shadow release];
	
	[self drawInteriorWithTabCell:cell inView:[cell controlView]];
}

- (void)drawBackgroundInRect:(NSRect)rect
{
	NSBezierPath *path = [NSBezierPath bezierPath];
	[path setLineWidth:1.0];
	
	if (_drawsUnified && [[[tabBar tabView] window] isKeyWindow]) {
		if ([[[tabBar tabView] window] isKeyWindow]) {
			NSBezierPath *path = [NSBezierPath bezierPathWithRect:rect];
			[path linearGradientFillWithStartColor:[NSColor colorWithCalibratedWhite:0.835 alpha:1.0]
										endColor:[NSColor colorWithCalibratedWhite:0.843 alpha:1.0]];
		} else {
			[[NSColor windowBackgroundColor] set];
			NSRectFill(rect);
		}
	} else {
		[[NSColor colorWithCalibratedWhite:0.85 alpha:0.6] set];
		[NSBezierPath fillRect:rect];
	}
	
	NSShadow *shadow = [[NSShadow alloc] init];
	[shadow setShadowBlurRadius:2];
	[shadow setShadowColor:[NSColor colorWithCalibratedWhite:0.6 alpha:1.0]];
	
	if (orientation == PSMTabBarHorizontalOrientation) {
		rect.origin.y++;
		[path moveToPoint:NSMakePoint(rect.origin.x, rect.origin.y)];
		[path lineToPoint:NSMakePoint(rect.origin.x + rect.size.width, rect.origin.y)];
		[shadow setShadowOffset:NSMakeSize(2, -2)];
	} else {
		NSPoint startPoint, endPoint;
		NSSize shadowSize;
		
		if (_drawsRight) {
			startPoint = NSMakePoint(rect.origin.x, rect.origin.y);
			endPoint = NSMakePoint(rect.origin.x, rect.origin.y + rect.size.height);
			shadowSize = NSMakeSize(2, -2);
		} else {
			startPoint = NSMakePoint(rect.origin.x + rect.size.width - 1, rect.origin.y);
			endPoint = NSMakePoint(rect.origin.x + rect.size.width - 1, rect.origin.y + rect.size.height);
			shadowSize = NSMakeSize(-2, -2);
		}
		
		[path moveToPoint:startPoint];
		[path lineToPoint:endPoint];
		[shadow setShadowOffset:shadowSize];
	}
	
	[NSGraphicsContext saveGraphicsState];
	[[NSColor grayColor] set];
	[shadow set];
	[shadow release];
	[[NSGraphicsContext currentContext] setShouldAntialias:NO];
	[path stroke];
	[NSGraphicsContext restoreGraphicsState];
}

- (void)drawTabBar:(PSMTabBarControl *)bar inRect:(NSRect)rect
{
	if (orientation != [bar orientation]) {
		orientation = [bar orientation];
	}
	
	if (tabBar != bar) {
		tabBar = bar;
	}
	
	[self drawBackgroundInRect:rect];
	
	// no tab view == not connected
	if (![bar tabView]) {
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
			centeredParagraphStyle = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] retain];
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
    if ([aCoder allowsKeyedCoding]) {
        [aCoder encodeObject:_closeButton forKey:@"closeButton"];
        [aCoder encodeObject:_closeButtonDown forKey:@"closeButtonDown"];
        [aCoder encodeObject:_closeButtonOver forKey:@"closeButtonOver"];
        [aCoder encodeObject:_addTabButtonImage forKey:@"addTabButtonImage"];
        [aCoder encodeObject:_addTabButtonPressedImage forKey:@"addTabButtonPressedImage"];
        [aCoder encodeObject:_addTabButtonRolloverImage forKey:@"addTabButtonRolloverImage"];
		[aCoder encodeBool:_drawsUnified forKey:@"drawsUnified"];
		[aCoder encodeBool:_drawsRight forKey:@"drawsRight"];
    }
}

- (id)initWithCoder:(NSCoder *)aDecoder 
{
   if ( (self = [super init]) ) {
        if ([aDecoder allowsKeyedCoding]) {
            _closeButton = [[aDecoder decodeObjectForKey:@"metalCloseButton"] retain];
            _closeButtonDown = [[aDecoder decodeObjectForKey:@"metalCloseButtonDown"] retain];
            _closeButtonOver = [[aDecoder decodeObjectForKey:@"metalCloseButtonOver"] retain];
            _addTabButtonImage = [[aDecoder decodeObjectForKey:@"addTabButtonImage"] retain];
            _addTabButtonPressedImage = [[aDecoder decodeObjectForKey:@"addTabButtonPressedImage"] retain];
            _addTabButtonRolloverImage = [[aDecoder decodeObjectForKey:@"addTabButtonRolloverImage"] retain];
			_drawsUnified = [aDecoder decodeBoolForKey:@"drawsUnified"];
			_drawsRight = [aDecoder decodeBoolForKey:@"drawsRight"];
        }
    }
    return self;
}

@end
