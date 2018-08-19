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

@interface PSMTabBarCell()<PSMProgressIndicatorDelegate>
- (NSView<PSMTabBarControlProtocol> *)psmTabControlView;
@end

static NSRect PSMConvertAccessibilityFrameToScreen(NSView *view, NSRect frame) {
    if (!NSIsEmptyRect(frame)) {
        NSWindow *window = view.window;
        if (window) {
            return [window convertRectToScreen:[view convertRect:frame toView:nil]];
        }
    }
    return NSZeroRect;
}

@interface PSMTabAccessibilityElementPrototype : NSAccessibilityElement
@property(nonatomic, assign) PSMTabBarCell *cell;
- (instancetype)initWithCell:(PSMTabBarCell *)cell role:(NSString *)role;
@end

@implementation PSMTabAccessibilityElementPrototype

- (instancetype)initWithCell:(PSMTabBarCell *)cell role:(NSString *)role {
    self = [super init];
    if (self) {
        self.accessibilityRole = role;
        self.cell = cell;
    }
    return self;
}

- (id)accessibilityHitTest:(NSPoint)point {
        for (id child in self.accessibilityChildren) {
        if (NSPointInRect(point, [child accessibilityFrame])) {
                return [child accessibilityHitTest:point];
        }
    }
    return self;
}

@end

@interface PSMTabAccessibilityElement : PSMTabAccessibilityElementPrototype<NSAccessibilityRadioButton>
@end

@implementation PSMTabAccessibilityElement

- (id)accessibilityParent {
    return self.cell.psmTabControlView;
}

- (id)accessibilityValue {
    return @(([self.cell tabState] & PSMTab_SelectedMask) == PSMTab_SelectedMask);
}

- (NSString *)accessibilityLabel {
    NSString *label = [self.cell stringValue];
    if ([label length] > 0) {
        return label;
    }
    return @"(Untitled Tab)";   // not localized as of now
}

- (NSRect)accessibilityFrame {
    PSMTabBarCell *cell = self.cell;
    return PSMConvertAccessibilityFrameToScreen(cell.psmTabControlView, cell.frame);
}

- (BOOL)accessibilityPerformPress {
    PSMTabBarCell *cell = self.cell;
    [cell.psmTabControlView tabClick:cell];
    return YES; // we don't actually know if -tabClick: succeeded, but for now, let's pretend it did
}

@end

@interface PSMTabCloseButtonAccessibilityElement : PSMTabAccessibilityElementPrototype<NSAccessibilityButton>
@end

@implementation PSMTabCloseButtonAccessibilityElement

- (id)accessibilityParent {
    return self.cell.element;
}

- (NSString *)accessibilityLabel {
    return @"Close Tab";        // not localized as of now
}

- (NSRect)accessibilityFrame {
    PSMTabBarCell *cell = self.cell;
    NSView<PSMTabBarControlProtocol> *controlView = cell.psmTabControlView;
    return PSMConvertAccessibilityFrameToScreen(controlView, [[controlView style] closeButtonRectForTabCell:cell]);
}

- (BOOL)accessibilityPerformPress {
        PSMTabBarCell *cell = self.cell;
    [cell.psmTabControlView closeTabClick:cell];
    return YES; // we don't actually know if -closeTabClick: succeeded, but for now, let's pretend it did
}

@end


// A timer that does not keep a strong reference to its target. The target
// should invoke -invalidate from its -dealloc method and release the timer to
// avoid getting called posthumously.
@interface PSMWeakTimer : NSObject
@property(nonatomic, assign) id target;
@property(nonatomic, assign) SEL selector;

- (instancetype)initWithTimeInterval:(NSTimeInterval)timeInterval
                              target:(id)target
                            selector:(SEL)selector
                             repeats:(BOOL)repeats;
- (void)invalidate;

@end

@implementation PSMWeakTimer {
    NSTimer *_timer;
    BOOL _repeats;
}

- (instancetype)initWithTimeInterval:(NSTimeInterval)timeInterval
                              target:(id)target
                            selector:(SEL)selector
                             repeats:(BOOL)repeats {
    self = [super init];
    if (self) {
        _target = target;
        _selector = selector;
        _repeats = repeats;
        _timer = [NSTimer scheduledTimerWithTimeInterval:timeInterval
                                                  target:self
                                                selector:@selector(timerDidFire:)
                                                userInfo:nil
                                                 repeats:repeats];
    }
    return self;
}

