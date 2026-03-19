//
//  SessionTitleView.h
//  iTerm
//
//  Created by George Nachman on 10/21/11.
//  Copyright 2011 George Nachman. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "iTermStatusBarViewController.h"

@protocol SessionTitleViewDelegate <NSObject>

- (NSMenu *)menu;
- (void)close;
- (void)beginDrag;
- (void)doubleClickOnTitleView;
- (void)sessionTitleViewBecomeFirstResponder;
- (NSColor *)sessionTitleViewBackgroundColor;
- (BOOL)sessionTitleViewIsLocked;
- (void)sessionTitleViewToggleLock;

@optional
- (void)sessionTitleViewDidSelectPaneTabAtIndex:(NSUInteger)index;
- (void)sessionTitleViewDidClosePaneTabAtIndex:(NSUInteger)index;
- (void)sessionTitleViewDidRequestNewPaneTab;

@end

@interface SessionTitleView : NSView<iTermStatusBarContainer>

@property(nonatomic, copy) NSString *title;
@property(nonatomic, weak) id<SessionTitleViewDelegate> delegate;
@property(nonatomic, assign) double dimmingAmount;
@property(nonatomic, assign) int ordinal;

- (void)updateTextColor;
- (void)updateBackgroundColor;
- (void)updateLockButton;
- (void)setPaneTabTitles:(NSArray<NSString *> *)titles activeIndex:(NSUInteger)activeIndex;
- (void)setPaneTabHasActivity:(BOOL)hasActivity atIndex:(NSUInteger)index;

@end
