//
//  ToolWrapper.h
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "iTermCollapsingSplitView.h"

@class PseudoTerminal;

@protocol ToolWrapperDelegate

- (BOOL)haveOnlyOneTool;
- (void)hideToolbelt;
- (void)toggleShowToolWithName:(NSString *)theName;

@end

@protocol ToolbeltTool
- (CGFloat)minimumHeight;

@optional
- (void)relayout;
- (void)shutdown;
@end

@interface ToolWrapper : NSView<iTermCollapsingSplitViewItem> 

@property (nonatomic, copy) NSString *name;
@property (nonatomic, readonly) __weak NSView *container;
@property (nonatomic, assign) PseudoTerminal *term;
@property (nonatomic, assign) id<ToolWrapperDelegate> delegate;

- (void)relayout;
- (NSView<ToolbeltTool> *)tool;
- (void)removeToolSubviews;
- (CGFloat)minimumHeight;

@end