- (void)invalidate {
    [_timer invalidate];
    _timer = nil;
}

- (void)timerDidFire:(NSTimer *)timer {
    [_target performSelector:_selector withObject:timer];
    if (!_repeats) {
        _timer = nil;
    }
}

@end

@implementation PSMTabBarCell  {
    NSSize _stringSize;
    PSMProgressIndicator *_indicator;
    NSTimeInterval _highlightChangeTime;
    PSMWeakTimer *_delayedStringValueTimer;  // For bug 3957
    BOOL _hasIcon;
    BOOL _highlighted;
    NSAccessibilityElement *_element;
}

#pragma mark - Creation/Destruction

- (id)initWithControlView:(PSMTabBarControl *)controlView {
    self = [super init];
    if (self) {
        [self setControlView:controlView];
        _indicator = [[PSMProgressIndicator alloc] initWithFrame:NSMakeRect(0,
                                                                            0,
                                                                            kPSMTabBarIndicatorWidth,
                                                                            kPSMTabBarIndicatorWidth)];
        _indicator.delegate = self;
        [_indicator setAutoresizingMask:NSViewMinYMargin];
        _indicator.light = controlView.style.useLightControls;
        _hasCloseButton = YES;
        _modifierString = [@"" copy];
        _truncationStyle = NSLineBreakByTruncatingTail;
        [self setUpAccessibilityElement];
    }
    return self;
}

- (id)initPlaceholderWithFrame:(NSRect)frame
                      expanded:(BOOL)value
                 inControlView:(PSMTabBarControl *)controlView {
    self = [super init];
    if (self) {
        [self setControlView:controlView];
        _isPlaceholder = YES;
        if (!value) {
            if ([controlView orientation] == PSMTabBarHorizontalOrientation) {
                frame.size.width = 0;
            } else {
                frame.size.height = 0;
            }
        }
        [self setFrame:frame];
        _closeButtonTrackingTag = 0;
        _cellTrackingTag = 0;
        _closeButtonOver = NO;
        _closeButtonPressed = NO;
        _indicator = nil;
        _hasCloseButton = YES;
        _count = 0;
        _tabColor = nil;
        _modifierString = [@"" copy];
        _truncationStyle = NSLineBreakByTruncatingTail;
        if (value) {
            [self setCurrentStep:(kPSMTabDragAnimationSteps - 1)];
        } else {
            [self setCurrentStep:0];
        }
        [self setUpAccessibilityElement];
    }
    return self;
}

- (void)dealloc {
    [_delayedStringValueTimer invalidate];
    [_delayedStringValueTimer release];

    [_modifierString release];
    _indicator.delegate = nil;
    [_indicator release];
    [_tabColor release];
    [_element release];
    [super dealloc];
}

- (NSString *)description {
    id identifier = nil;
    if ([self.representedObject respondsToSelector:@selector(identifier)]) {
        identifier = [self.representedObject identifier];
    }
    return [NSString stringWithFormat:@"<%@: %p representedObject=%@ identifier=%@ objectCount=%@>",
            NSStringFromClass([self class]),
            self,
            self.representedObject,
            identifier,
            @(self.count)];
}

// we don't want this to be the first responder in the chain
- (BOOL)acceptsFirstResponder {
  return NO;
}

#pragma mark - Accessors

- (BOOL)closeButtonVisible {
    return !_isCloseButtonSuppressed || [self highlightAmount] > 0;
}

- (NSView<PSMTabBarControlProtocol> *)psmTabControlView {
    return (NSView<PSMTabBarControlProtocol> *)[self controlView];
}

- (float)width {
    return _frame.size.width;
}

- (void)setStringValue:(NSString *)aString {
    [super setStringValue:aString];
    
    if (!_delayedStringValueTimer) {
        static const NSTimeInterval kStringValueSettingDelay = 0.1;
        _delayedStringValueTimer =
                [[PSMWeakTimer alloc] initWithTimeInterval:kStringValueSettingDelay
                                                    target:self
                                                  selector:@selector(updateStringValue:)
                                                   repeats:NO];
    }
}

- (void)updateStringValue:(NSTimer *)timer {
    [_delayedStringValueTimer release];
    _delayedStringValueTimer = nil;
    _stringSize = [[self attributedStringValue] size];
    // need to redisplay now - binding observation was too quick.
    [[self psmTabControlView] update:[[self psmTabControlView] automaticallyAnimates]];
}

- (NSSize)stringSize {
    return _stringSize;
}

