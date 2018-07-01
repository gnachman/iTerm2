//
//  SessionTitleView.h
//  iTerm
//
//  Created by George Nachman on 10/21/11.
//  Copyright 2011 George Nachman. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class iTermStatusBarViewController;

@protocol SessionTitleViewDelegate <NSObject>

- (NSColor *)tabColor;
- (NSMenu *)menu;
- (void)close;
- (void)beginDrag;
- (BOOL)sessionTitleViewIsFirstResponder;
- (void)doubleClickOnTitleView;
- (void)sessionTitleViewBecomeFirstResponder;

@end

@interface SessionTitleView : NSView

@property(nonatomic, copy) NSString *title;
@property(nonatomic, weak) id<SessionTitleViewDelegate> delegate;
@property(nonatomic, assign) double dimmingAmount;
@property(nonatomic, assign) int ordinal;
@property(nonatomic, strong) iTermStatusBarViewController *statusBarViewController;

@end
