//
//  iTermSearchFieldCell.m
//  iTerm2SharedARC
//
//  Created by GEORGE NACHMAN on 7/4/18.
//

#import "iTermSearchFieldCell.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSObject+iTerm.h"

static NSSize kFocusRingInset = { 2, 3 };
const CGFloat kEdgeWidth = 3;

@implementation iTermMinimalSearchFieldCell
- (BOOL)shouldUseFocusedAppearanceWithControlView:(NSView *)controlView {
    return NO;
}
@end

@implementation iTermMiniSearchFieldCell
- (BOOL)shouldUseFocusedAppearanceWithControlView:(NSView *)controlView {
    return YES;
}
@end

@implementation iTermSearchFieldCell {
    CGFloat _alphaMultiplier;
    NSTimer *_timer;
    BOOL _needsAnimation;
}

- (instancetype)initTextCell:(NSString *)aString  {
    self = [super initTextCell:aString];
    if (self) {
        _alphaMultiplier = 1;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        _alphaMultiplier = 1;
    }
    return self;
}

- (void)setFraction:(CGFloat)fraction {
    if (fraction == 1.0 && _fraction < 1.0) {
        _needsAnimation = YES;
    } else if (fraction < 1.0) {
        _needsAnimation = NO;
    }
    _fraction = fraction;
    _alphaMultiplier = 1;
}

- (void)willAnimate {
    _alphaMultiplier -= 0.05;
    if (_alphaMultiplier <= 0) {
        _needsAnimation = NO;
        _alphaMultiplier = 0;
    }
}

- (void)drawFocusRingMaskWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    if (controlView.frame.origin.y >= 0) {
        [super drawFocusRingMaskWithFrame:NSInsetRect(cellFrame, kFocusRingInset.width, kFocusRingInset.height)
                                   inView:controlView];
    }
}

- (BOOL)shouldUseFocusedAppearanceWithControlView:(NSView *)controlView {
    return ([controlView respondsToSelector:@selector(currentEditor)] &&
            [(NSControl *)controlView currentEditor]);
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    NSRect originalFrame = cellFrame;
    const BOOL focused = [self shouldUseFocusedAppearanceWithControlView:controlView];
    [self.backgroundColor set];

    CGFloat xInset, yInset;
    if (focused) {
        xInset = 2.5;
        yInset = 1.5;
    } else {
        xInset = 0.5;
        yInset = 0.5;
    }
    cellFrame = NSInsetRect(cellFrame, xInset, yInset);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:cellFrame
                                                         xRadius:4
                                                         yRadius:4];
    [path fill];

    [self drawProgressBarInFrame:originalFrame path:path];

    if (!focused) {
        [[NSColor colorWithCalibratedWhite:0.5 alpha:1] set];
        [path setLineWidth:0.25];
        [path stroke];

        cellFrame = NSInsetRect(cellFrame, 0.25, 0.25);
        path = [NSBezierPath bezierPathWithRoundedRect:cellFrame
                                               xRadius:4
                                               yRadius:4];
        [path setLineWidth:0.25];
        [[NSColor colorWithCalibratedWhite:0.7 alpha:1] set];
        [path stroke];
    }

    NSString *indexAndCountString = self.indexAndCountString;
    if (indexAndCountString) {
        NSSize size = self.sizeOfIndexAndCount;
        NSRect textRect = [super searchTextRectForBounds:controlView.bounds];

        NSRect rect = NSMakeRect(NSMaxX(textRect) - size.width - self.marginForIndexAndCount,
                                 textRect.origin.y,
                                 size.width,
                                 textRect.size.height);
        [indexAndCountString drawInRect:rect withAttributes:self.attributesForIndexAndCount];
    }
    [self updateKeyboardClipViewIfNeeded];

    [self drawInteriorWithFrame:originalFrame inView:controlView];
}

// Work around a macOS bug that prevents updating the text rect while the search field has keyboard focus.
- (void)updateKeyboardClipViewIfNeeded {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSTextField *textField = [NSTextField castFrom:self.controlView];
        id cell = textField.cell;
        if ([cell isKindOfClass:[iTermSearchFieldCell class]]) {
            [cell reallyUpdateKeyboardClipView:textField];
        };
    });
}