- (NSAttributedString *)attributedStringValue {
    id<PSMTabBarControlProtocol> control = [self psmTabControlView];
    id <PSMTabStyle> tabStyle = [control style];
    return [tabStyle attributedStringValueForTabCell:self];
}

- (PSMProgressIndicator *)indicator {
    return _indicator;
}

- (void)setHasIcon:(BOOL)value {
    _hasIcon = value;
    [[self psmTabControlView] update:[[self psmTabControlView] automaticallyAnimates]]; // binding notice is too fast
}

- (BOOL)hasIcon {
    BOOL hasIndicator = [self indicator] && !self.indicator.isHidden;
    return _hasIcon && !hasIndicator;
}

- (void)setCount:(int)value {
    _count = value;
    [[self psmTabControlView] update:[[self psmTabControlView] automaticallyAnimates]]; // binding notice is too fast
}

- (void)setCurrentStep:(int)value {
    if (value < 0) {
        value = 0;
    }

    if (value > (kPSMTabDragAnimationSteps - 1)) {
        value = (kPSMTabDragAnimationSteps - 1);
    }

    _currentStep = value;
}

#pragma mark - Bindings

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    // the progress indicator, label, icon, or count has changed - redraw the control view
    [[self psmTabControlView] update:[[self psmTabControlView] automaticallyAnimates]];
}

#pragma mark - Component Attributes

- (NSRect)indicatorRectForFrame:(NSRect)cellFrame {
    return [[[self psmTabControlView] style] indicatorRectForTabCell:self];
}

- (NSRect)closeButtonRectForFrame:(NSRect)cellFrame {
    return [[[self psmTabControlView] style] closeButtonRectForTabCell:self];
}

- (float)minimumWidthOfCell {
    return [[[self psmTabControlView] style] minimumWidthOfTabCell:self];
}

- (float)desiredWidthOfCell {
    return [[[self psmTabControlView] style] desiredWidthOfTabCell:self];
}

#pragma mark - Drawing

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    if (_isPlaceholder){
        [[NSColor colorWithCalibratedWhite:0 alpha:0.2] set];
        NSRectFillUsingOperation(cellFrame, NSCompositingOperationSourceAtop);
        return;
    }

    [[[self psmTabControlView] style] drawTabCell:self highlightAmount:[self highlightAmount]];
}

- (void)drawPostHocDecorationsOnSelectedCell:(PSMTabBarCell *)cell
                               tabBarControl:(PSMTabBarControl *)bar {
    [[[self psmTabControlView] style] drawPostHocDecorationsOnSelectedCell:cell
                                                             tabBarControl:bar];
}

- (CGFloat)highlightAmount {
    NSTimeInterval timeSinceChange = [NSDate timeIntervalSinceReferenceDate] - _highlightChangeTime;
    CGFloat amount = self.highlighted ? 1 : 0;
    if (timeSinceChange < [self highlightAnimationDuration]) {
        CGFloat alpha = timeSinceChange / [self highlightAnimationDuration];
        return amount * alpha + (1 - amount) * (1 - alpha);
    } else {
        return amount;
    }
}

#pragma mark Tracking

- (void)mouseEntered:(NSEvent *)theEvent {
    // check for which tag
    if ([theEvent trackingNumber] == _closeButtonTrackingTag) {
        _closeButtonOver = YES;
    }
    if ([theEvent trackingNumber] == _cellTrackingTag) {
        [self setHighlighted:YES];
        [[self psmTabControlView] setNeedsDisplay:NO];
    }

    //tell the control we only need to redraw the affected tab
    [[self psmTabControlView] setNeedsDisplayInRect:NSInsetRect([self frame], -2, -2)];
}

- (void)mouseExited:(NSEvent *)theEvent {
    // check for which tag
    if ([theEvent trackingNumber] == _closeButtonTrackingTag) {
        _closeButtonOver = NO;
    }

    if ([theEvent trackingNumber] == _cellTrackingTag) {
        [self setHighlighted:NO];
        [[self psmTabControlView] setNeedsDisplay:NO];
    }

    //tell the control we only need to redraw the affected tab
    [[self psmTabControlView] setNeedsDisplayInRect:NSInsetRect([self frame], -2, -2)];
}

#pragma mark - Drag Support

