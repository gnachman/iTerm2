//
//  PSMTabBarCell.m
//  PSMTabBarControl
//
//  Created by John Pannell on 10/13/05.
//  Copyright 2005 Positive Spin Media. All rights reserved.
//

#import "PSMTabBarCell.h"
#import "PSMTabBarControl.h"
#import "PSMTabStyle.h"
#import "PSMProgressIndicator.h"
#import "PSMTabDragAssistant.h"
#import "FutureMethods.h"

@interface PSMTabBarControl (Private)
- (void)update;
- (void)update:(BOOL)animate;
@end

@implementation PSMTabBarCell

@synthesize isLast = _isLast;

#pragma mark -
#pragma mark Creation/Destruction
- (id)initWithControlView:(PSMTabBarControl *)controlView
{
    if ( (self = [super init]) ) {
        _controlView = controlView;
        _closeButtonTrackingTag = 0;
        _cellTrackingTag = 0;
        _closeButtonOver = NO;
        _closeButtonPressed = NO;
        _indicator = [[PSMProgressIndicator alloc] initWithFrame:NSMakeRect(0.0,0.0,kPSMTabBarIndicatorWidth,kPSMTabBarIndicatorWidth)];
        [_indicator setStyle:NSProgressIndicatorSpinningStyle];
        [_indicator setAutoresizingMask:NSViewMinYMargin];
        [_indicator setControlSize:NSSmallControlSize];
        _hasCloseButton = YES;
        _isCloseButtonSuppressed = NO;
        _count = 0;
        _isPlaceholder = NO;
        _labelColor = nil;
        _tabColor = nil;
        _modifierString = [@"" copy];
    }
    return self;
}

- (id)initPlaceholderWithFrame:(NSRect)frame expanded:(BOOL)value inControlView:(PSMTabBarControl *)controlView
{
    if ( (self = [super init]) ) {
        _controlView = controlView;
        _isPlaceholder = YES;
        if (!value) {
            if ([controlView orientation] == PSMTabBarHorizontalOrientation) {
                frame.size.width = 0.0;
            } else {
                frame.size.height = 0.0;
            }
        }
        [self setFrame:frame];
        _closeButtonTrackingTag = 0;
        _cellTrackingTag = 0;
        _closeButtonOver = NO;
        _closeButtonPressed = NO;
        _indicator = nil;
        _hasCloseButton = YES;
        _isCloseButtonSuppressed = NO;
        _count = 0;
        _labelColor = nil;
        _tabColor = nil;
        _modifierString = [@"" copy];
        if (value) {
            [self setCurrentStep:(kPSMTabDragAnimationSteps - 1)];
        } else {
            [self setCurrentStep:0];
        }
    }
    return self;
}

- (void)dealloc
{
    [_modifierString release];
    [_indicator release];
    if (_labelColor)
        [_labelColor release];
    if (_tabColor)
        [_tabColor release];
    [super dealloc];
}

// we don't want this to be the first responder in the chain
- (BOOL)acceptsFirstResponder
{
  return NO;
}

#pragma mark -
#pragma mark Accessors

- (id)controlView
{
    return _controlView;
}

- (id<PSMTabBarControlProtocol>)psmTabControlView {
    return (id<PSMTabBarControlProtocol>)_controlView;
}

- (void)setControlView:(id)view
{
    // no retain release pattern, as this simply switches a tab to another view.
    _controlView = view;
}

- (NSTrackingRectTag)closeButtonTrackingTag
{
    return _closeButtonTrackingTag;
}

- (void)setCloseButtonTrackingTag:(NSTrackingRectTag)tag
{
    _closeButtonTrackingTag = tag;
}

- (NSTrackingRectTag)cellTrackingTag
{
    return _cellTrackingTag;
}

- (void)setCellTrackingTag:(NSTrackingRectTag)tag
{
    _cellTrackingTag = tag;
}

- (float)width
{
    return _frame.size.width;
}

- (NSRect)frame
{
    return _frame;
}

- (void)setFrame:(NSRect)rect
{
    _frame = rect;
}

- (void)setStringValue:(NSString *)aString
{
    [super setStringValue:aString];
    _stringSize = [[self attributedStringValue] size];
    // need to redisplay now - binding observation was too quick.
    [_controlView update:[[self controlView] automaticallyAnimates]];
}

- (NSSize)stringSize
{
    return _stringSize;
}

