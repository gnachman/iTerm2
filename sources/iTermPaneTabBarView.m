//
//  iTermPaneTabBarView.m
//  iTerm2
//
//  Lightweight tab bar for displaying multiple sessions within a single split pane.
//

#import "iTermPaneTabBarView.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermPreferences.h"
#import "NSAppearance+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSImage+iTerm.h"
#import "PTYWindow.h"

static const CGFloat kPaneTabMinWidth = 40;
static const CGFloat kPaneTabMaxWidth = 150;
static const CGFloat kPaneTabPadding = 6;
static const CGFloat kPaneTabSpacing = 1;
static const CGFloat kPaneTabCloseButtonSize = 10;
static const CGFloat kPaneTabCloseButtonMargin = 3;
static const CGFloat kPaneTabVerticalPadding = 2;

@interface iTermPaneTabButton : NSView
@property (nonatomic, copy) NSString *title;
@property (nonatomic) BOOL selected;
@property (nonatomic) BOOL hasActivity;
@property (nonatomic) NSUInteger tabIndex;
@property (nonatomic, weak) iTermPaneTabBarView *owner;
@property (nonatomic) BOOL mouseInside;
@end

@implementation iTermPaneTabButton {
    NSTrackingArea *_trackingArea;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self updateTrackingArea];
    }
    return self;
}

- (void)updateTrackingArea {
    if (_trackingArea) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                options:(NSTrackingMouseEnteredAndExited |
                                                         NSTrackingActiveInActiveApp)
                                                  owner:self
                                               userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    [self updateTrackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
    _mouseInside = YES;
    [self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent *)event {
    _mouseInside = NO;
    [self setNeedsDisplay:YES];
}

- (BOOL)acceptsFirstResponder {
    return NO;
}

- (void)mouseUp:(NSEvent *)event {
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];

    // Check if click is on close button
    if (_mouseInside && [self closeButtonRectForBounds:self.bounds].size.width > 0) {
        NSRect closeRect = [self closeButtonRectForBounds:self.bounds];
        if (NSPointInRect(point, closeRect)) {
            [_owner.delegate paneTabBarView:_owner didCloseTabAtIndex:_tabIndex];
            return;
        }
    }

    [_owner.delegate paneTabBarView:_owner didSelectTabAtIndex:_tabIndex];
}

- (NSRect)closeButtonRectForBounds:(NSRect)bounds {
    if (!_mouseInside && !_selected) {
        return NSZeroRect;
    }
    CGFloat y = (bounds.size.height - kPaneTabCloseButtonSize) / 2;
    return NSMakeRect(kPaneTabCloseButtonMargin,
                      y,
                      kPaneTabCloseButtonSize,
                      kPaneTabCloseButtonSize);
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = self.bounds;

    // Draw background
    if (_selected) {
        NSColor *bgColor;
        if (self.window.ptyWindow.it_terminalWindowUseMinimalStyle) {
            bgColor = [[NSColor controlAccentColor] colorWithAlphaComponent:0.3];
        } else {
            bgColor = [NSColor.controlAccentColor colorWithAlphaComponent:0.2];
        }
        [bgColor set];
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 1, kPaneTabVerticalPadding)
                                                             xRadius:3
                                                             yRadius:3];
        [path fill];
    } else if (_mouseInside) {
        NSColor *hoverColor = [[NSColor labelColor] colorWithAlphaComponent:0.08];
        [hoverColor set];
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 1, kPaneTabVerticalPadding)
                                                             xRadius:3
                                                             yRadius:3];
        [path fill];
    }

    // Draw activity indicator dot
    if (_hasActivity && !_selected) {
        NSColor *dotColor = [NSColor controlAccentColor];
        [dotColor set];
        CGFloat dotSize = 4;
        NSRect dotRect = NSMakeRect(kPaneTabPadding,
                                    (bounds.size.height - dotSize) / 2,
                                    dotSize,
                                    dotSize);
        [[NSBezierPath bezierPathWithOvalInRect:dotRect] fill];
    }

    // Draw title
    NSFont *font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    NSColor *textColor;
    if (self.window.ptyWindow.it_terminalWindowUseMinimalStyle) {
        textColor = [self.window.ptyWindow it_terminalWindowDecorationTextColorForBackgroundColor:nil];
    } else {
        textColor = _selected ? [NSColor labelColor] : [NSColor secondaryLabelColor];
    }

    NSDictionary *attrs = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: textColor
    };

    NSRect closeRect = [self closeButtonRectForBounds:bounds];
    CGFloat titleX;
    if (closeRect.size.width > 0) {
        titleX = NSMaxX(closeRect) + kPaneTabCloseButtonMargin;
    } else {
        titleX = kPaneTabPadding + (_hasActivity && !_selected ? 6 : 0);
    }
    CGFloat titleMaxWidth = bounds.size.width - titleX - kPaneTabPadding;

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    NSMutableDictionary *titleAttrs = [attrs mutableCopy];
    titleAttrs[NSParagraphStyleAttributeName] = style;

    NSSize titleSize = [_title sizeWithAttributes:attrs];
    CGFloat titleY = (bounds.size.height - titleSize.height) / 2;
    NSRect titleRect = NSMakeRect(titleX, titleY, titleMaxWidth, titleSize.height);
    [_title drawInRect:titleRect withAttributes:titleAttrs];

    // Draw close button on hover or when selected
    if (closeRect.size.width > 0) {
        NSColor *closeColor = [textColor colorWithAlphaComponent:_mouseInside ? 0.8 : 0.4];
        [closeColor set];

        CGFloat inset = 2;
        NSRect xRect = NSInsetRect(closeRect, inset, inset);
        NSBezierPath *xPath = [NSBezierPath bezierPath];
        [xPath moveToPoint:NSMakePoint(NSMinX(xRect), NSMinY(xRect))];
        [xPath lineToPoint:NSMakePoint(NSMaxX(xRect), NSMaxY(xRect))];
        [xPath moveToPoint:NSMakePoint(NSMaxX(xRect), NSMinY(xRect))];
        [xPath lineToPoint:NSMakePoint(NSMinX(xRect), NSMaxY(xRect))];
        [xPath setLineWidth:1.5];
        [xPath stroke];
    }
}