- (void)reallyUpdateKeyboardClipView:(NSTextField *)textField {
    NSView *keyboardClipView = [self.controlView.subviews objectPassingTest:^BOOL(__kindof NSView *element, NSUInteger index, BOOL *stop) {
        return [NSStringFromClass([element class]) isEqualToString:@"_NSKeyboardFocusClipView"];
    }];
    if (!keyboardClipView) {
        return;
    }
    NSRect desiredFrame = [self searchTextRectForBounds:textField.bounds];
    NSRect frame = keyboardClipView.frame;
    BOOL shouldUpdate = NO;
    if (self.fraction == 1) {
        shouldUpdate = (frame.size.width != desiredFrame.size.width);
    } else {
        // Don't allow the frame to grow until the search is complete.
        shouldUpdate = (frame.size.width > desiredFrame.size.width);
    }
    if (shouldUpdate) {
        frame.size.width = desiredFrame.size.width;
        keyboardClipView.frame = frame;

        NSTextView *textView = [NSTextView castFrom:[textField.window fieldEditor:YES forObject:textField]];
        [textView scrollRangeToVisible:[[[textView selectedRanges] firstObject] rangeValue]];
        DLog(@"Update keyboard clip view's frame to %@", NSStringFromRect(frame));
    }
}

- (NSString *)indexAndCountString {
    NSTextField *textField = [NSTextField castFrom:self.controlView];
    if (textField.stringValue.length == 0) {
        // No query.
        return nil;
    }
    NSView *controlView = self.controlView;
    if (![controlView conformsToProtocol:@protocol(iTermSearchFieldControl)]) {
        return nil;
    }
    id<iTermSearchFieldControl> control = (id<iTermSearchFieldControl>)controlView;
    if (![control searchFieldControlHasCounts:self]) {
        return nil;
    }
    const iTermSearchFieldCounts counts = [control searchFieldControlGetCounts:self];
    if (counts.currentIndex == 0) {
        if (counts.numberOfResults == 0) {
            return nil;
        }
        return [NSString stringWithFormat:@"%@", @(counts.numberOfResults)];
    }
    return [NSString stringWithFormat:@"%@/%@", @(counts.currentIndex), @(counts.numberOfResults)];
}

- (NSRect)searchTextRectForBounds:(NSRect)rect {
    NSSize size = [self sizeOfIndexAndCount];
    NSRect result = [super searchTextRectForBounds:rect];
    result.size.width -= size.width + self.marginForIndexAndCount * 2;
    return result;
}

- (NSSize)sizeOfIndexAndCount {
    NSString *string = [self indexAndCountString];
    return [self sizeOfIndexAndCountForString:string];
}

- (NSSize)sizeOfIndexAndCountForString:(NSString *)string {
    NSDictionary *attributes = [self attributesForIndexAndCount];
    NSSize size = [string sizeWithAttributes:attributes];
    return size;
}

- (NSDictionary *)attributesForIndexAndCount {
    NSTextField *textField = [NSTextField castFrom:self.controlView];
    if (textField.attributedStringValue.length == 0) {
        return @{};
    }
    NSMutableDictionary *attributes = [[textField.attributedStringValue attributesAtIndex:0 effectiveRange:nil] mutableCopy];
    attributes[NSForegroundColorAttributeName] = [attributes[NSForegroundColorAttributeName] colorWithAlphaComponent:0.5];
    return attributes;
}

- (CGFloat)marginForIndexAndCount {
    return 4;
}

- (void)drawProgressBarInFrame:(NSRect)cellFrame path:(NSBezierPath *)fieldPath {
    if (self.fraction < 0.01) {
        return;
    }
    [[NSGraphicsContext currentContext] saveGraphicsState];
    [fieldPath addClip];

    const CGFloat maximumWidth = cellFrame.size.width - 1.0;
    NSRect blueRect = NSMakeRect(0, 0, maximumWidth * [self fraction] + kEdgeWidth, cellFrame.size.height);

    const CGFloat alpha = 0.3 * _alphaMultiplier;
    [[NSColor colorWithCalibratedRed:0.6
                               green:0.6
                               blue:1.0
                               alpha:alpha] set];
    NSRectFillUsingOperation(blueRect, NSCompositingOperationSourceOver);

    [[NSGraphicsContext currentContext] restoreGraphicsState];
}

@end
