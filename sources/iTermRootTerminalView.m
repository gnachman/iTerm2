//
//  iTermRootTerminalView.m
//  iTerm2
//
//  Created by George Nachman on 7/3/15.
//
//

#import "iTermRootTerminalView.h"
#import "iTermPreferences.h"
#import "iTermTabBarControlView.h"
#import "PTYTabView.h"

const CGFloat kHorizontalTabBarHeight = 22;

@interface iTermRootTerminalView()

@property(nonatomic, retain) PTYTabView *tabView;
@property(nonatomic, retain) iTermTabBarControlView *tabBarControl;

@end


@implementation iTermRootTerminalView

- (instancetype)initWithFrame:(NSRect)frameRect
                        color:(NSColor *)color
               tabBarDelegate:(id<iTermTabBarControlViewDelegate, PSMTabBarControlDelegate>)tabBarDelegate {
    self = [super initWithFrame:frameRect color:color];
    if (self) {
        // Create the tab view.
        self.tabView = [[[PTYTabView alloc] initWithFrame:self.bounds] autorelease];
        _tabView.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
        _tabView.autoresizesSubviews = YES;
        _tabView.allowsTruncatedLabels = NO;
        _tabView.controlSize = NSSmallControlSize;
        _tabView.tabViewType = NSNoTabsNoBorder;
        [self addSubview:_tabView];

        // Create the tab bar.
        NSRect tabBarFrame = [[[self window] contentView] bounds];
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
    }
    return self;
}

- (void)dealloc {
    [_tabView release];

    _tabBarControl.itermTabBarDelegate = nil;
    _tabBarControl.delegate = nil;
    [_tabBarControl release];
    
    [super dealloc];
}

@end
