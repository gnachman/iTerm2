//
//  PSMMetalTabStyle.m
//  PSMTabBarControl
//
//  Created by John Pannell on 2/17/06.
//  Copyright 2006 Positive Spin Media. All rights reserved.
//

#import "PSMMetalTabStyle.h"
#import "PSMTabBarCell.h"
#import "PSMTabBarControl.h"

#define kPSMMetalObjectCounterRadius 7.0
#define kPSMMetalCounterMinWidth 20

@implementation PSMMetalTabStyle

- (NSString *)name
{
    return @"Metal";
}

#pragma mark -
#pragma mark Creation/Destruction

- (id) init
{
    if( (self = [super init]) ) {
        metalCloseButton = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:@"TabClose_Front"]];
        metalCloseButtonDown = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:@"TabClose_Front_Pressed"]];
        metalCloseButtonOver = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:@"TabClose_Front_Rollover"]];
        
        _addTabButtonImage = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:@"TabNewMetal"]];
        _addTabButtonPressedImage = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:@"TabNewMetalPressed"]];
        _addTabButtonRolloverImage = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:@"TabNewMetalRollover"]];
		
		_objectCountStringAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:[[NSFontManager sharedFontManager] convertFont:[NSFont fontWithName:@"Helvetica" size:11.0] toHaveTrait:NSBoldFontMask], NSFontAttributeName,
																					[[NSColor whiteColor] colorWithAlphaComponent:0.85], NSForegroundColorAttributeName,
																					nil, nil];
    }
    return self;
}

- (void)dealloc
{
    [metalCloseButton release];
    [metalCloseButtonDown release];
    [metalCloseButtonOver release];
    [_addTabButtonImage release];
    [_addTabButtonPressedImage release];
    [_addTabButtonRolloverImage release];
    
	[_objectCountStringAttributes release];
	
    [super dealloc];
}

#pragma mark -
#pragma mark Control Specific