- (NSAttributedString *)attributedStringValue
{
    NSMutableAttributedString *aString = [[[NSMutableAttributedString alloc] initWithAttributedString:[(id <PSMTabStyle>)[(PSMTabBarControl *)_controlView style] attributedStringValueForTabCell:self]] autorelease];

    if (_labelColor) {
        [aString addAttribute:NSForegroundColorAttributeName value:_labelColor range:NSMakeRange(0, [aString length])];
    }

    return aString;
}

- (int)tabState
{
    return _tabState;
}

- (void)setTabState:(int)state
{
    _tabState = state;
}

- (NSProgressIndicator *)indicator
{
    return _indicator;
}

- (BOOL)isInOverflowMenu
{
    return _isInOverflowMenu;
}

- (void)setIsInOverflowMenu:(BOOL)value
{
    _isInOverflowMenu = value;
}

- (BOOL)closeButtonPressed
{
    return _closeButtonPressed;
}

- (void)setCloseButtonPressed:(BOOL)value
{
    _closeButtonPressed = value;
}

- (BOOL)closeButtonOver
{
    return _closeButtonOver;
}

- (void)setCloseButtonOver:(BOOL)value
{
    _closeButtonOver = value;
}

- (BOOL)hasCloseButton
{
    return _hasCloseButton;
}

- (void)setHasCloseButton:(BOOL)set;
{
    _hasCloseButton = set;
}

- (void)setCloseButtonSuppressed:(BOOL)suppress;
{
    _isCloseButtonSuppressed = suppress;
}

- (BOOL)isCloseButtonSuppressed;
{
    return _isCloseButtonSuppressed;
}

- (BOOL)hasIcon
{
    return _hasIcon;
}

- (void)setHasIcon:(BOOL)value
{
    _hasIcon = value;
    [_controlView update:[[self controlView] automaticallyAnimates]]; // binding notice is too fast
}

- (int)count
{
    return _count;
}

- (void)setCount:(int)value
{
    _count = value;
    [_controlView update:[[self controlView] automaticallyAnimates]]; // binding notice is too fast
}

- (BOOL)isPlaceholder
{
    return _isPlaceholder;
}

- (void)setIsPlaceholder:(BOOL)value;
{
    _isPlaceholder = value;
}

- (int)currentStep
{
    return _currentStep;
}

- (void)setCurrentStep:(int)value
{
    if(value < 0)
        value = 0;

    if(value > (kPSMTabDragAnimationSteps - 1))
        value = (kPSMTabDragAnimationSteps - 1);

    _currentStep = value;
}

- (NSString*)modifierString
{
    return _modifierString;
}

- (void)setModifierString:(NSString*)value
{
    [_modifierString autorelease];
    _modifierString = [value copy];
}

#pragma mark -
#pragma mark Bindings

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    // the progress indicator, label, icon, or count has changed - redraw the control view
    [_controlView update:[[self controlView] automaticallyAnimates]];
}

#pragma mark -
#pragma mark Component Attributes

- (NSRect)indicatorRectForFrame:(NSRect)cellFrame
{
    return [(id <PSMTabStyle>)[(PSMTabBarControl *)_controlView style] indicatorRectForTabCell:self];
}

- (NSRect)closeButtonRectForFrame:(NSRect)cellFrame
{
    return [(id <PSMTabStyle>)[(PSMTabBarControl *)_controlView style] closeButtonRectForTabCell:self];
}

- (float)minimumWidthOfCell
{
    return [(id <PSMTabStyle>)[(PSMTabBarControl *)_controlView style] minimumWidthOfTabCell:self];
}

- (float)desiredWidthOfCell
{
    return [(id <PSMTabStyle>)[(PSMTabBarControl *)_controlView style] desiredWidthOfTabCell:self];
}

#pragma mark -
#pragma mark Drawing

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    if(_isPlaceholder){
        [[NSColor colorWithCalibratedWhite:0.0 alpha:0.2] set];
        NSRectFillUsingOperation(cellFrame, NSCompositeSourceAtop);
        return;
    }

    [(id <PSMTabStyle>)[(PSMTabBarControl *)_controlView style] drawTabCell:self];
}

#pragma mark -
#pragma mark Tracking

- (void)mouseEntered:(NSEvent *)theEvent
{
    // check for which tag
    if ([theEvent trackingNumber] == _closeButtonTrackingTag) {
        _closeButtonOver = YES;
    }
    if ([theEvent trackingNumber] == _cellTrackingTag) {
        [self setHighlighted:YES];
        [_controlView setNeedsDisplay:NO];
    }

    //tell the control we only need to redraw the affected tab
    [_controlView setNeedsDisplayInRect:NSInsetRect([self frame], -2, -2)];
}

