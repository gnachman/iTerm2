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

@end

@interface SessionTitleView : NSView<iTermStatusBarContainer>

@property(nonatomic, copy) NSString *title;
@property(nonatomic, weak) id<SessionTitleViewDelegate> delegate;
@property(nonatomic, assign) double dimmingAmount;
@property(nonatomic, assign) int ordinal;

- (void)updateTextColor;
- (void)updateBackgroundColor;

@end