- (float)leftMarginForTabBarControl
{
    return 10.0f;
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

- (NSRect)dragRectForTabCell:(PSMTabBarCell *)cell orientation:(PSMTabBarOrientation)tabOrientation
{
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

- (NSRect)closeButtonRectForTabCell:(PSMTabBarCell *)cell
{
    NSRect cellFrame = [cell frame];
    
    if ([cell hasCloseButton] == NO) {
        return NSZeroRect;
    }
    
    NSRect result;
    result.size = [metalCloseButton size];
    result.origin.x = cellFrame.origin.x + MARGIN_X;
    result.origin.y = cellFrame.origin.y + MARGIN_Y + 2.0;
    
    if([cell state] == NSOnState){
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
    
    if([cell hasCloseButton] && ![cell isCloseButtonSuppressed])
        result.origin.x += [metalCloseButton size].width + kPSMTabBarCellPadding;
    
    if([cell state] == NSOnState){
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
    
    if([cell state] == NSOnState){
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
    countWidth += (2 * kPSMMetalObjectCounterRadius - 6.0);
    if(countWidth < kPSMMetalCounterMinWidth)
        countWidth = kPSMMetalCounterMinWidth;
    
    NSRect result;
    result.size = NSMakeSize(countWidth, 2 * kPSMMetalObjectCounterRadius); // temp
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
        resultWidth += [metalCloseButton size].width + kPSMTabBarCellPadding;
    
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
        resultWidth += [metalCloseButton size].width + kPSMTabBarCellPadding;
    
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
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_4
    NSNumberFormatter *nf = [[[NSNumberFormatter alloc] init] autorelease];
    [nf setLocalizesFormat:YES];
    [nf setFormat:@"0"];
    [nf setHasThousandSeparators:YES];
    NSString *contents = [nf stringFromNumber:[NSNumber numberWithInt:[cell count]]];
#else
    NSString *contents = [NSString stringWithFormat:@"%d", [cell count]];
#endif
    return [[[NSMutableAttributedString alloc] initWithString:contents attributes:_objectCountStringAttributes] autorelease];
}

- (NSAttributedString *)attributedStringValueForTabCell:(PSMTabBarCell *)cell
{
    NSMutableAttributedString *attrStr;
    NSString *contents = [cell stringValue];
    attrStr = [[[NSMutableAttributedString alloc] initWithString:contents] autorelease];
    NSRange range = NSMakeRange(0, [contents length]);
    
    // Add font attribute
    [attrStr addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:11.0] range:range];
    [attrStr addAttribute:NSForegroundColorAttributeName value:[[NSColor textColor] colorWithAlphaComponent:0.75] range:range];
    
    // Add shadow attribute
    NSShadow* shadow;
    shadow = [[[NSShadow alloc] init] autorelease];
    float shadowAlpha;
    if(([cell state] == NSOnState) || [cell isHighlighted]){
        shadowAlpha = 0.8;
    } else {
        shadowAlpha = 0.5;
    }
    [shadow setShadowColor:[NSColor colorWithCalibratedWhite:1.0 alpha:shadowAlpha]];
    [shadow setShadowOffset:NSMakeSize(0, -1)];
    [shadow setShadowBlurRadius:1.0];
    [attrStr addAttribute:NSShadowAttributeName value:shadow range:range];
    
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
#pragma mark ---- drawing ----

- (void)drawTabCell:(PSMTabBarCell *)cell
{
    NSRect cellFrame = [cell frame];	
    NSColor *lineColor = nil;
    NSBezierPath *bezier = [NSBezierPath bezierPath];
    lineColor = [NSColor darkGrayColor];
	
	//disable antialiasing of bezier paths
	[NSGraphicsContext saveGraphicsState];
	[[NSGraphicsContext currentContext] setShouldAntialias:NO];
	
    if ([cell state] == NSOnState) {
        // selected tab
		if (orientation == PSMTabBarHorizontalOrientation) {
			NSRect aRect = NSMakeRect(cellFrame.origin.x, cellFrame.origin.y, cellFrame.size.width, cellFrame.size.height-2.5);
			
			// background
			aRect.origin.x += 1.0;
			aRect.size.width--;
			aRect.size.height -= 0.5;
			NSDrawWindowBackground(aRect);
			aRect.size.width++;
			aRect.size.height += 0.5;
			
			// frame
			aRect.origin.x -= 0.5;
			[lineColor set];
			[bezier setLineWidth:1.0];
			[bezier moveToPoint:NSMakePoint(aRect.origin.x, aRect.origin.y)];
			[bezier lineToPoint:NSMakePoint(aRect.origin.x, aRect.origin.y+aRect.size.height-1.5)];
			[bezier lineToPoint:NSMakePoint(aRect.origin.x+1.5, aRect.origin.y+aRect.size.height)];
			[bezier lineToPoint:NSMakePoint(aRect.origin.x+aRect.size.width-2.5, aRect.origin.y+aRect.size.height)];
			[bezier lineToPoint:NSMakePoint(aRect.origin.x+aRect.size.width, aRect.origin.y+aRect.size.height-1.5)];
			[bezier lineToPoint:NSMakePoint(aRect.origin.x+aRect.size.width, aRect.origin.y)];
			if ([[cell controlView] frame].size.height < 2) {
				// special case of hidden control; need line across top of cell
				[bezier moveToPoint:NSMakePoint(aRect.origin.x, aRect.origin.y+0.5)];
				[bezier lineToPoint:NSMakePoint(aRect.origin.x+aRect.size.width, aRect.origin.y+0.5)];
			}
		} else {
			NSRect aRect = NSMakeRect(cellFrame.origin.x + 2, cellFrame.origin.y, cellFrame.size.width - 2, cellFrame.size.height);
			
			// background
			aRect.origin.x++;
			aRect.size.height--;
			NSDrawWindowBackground(aRect);
			aRect.origin.x--;
			aRect.size.height++;
			
			// frame
			[lineColor set];
			[bezier setLineWidth:1.0];
			[bezier moveToPoint:NSMakePoint(aRect.origin.x + aRect.size.width, aRect.origin.y)];
			[bezier lineToPoint:NSMakePoint(aRect.origin.x + 2, aRect.origin.y)];
			[bezier lineToPoint:NSMakePoint(aRect.origin.x + 0.5, aRect.origin.y + 2)];
			[bezier lineToPoint:NSMakePoint(aRect.origin.x + 0.5, aRect.origin.y + aRect.size.height - 3)];
			[bezier lineToPoint:NSMakePoint(aRect.origin.x + 3, aRect.origin.y + aRect.size.height)];
			[bezier lineToPoint:NSMakePoint(aRect.origin.x + aRect.size.width, aRect.origin.y + aRect.size.height)];
		}
		
        [bezier stroke];
    } else {
        
        // unselected tab
        NSRect aRect = NSMakeRect(cellFrame.origin.x, cellFrame.origin.y, cellFrame.size.width, cellFrame.size.height);
        aRect.origin.y += 0.5;
        aRect.origin.x += 1.5;
        aRect.size.width -= 1;
        
        // rollover
        if ([cell isHighlighted]) {
            [[NSColor colorWithCalibratedWhite:0.0 alpha:0.1] set];
            NSRectFillUsingOperation(aRect, NSCompositeSourceAtop);
        }
        
		[lineColor set];
		
		if (orientation == PSMTabBarHorizontalOrientation) {
			aRect.origin.x -= 1;
			aRect.size.width += 1;
			
			// frame
			[bezier moveToPoint:NSMakePoint(aRect.origin.x, aRect.origin.y)];
			[bezier lineToPoint:NSMakePoint(aRect.origin.x + aRect.size.width, aRect.origin.y)];
			if (!([cell tabState] & PSMTab_RightIsSelectedMask)) {
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
        
        closeButton = metalCloseButton;
        if ([cell closeButtonOver]) closeButton = metalCloseButtonOver;
        if ([cell closeButtonPressed]) closeButton = metalCloseButtonDown;
        
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
    if([cell count] > 0){
        [[NSColor colorWithCalibratedWhite:0.3 alpha:0.6] set];
        NSBezierPath *path = [NSBezierPath bezierPath];
        NSRect myRect = [self objectCounterRectForTabCell:cell];
        if([cell state] == NSOnState)
            myRect.origin.y -= 1.0;
        [path moveToPoint:NSMakePoint(myRect.origin.x + kPSMMetalObjectCounterRadius, myRect.origin.y)];
        [path lineToPoint:NSMakePoint(myRect.origin.x + myRect.size.width - kPSMMetalObjectCounterRadius, myRect.origin.y)];
        [path appendBezierPathWithArcWithCenter:NSMakePoint(myRect.origin.x + myRect.size.width - kPSMMetalObjectCounterRadius, myRect.origin.y + kPSMMetalObjectCounterRadius) radius:kPSMMetalObjectCounterRadius startAngle:270.0 endAngle:90.0];
        [path lineToPoint:NSMakePoint(myRect.origin.x + kPSMMetalObjectCounterRadius, myRect.origin.y + myRect.size.height)];
        [path appendBezierPathWithArcWithCenter:NSMakePoint(myRect.origin.x + kPSMMetalObjectCounterRadius, myRect.origin.y + kPSMMetalObjectCounterRadius) radius:kPSMMetalObjectCounterRadius startAngle:90.0 endAngle:270.0];
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
    
    if([cell state] == NSOnState){
        labelRect.origin.y -= 1;
    }
    
    if(![[cell indicator] isHidden])
        labelRect.size.width -= (kPSMTabBarIndicatorWidth + kPSMTabBarCellPadding);
    
    if([cell count] > 0)
        labelRect.size.width -= ([self objectCounterRectForTabCell:cell].size.width + kPSMTabBarCellPadding);
    
    // label
    [[cell attributedStringValue] drawInRect:labelRect];
}

- (void)drawBackgroundInRect:(NSRect)rect
{
	if (orientation == PSMTabBarVerticalOrientation && [tabBar frame].size.width < 2) {
		return;
	}
	
	[NSGraphicsContext saveGraphicsState];
	[[NSGraphicsContext currentContext] setShouldAntialias:NO];
	
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.2] set];
    NSRectFillUsingOperation(rect, NSCompositeSourceAtop);
	[[NSColor darkGrayColor] set];
	
	if (orientation == PSMTabBarHorizontalOrientation) {
		[NSBezierPath strokeLineFromPoint:NSMakePoint(rect.origin.x, rect.origin.y + 0.5) toPoint:NSMakePoint(rect.origin.x + rect.size.width, rect.origin.y + 0.5)];
		[NSBezierPath strokeLineFromPoint:NSMakePoint(rect.origin.x, rect.origin.y + rect.size.height - 0.5) toPoint:NSMakePoint(rect.origin.x + rect.size.width, rect.origin.y + rect.size.height - 0.5)];
	} else {
		[NSBezierPath strokeLineFromPoint:NSMakePoint(rect.origin.x, rect.origin.y + 0.5) toPoint:NSMakePoint(rect.origin.x, rect.origin.y + rect.size.height + 0.5)];
		[NSBezierPath strokeLineFromPoint:NSMakePoint(rect.origin.x + rect.size.width, rect.origin.y + 0.5) toPoint:NSMakePoint(rect.origin.x + rect.size.width, rect.origin.y + rect.size.height + 0.5)];
	}
	
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
    //[super encodeWithCoder:aCoder];
    if ([aCoder allowsKeyedCoding]) {
        [aCoder encodeObject:metalCloseButton forKey:@"metalCloseButton"];
        [aCoder encodeObject:metalCloseButtonDown forKey:@"metalCloseButtonDown"];
        [aCoder encodeObject:metalCloseButtonOver forKey:@"metalCloseButtonOver"];
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
            metalCloseButton = [[aDecoder decodeObjectForKey:@"metalCloseButton"] retain];
            metalCloseButtonDown = [[aDecoder decodeObjectForKey:@"metalCloseButtonDown"] retain];
            metalCloseButtonOver = [[aDecoder decodeObjectForKey:@"metalCloseButtonOver"] retain];
            _addTabButtonImage = [[aDecoder decodeObjectForKey:@"addTabButtonImage"] retain];
            _addTabButtonPressedImage = [[aDecoder decodeObjectForKey:@"addTabButtonPressedImage"] retain];
            _addTabButtonRolloverImage = [[aDecoder decodeObjectForKey:@"addTabButtonRolloverImage"] retain];
        }
    //}
    return self;
}

@end
