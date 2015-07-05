//
//  iTermRootTerminalView.m
//  iTerm2
//
//  Created by George Nachman on 7/3/15.
//
//

#import "iTermRootTerminalView.h"

#import "DebugLogging.h"
#import "iTermPreferences.h"
#import "iTermTabBarControlView.h"
#import "PTYTabView.h"
#import "ToolbeltView.h"

const CGFloat kHorizontalTabBarHeight = 22;
static const CGFloat kDefaultToolbeltWidth = 250;
static const CGFloat kMinimumToolbeltSizeInPoints = 100;
static const CGFloat kMinimumToolbeltSizeAsFractionOfWindow = 0.05;
static const CGFloat kMaximumToolbeltSizeAsFractionOfWindow = 0.5;

@interface iTermRootTerminalView()

@property(nonatomic, retain) PTYTabView *tabView;
@property(nonatomic, retain) iTermTabBarControlView *tabBarControl;
@property(nonatomic, retain) NSView *divisionView;
@property(nonatomic, retain) ToolbeltView *toolbelt;

@end


@implementation iTermRootTerminalView


- (instancetype)initWithFrame:(NSRect)frameRect
                        color:(NSColor *)color
               tabBarDelegate:(id<iTermTabBarControlViewDelegate,PSMTabBarControlDelegate>)tabBarDelegate
                     delegate:(id<iTermRootTerminalViewDelegate, iTermToolbeltViewDelegate>)delegate {
    self = [super initWithFrame:frameRect color:color];
    if (self) {
        _delegate = delegate;

        self.autoresizesSubviews = YES;

        // Create the tab view.
        self.tabView = [[[PTYTabView alloc] initWithFrame:self.bounds] autorelease];
        _tabView.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
        _tabView.autoresizesSubviews = YES;
        _tabView.allowsTruncatedLabels = NO;
        _tabView.controlSize = NSSmallControlSize;
        _tabView.tabViewType = NSNoTabsNoBorder;
        [self addSubview:_tabView];

        // Create the tab bar.
        NSRect tabBarFrame = self.bounds;
        tabBarFrame.size.height = kHorizontalTabBarHeight;
        self.tabBarControl = [[[iTermTabBarControlView alloc] initWithFrame:tabBarFrame] autorelease];
        _tabBarControl.itermTabBarDelegate = tabBarDelegate;

        int theModifier =
            [iTermPreferences maskForModifierTag:[iTermPreferences intForKey:kPreferenceKeySwitchTabModifier]];
        [_tabBarControl setModifier:theModifier];
        switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
            case PSMTab_BottomTab:
                _tabBarControl.orientation = PSMTabBarHorizontalOrientation;
                [_tabBarControl setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
                break;

            case PSMTab_TopTab:
                _tabBarControl.orientation = PSMTabBarHorizontalOrientation;
                [_tabBarControl setAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];
                break;

            case PSMTab_LeftTab:
                _tabBarControl.orientation = PSMTabBarVerticalOrientation;
                _tabBarControl.autoresizingMask = (NSViewHeightSizable | NSViewMaxXMargin);
                break;
        }
        [self addSubview:_tabBarControl];
        _tabBarControl.tabView = _tabView;
        [_tabView setDelegate:_tabBarControl];
        _tabBarControl.delegate = tabBarDelegate;
        _tabBarControl.hideForSingleTab = NO;

        // Create the toolbelt
        // A decent default value.
        _toolbeltWidth = kDefaultToolbeltWidth;
        [self constrainToolbeltWidth];

        self.toolbelt = [[[ToolbeltView alloc] initWithFrame:self.toolbeltFrame
                                                    delegate:(id)_delegate] autorelease];
        _toolbelt.autoresizingMask = (NSViewMinXMargin | NSViewHeightSizable);
        [self addSubview:_toolbelt];
        [self updateToolbelt];
    }
    return self;
}

- (void)dealloc {
    [_tabView release];

    _tabBarControl.itermTabBarDelegate = nil;
    _tabBarControl.delegate = nil;
    [_tabBarControl release];

    [_divisionView release];
    [_toolbelt release];

    [super dealloc];
}

#pragma mark - Division View

- (void)updateDivisionViewVisible:(BOOL)shouldBeVisible {
    if (shouldBeVisible) {
        // A division is needed, but there might already be one.
        NSRect reducedTabviewFrame = _tabView.frame;
        if (!_divisionView) {
            reducedTabviewFrame.size.height -= 1;
        }
        NSRect divisionViewFrame = NSMakeRect(reducedTabviewFrame.origin.x,
                                              reducedTabviewFrame.size.height + reducedTabviewFrame.origin.y,
                                              reducedTabviewFrame.size.width,
                                              1);
        if (_divisionView) {
            // Simply update divisionView's frame.
            _divisionView.frame = divisionViewFrame;
        } else {
            // Shrink the tabview and add a division view.
            _tabView.frame = reducedTabviewFrame;
            _divisionView = [[SolidColorView alloc] initWithFrame:divisionViewFrame
                                                            color:[NSColor darkGrayColor]];
            _divisionView.autoresizingMask = (NSViewWidthSizable | NSViewMinYMargin);
            [self addSubview:_divisionView];
        }
    } else if (_divisionView) {
        // Remove existing division
        NSRect augmentedTabviewFrame = _tabView.frame;
        augmentedTabviewFrame.size.height += 1;
        [_divisionView removeFromSuperview];
        [_divisionView release];
        _divisionView = nil;
        _tabView.frame = augmentedTabviewFrame;
    }
}

#pragma mark - Toolbelt

- (void)updateToolbelt {
    _toolbelt.frame = [self toolbeltFrame];
    _toolbelt.hidden = ![self shouldShowToolbelt];
    [_delegate repositionWidgets];
    [_toolbelt relayoutAllTools];
}

- (void)constrainToolbeltWidth {
    CGFloat minSize = MIN(kMinimumToolbeltSizeInPoints,
                          self.frame.size.width * kMinimumToolbeltSizeAsFractionOfWindow);
    _toolbeltWidth = MAX(MIN(_toolbeltWidth,
                             self.frame.size.width * kMaximumToolbeltSizeAsFractionOfWindow),
                         minSize);
}

- (NSRect)toolbeltFrame {
    CGFloat width = floor(_toolbeltWidth);
    CGFloat top = [_delegate _haveTopBorder] ? 1 : 0;
    CGFloat bottom = [_delegate _haveBottomBorder] ? 1 : 0;
    CGFloat right = [_delegate _haveRightBorder] ? 1 : 0;
    NSRect toolbeltFrame = NSMakeRect(self.bounds.size.width - width - right,
                                      bottom,
                                      width,
                                      self.bounds.size.height - top - bottom);
    return toolbeltFrame;
}

- (void)setShouldShowToolbelt:(BOOL)shouldShowToolbelt {
    if (shouldShowToolbelt == _shouldShowToolbelt) {
        return;
    }

    _shouldShowToolbelt = shouldShowToolbelt;
    _toolbelt.hidden = !shouldShowToolbelt;
    if (shouldShowToolbelt) {
        [self constrainToolbeltWidth];
    }
}

- (void)updateToolbeltFrame {
    DLog(@"Set toolbelt frame to %@", NSStringFromRect([self toolbeltFrame]));
    [self constrainToolbeltWidth];
    [self.toolbelt setFrame:self.toolbeltFrame];
}

- (void)shutdown {
    [_toolbelt shutdown];
    [_toolbelt release];
    _toolbelt = nil;
}

@end
