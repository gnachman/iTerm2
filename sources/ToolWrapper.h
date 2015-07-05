//
//  ToolWrapper.h
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class CapturedOutput;
@class iTermMark;
@class VT100RemoteHost;
@class ToolCommandHistoryView;
@class VT100ScreenMark;

@protocol iTermToolbeltViewDelegate<NSObject>
- (CGFloat)growToolbeltBy:(CGFloat)amount;
- (void)toolbeltUpdateMouseCursor;
- (void)toolbeltInsertText:(NSString *)text;
- (VT100RemoteHost *)toolbeltCurrentHost;
- (pid_t)toolbeltCurrentShellProcessId;
- (VT100ScreenMark *)toolbeltLastCommandMark;
- (void)toolbeltDidSelectMark:(iTermMark *)mark;
- (void)toolbeltActivateTriggerForCapturedOutputInCurrentSession:(CapturedOutput *)capturedOutput;
- (BOOL)toolbeltCurrentSessionHasGuid:(NSString *)guid;
@end

@protocol ToolWrapperDelegate

@property(nonatomic, readonly) id<iTermToolbeltViewDelegate> delegate;

- (BOOL)haveOnlyOneTool;
- (void)hideToolbelt;
- (void)toggleShowToolWithName:(NSString *)theName;
- (ToolCommandHistoryView *)commandHistoryView;

@end

@protocol ToolbeltTool
- (CGFloat)minimumHeight;

@optional
- (void)relayout;
- (void)shutdown;
@end

@interface ToolWrapper : NSView

@property (nonatomic, copy) NSString *name;
@property (nonatomic, readonly) __weak NSView *container;
@property (nonatomic, assign) id<ToolWrapperDelegate> delegate;

- (void)relayout;
- (NSObject<ToolbeltTool> *)tool;
- (void)removeToolSubviews;
- (CGFloat)minimumHeight;

@end
