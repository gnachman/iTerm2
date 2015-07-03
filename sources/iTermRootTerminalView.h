//
//  iTermRootTerminalView.h
//  iTerm2
//
//  Created by George Nachman on 7/3/15.
//
//

#import <Cocoa/Cocoa.h>
#import "SolidColorView.h"

extern const CGFloat kHorizontalTabBarHeight;

@class iTermTabBarControlView;
@protocol iTermTabBarControlViewDelegate;
@protocol PSMTabBarControlDelegate;
@class PTYTabView;

@interface iTermRootTerminalView : SolidColorView

- (instancetype)initWithFrame:(NSRect)frame
                        color:(NSColor *)color
               tabBarDelegate:(id<iTermTabBarControlViewDelegate, PSMTabBarControlDelegate>)tabBarDelegate;

// The tabview occupies almost the entire window. Each tab has an identifier
// which is a PTYTab.
@property(nonatomic, readonly) PTYTabView *tabView;

// This is a sometimes-visible control that shows the tabs and lets the user
// change which is visible.
@property(nonatomic, readonly) iTermTabBarControlView *tabBarControl;

@end
