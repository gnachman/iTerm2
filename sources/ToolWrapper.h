//
//  ToolWrapper.h
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>

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

@interface ToolWrapper : NSView {
    NSTextField *title_;
    NSButton *closeButton_;
    NSString *name;
    NSView *container_;
    PseudoTerminal *term;
	id<ToolWrapperDelegate> delegate_;  // weak
}

@property (nonatomic, copy) NSString *name;
@property (nonatomic, readonly) __weak NSView *container;
@property (nonatomic, assign) PseudoTerminal *term;
@property (nonatomic, assign) id<ToolWrapperDelegate> delegate;

- (void)relayout;
- (NSObject<ToolbeltTool> *)tool;
- (void)removeToolSubviews;
- (CGFloat)minimumHeight;

@end