- (NSImage *)dragImage {
    NSRect cellFrame =
        [[[self psmTabControlView] style] dragRectForTabCell:self
                                                 orientation:[[self psmTabControlView] orientation]];

    NSBitmapImageRep *rep;
    if (@available(macOS 10.14, *)) {
        rep = [self.psmTabControlView bitmapImageRepForCachingDisplayInRect:cellFrame];
        [self.psmTabControlView cacheDisplayInRect:cellFrame toBitmapImageRep:rep];
    } else {
        [[self psmTabControlView] lockFocus];
        rep = [[[NSBitmapImageRep alloc] initWithFocusedViewRect:cellFrame] autorelease];
        [[self psmTabControlView] unlockFocus];
    }
    NSImage *image = [[[NSImage alloc] initWithSize:[rep size]] autorelease];
    [image addRepresentation:rep];
    NSImage *returnImage = [[[NSImage alloc] initWithSize:[rep size]] autorelease];
    [returnImage lockFocus];
    [image drawAtPoint:NSZeroPoint
              fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver
              fraction:1.0];
    [returnImage unlockFocus];
    if (![[self indicator] isHidden]) {
        // TODO: This image is missing!
        NSImage *piImage = [[NSImage alloc] initByReferencingFile:[[PSMTabBarControl bundle] pathForImageResource:@"pi"]];
        [returnImage lockFocus];
        NSPoint indicatorPoint = self.indicator.frame.origin;
        [piImage drawAtPoint:indicatorPoint
                    fromRect:NSZeroRect
                   operation:NSCompositingOperationSourceOver
                    fraction:1.0];
        [returnImage unlockFocus];
        [piImage release];
    }
    return returnImage;
}

#pragma mark - NSCoding

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

#pragma mark - Accessibility

- (void)setUpAccessibilityElement {
    if (!_element) {
        _element = [[PSMTabAccessibilityElement alloc] initWithCell:self role:NSAccessibilityRadioButtonRole];
        if (_element) {
            PSMTabCloseButtonAccessibilityElement *closeButtonElement = [[PSMTabCloseButtonAccessibilityElement alloc] initWithCell:self role:NSAccessibilityButtonRole];
            if (closeButtonElement) {
                _element.accessibilityChildren = @[ closeButtonElement ];
                [closeButtonElement release];
            }
        }
    }
}

#pragma mark - iTerm2 Additions

- (void)updateForStyle {
    _indicator.light = [self psmTabControlView].style.useLightControls;
}

- (void)updateHighlight {
    if (self.isHighlighted) {
        NSPoint mouseLocationInScreenCoords = [NSEvent mouseLocation];
        NSRect rectInScreenCoords;
        rectInScreenCoords.origin = mouseLocationInScreenCoords;
        rectInScreenCoords.size = NSZeroSize;
        NSPoint mouseLocationInWindowCoords = [self.controlView.window convertRectFromScreen:rectInScreenCoords].origin;
        NSPoint mouseLocationInViewCoords = [self.controlView convertPoint:mouseLocationInWindowCoords
                                                                  fromView:nil];
        if (!NSPointInRect(mouseLocationInViewCoords, self.frame)) {
            self.highlighted = NO;
        }
    }
}

- (BOOL)isHighlighted {
    return _highlighted;
}

- (void)setHighlighted:(BOOL)highlighted {
    // Don't call -[super setHighlighted:] because it redraws the whole control.
    BOOL wasHighlighted = self.isHighlighted;
    _highlighted = highlighted;
    if (highlighted != wasHighlighted) {
        if ([self highlightAnimationDuration] > 0) {
            _highlightChangeTime = [NSDate timeIntervalSinceReferenceDate];
            [NSTimer scheduledTimerWithTimeInterval:1 / 60.0
                                             target:self
                                           selector:@selector(redrawHighlight:)
                                           userInfo:self.controlView
                                            repeats:YES];
        } else {
            [self.controlView setNeedsDisplayInRect:self.frame];
        }
    }
}

- (CGFloat)highlightAnimationDuration {
    if ([(PSMTabBarControl *)self.controlView orientation] == PSMTabBarHorizontalOrientation) {
        return 0.2;
    } else {
        return 0;
    }
}

- (void)redrawHighlight:(NSTimer *)timer {
    [self.controlView setNeedsDisplayInRect:self.frame];
    if ([NSDate timeIntervalSinceReferenceDate] - _highlightChangeTime > [self highlightAnimationDuration]) {
        [timer invalidate];
    }
}

#pragma mark - PSMProgressIndicatorDelegate

- (void)progressIndicatorNeedsUpdate {
    return [(PSMTabBarControl *)self.controlView progressIndicatorNeedsUpdate];
}

@end