- (void)mouseExited:(NSEvent *)theEvent
{
    // check for which tag
    if ([theEvent trackingNumber] == _closeButtonTrackingTag) {
        _closeButtonOver = NO;
    }

    if ([theEvent trackingNumber] == _cellTrackingTag) {
        [self setHighlighted:NO];
        [_controlView setNeedsDisplay:NO];
    }

    //tell the control we only need to redraw the affected tab
    [_controlView setNeedsDisplayInRect:NSInsetRect([self frame], -2, -2)];
}

#pragma mark -
#pragma mark Drag Support

- (NSImage *)dragImage
{
    NSRect cellFrame = [(id <PSMTabStyle>)[(PSMTabBarControl *)_controlView style] dragRectForTabCell:self orientation:[(PSMTabBarControl *)_controlView orientation]];

    [_controlView lockFocus];
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithFocusedViewRect:cellFrame] autorelease];
    [_controlView unlockFocus];
    NSImage *image = [[[NSImage alloc] initWithSize:[rep size]] autorelease];
    [image addRepresentation:rep];
    NSImage *returnImage = [[[NSImage alloc] initWithSize:[rep size]] autorelease];
    [returnImage lockFocus];
    [image compositeToPoint:NSMakePoint(0.0, 0.0) operation:NSCompositeSourceOver fraction:1.0];
    [returnImage unlockFocus];
    if(![[self indicator] isHidden]){
        NSImage *piImage = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:@"pi"]];
        [returnImage lockFocus];
        NSPoint indicatorPoint = NSMakePoint([self frame].size.width - MARGIN_X - kPSMTabBarIndicatorWidth, MARGIN_Y);
        [piImage compositeToPoint:indicatorPoint operation:NSCompositeSourceOver fraction:1.0];
        [returnImage unlockFocus];
        [piImage release];
    }
    return returnImage;
}

#pragma mark -
#pragma mark Archiving

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [super encodeWithCoder:aCoder];
    if ([aCoder allowsKeyedCoding]) {
        [aCoder encodeRect:_frame forKey:@"frame"];
        [aCoder encodeSize:_stringSize forKey:@"stringSize"];
        [aCoder encodeInt:_currentStep forKey:@"currentStep"];
        [aCoder encodeBool:_isPlaceholder forKey:@"isPlaceholder"];
        [aCoder encodeInt:_tabState forKey:@"tabState"];
        [aCoder encodeInt:_closeButtonTrackingTag forKey:@"closeButtonTrackingTag"];
        [aCoder encodeInt:_cellTrackingTag forKey:@"cellTrackingTag"];
        [aCoder encodeBool:_closeButtonOver forKey:@"closeButtonOver"];
        [aCoder encodeBool:_closeButtonPressed forKey:@"closeButtonPressed"];
        [aCoder encodeObject:_indicator forKey:@"indicator"];
        [aCoder encodeBool:_isInOverflowMenu forKey:@"isInOverflowMenu"];
        [aCoder encodeBool:_hasCloseButton forKey:@"hasCloseButton"];
        [aCoder encodeBool:_isCloseButtonSuppressed forKey:@"isCloseButtonSuppressed"];
        [aCoder encodeBool:_hasIcon forKey:@"hasIcon"];
        [aCoder encodeInt:_count forKey:@"count"];
    }
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        if ([aDecoder allowsKeyedCoding]) {
            _frame = [aDecoder decodeRectForKey:@"frame"];
            NSLog(@"decoding cell");
            _stringSize = [aDecoder decodeSizeForKey:@"stringSize"];
            _currentStep = [aDecoder decodeIntForKey:@"currentStep"];
            _isPlaceholder = [aDecoder decodeBoolForKey:@"isPlaceholder"];
            _tabState = [aDecoder decodeIntForKey:@"tabState"];
            _closeButtonTrackingTag = [aDecoder decodeIntForKey:@"closeButtonTrackingTag"];
            _cellTrackingTag = [aDecoder decodeIntForKey:@"cellTrackingTag"];
            _closeButtonOver = [aDecoder decodeBoolForKey:@"closeButtonOver"];
            _closeButtonPressed = [aDecoder decodeBoolForKey:@"closeButtonPressed"];
            _indicator = [[aDecoder decodeObjectForKey:@"indicator"] retain];
            _isInOverflowMenu = [aDecoder decodeBoolForKey:@"isInOverflowMenu"];
            _hasCloseButton = [aDecoder decodeBoolForKey:@"hasCloseButton"];
            _isCloseButtonSuppressed = [aDecoder decodeBoolForKey:@"isCloseButtonSuppressed"];
            _hasIcon = [aDecoder decodeBoolForKey:@"hasIcon"];
            _count = [aDecoder decodeIntForKey:@"count"];
        }
    }
    return self;
}