@end

#pragma mark - iTermPaneTabBarView

@implementation iTermPaneTabBarView {
    NSMutableArray<iTermPaneTabButton *> *_tabButtons;
    NSMutableIndexSet *_activityIndexes;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _tabButtons = [[NSMutableArray alloc] init];
        _activityIndexes = [[NSMutableIndexSet alloc] init];
    }
    return self;
}

- (BOOL)acceptsFirstResponder {
    return NO;
}

- (void)setTabTitles:(NSArray<NSString *> *)tabTitles {
    _tabTitles = [tabTitles copy];
    [self rebuildTabButtons];
    [self layoutTabButtons];
    [self setNeedsDisplay:YES];
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    _selectedIndex = selectedIndex;
    for (NSUInteger i = 0; i < _tabButtons.count; i++) {
        _tabButtons[i].selected = (i == selectedIndex);
    }
    [self setNeedsDisplay:YES];
}

- (void)setTabHasActivity:(BOOL)hasActivity atIndex:(NSUInteger)index {
    if (hasActivity) {
        [_activityIndexes addIndex:index];
    } else {
        [_activityIndexes removeIndex:index];
    }
    if (index < _tabButtons.count) {
        _tabButtons[index].hasActivity = hasActivity;
        [_tabButtons[index] setNeedsDisplay:YES];
    }
}

- (void)rebuildTabButtons {
    for (iTermPaneTabButton *button in _tabButtons) {
        [button removeFromSuperview];
    }
    [_tabButtons removeAllObjects];

    for (NSUInteger i = 0; i < _tabTitles.count; i++) {
        iTermPaneTabButton *button = [[iTermPaneTabButton alloc] initWithFrame:NSZeroRect];
        button.title = _tabTitles[i];
        button.tabIndex = i;
        button.owner = self;
        button.selected = (i == _selectedIndex);
        button.hasActivity = [_activityIndexes containsIndex:i];
        [self addSubview:button];
        [_tabButtons addObject:button];
    }
}

- (void)layoutTabButtons {
    NSRect bounds = self.bounds;
    CGFloat availableWidth = bounds.size.width;
    NSUInteger tabCount = _tabButtons.count;

    if (tabCount == 0) {
        return;
    }

    // Calculate tab width: divide available space evenly, clamped to min/max
    CGFloat tabWidth = availableWidth / tabCount;
    tabWidth = MAX(kPaneTabMinWidth, MIN(kPaneTabMaxWidth, tabWidth));

    // If tabs would overflow, shrink them
    CGFloat totalTabWidth = tabWidth * tabCount + kPaneTabSpacing * (tabCount - 1);
    if (totalTabWidth > availableWidth) {
        tabWidth = (availableWidth - kPaneTabSpacing * (tabCount - 1)) / tabCount;
        tabWidth = MAX(20, tabWidth); // absolute minimum
    }

    CGFloat x = 0;
    for (NSUInteger i = 0; i < tabCount; i++) {
        _tabButtons[i].frame = NSMakeRect(x,
                                          0,
                                          tabWidth,
                                          bounds.size.height);
        x += tabWidth + kPaneTabSpacing;
    }
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self layoutTabButtons];
}

- (void)updateTextColor {
    for (iTermPaneTabButton *button in _tabButtons) {
        [button setNeedsDisplay:YES];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    // The parent SessionTitleView handles background drawing.
    // We just draw our tab buttons (handled by subviews).
}

@end
