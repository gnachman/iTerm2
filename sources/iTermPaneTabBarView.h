//
//  iTermPaneTabBarView.h
//  iTerm2
//
//  Lightweight tab bar for displaying multiple sessions within a single split pane.
//  Renders horizontally within the pane's title bar area.
//

#import <Cocoa/Cocoa.h>

@class iTermPaneTabBarView;

@protocol iTermPaneTabBarViewDelegate <NSObject>

- (void)paneTabBarView:(iTermPaneTabBarView *)view didSelectTabAtIndex:(NSUInteger)index;
- (void)paneTabBarView:(iTermPaneTabBarView *)view didCloseTabAtIndex:(NSUInteger)index;
- (void)paneTabBarViewDidRequestNewTab:(iTermPaneTabBarView *)view;

@end

@interface iTermPaneTabBarView : NSView

@property (nonatomic, copy) NSArray<NSString *> *tabTitles;
@property (nonatomic) NSUInteger selectedIndex;
@property (nonatomic, weak) id<iTermPaneTabBarViewDelegate> delegate;
@property (nonatomic) double dimmingAmount;

- (void)setTabHasActivity:(BOOL)hasActivity atIndex:(NSUInteger)index;
- (void)updateTextColor;

@end