#pragma mark -
#pragma mark Accessibility

-(BOOL)accessibilityIsIgnored {
    return NO;
}

- (NSArray*)accessibilityAttributeNames
{
    static NSArray *attributes = nil;
    if (!attributes) {
        NSSet *set = [NSSet setWithArray:[super accessibilityAttributeNames]];
        set = [set setByAddingObjectsFromArray:[NSArray arrayWithObjects:
                                                   NSAccessibilityTitleAttribute,
                                                   NSAccessibilityValueAttribute,
                                                   nil]];
        attributes = [[set allObjects] retain];
    }
    return attributes;
}


- (id)accessibilityAttributeValue:(NSString *)attribute {
    id attributeValue = nil;

    if ([attribute isEqualToString: NSAccessibilityRoleAttribute]) {
        attributeValue = NSAccessibilityRadioButtonRole;
    } else if ([attribute isEqualToString: NSAccessibilityHelpAttribute]) {
        if ([[[self controlView] delegate] respondsToSelector:@selector(accessibilityStringForTabView:objectCount:)]) {
            attributeValue = [NSString stringWithFormat:@"%@, %i %@", [self stringValue],
                                                                        [self count],
                                                                        [[[self controlView] delegate] accessibilityStringForTabView:[[self controlView] tabView] objectCount:[self count]]];
        } else {
            attributeValue = [self stringValue];
        }
    } else if ([attribute isEqualToString:NSAccessibilityPositionAttribute] || [attribute isEqualToString:NSAccessibilitySizeAttribute]) {
        NSRect rect = [self frame];
        rect = [[self controlView] convertRect:rect toView:nil];
        rect = [[self controlView] convertRectToScreen:rect];
        if ([attribute isEqualToString:NSAccessibilityPositionAttribute]) {
            attributeValue = [NSValue valueWithPoint:rect.origin];
        } else {
            attributeValue = [NSValue valueWithSize:rect.size];
        }
    } else if ([attribute isEqualToString:NSAccessibilityTitleAttribute]) {
        attributeValue = [self stringValue];
    } else if ([attribute isEqualToString: NSAccessibilityValueAttribute]) {
        attributeValue = [NSNumber numberWithBool:([self tabState] == 2)];
    } else {
        attributeValue = [super accessibilityAttributeValue:attribute];
    }

    return attributeValue;
}

- (NSArray *)accessibilityActionNames
{
    static NSArray *actions;

    if (!actions) {
        actions = [[NSArray alloc] initWithObjects:NSAccessibilityPressAction, nil];
    }
    return actions;
}

- (NSString *)accessibilityActionDescription:(NSString *)action
{
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_4
    return NSAccessibilityActionDescription(action);
#else
    return nil;
#endif
}

- (void)accessibilityPerformAction:(NSString *)action {
    if ([action isEqualToString:NSAccessibilityPressAction]) {
        // this tab was selected
        [[self psmTabControlView] performSelector:@selector(tabClick:)
                                       withObject:self];
    }
}

- (id)accessibilityHitTest:(NSPoint)point {
    return NSAccessibilityUnignoredAncestor(self);
}

- (id)accessibilityFocusedUIElement:(NSPoint)point {
    return NSAccessibilityUnignoredAncestor(self);
}

#pragma mark -
#pragma mark iTerm Add-on

- (NSColor *)labelColor
{
    return _labelColor;
}

- (void)setLabelColor:(NSColor *)aColor
{
    if (_labelColor != aColor) {
        if (_labelColor) {
            [_labelColor release];
        }
        _labelColor = aColor ? [aColor retain] : nil;
    }
}

- (NSColor*)tabColor
{
    return _tabColor;
}

- (void)setTabColor:(NSColor *)aColor
{
    if (_tabColor != aColor) {
        if (_tabColor) {
            [_tabColor release];
        }
        _tabColor = aColor ? [aColor retain] : nil;
    }
}

@end
