//
//  iTermToolWrapper.h
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "iTermKeyBindingAction.h"

@class CapturedOutput;
@class iTermAction;
@protocol iTermMark;
@class iTermToolSnippets;
@protocol ProcessInfoProvider;
@class ToolCommandHistoryView;
@protocol VT100ScreenMarkReading;
@protocol VT100RemoteHostReading;
@class iTermCommandHistoryCommandUseMO;
@class ToolNamedMarks;
@class iTermToolWrapper;
@class iTermToolCodecierge;

@protocol iTermToolbeltViewDelegate<NSObject>

- (CGFloat)growToolbeltBy:(CGFloat)amount;
// Dragging of the toolbelt's handle finished.
- (void)toolbeltDidFinishGrowing;
- (void)toolbeltUpdateMouseCursor;
- (void)toolbeltInsertText:(NSString *)text;
- (id<VT100RemoteHostReading>)toolbeltCurrentHost;
- (pid_t)toolbeltCurrentShellProcessId;
- (id<ProcessInfoProvider>)toolbeltCurrentShellProcessInfoProvider;
- (id<VT100ScreenMarkReading>)toolbeltLastCommandMark;
- (void)toolbeltDidSelectMark:(id<iTermMark>)mark;
- (void)toolbeltActivateTriggerForCapturedOutputInCurrentSession:(CapturedOutput *)capturedOutput;
- (BOOL)toolbeltCurrentSessionHasGuid:(NSString *)guid;
- (NSString *)toolbeltCurrentSessionGUID;
- (NSArray<iTermCommandHistoryCommandUseMO *> *)toolbeltCommandUsesForCurrentSession;
- (void)toolbeltApplyActionToCurrentSession:(iTermAction *)action;
- (void)toolbeltOpenAdvancedPasteWithString:(NSString *)text escaping:(iTermSendTextEscaping)escaping;
- (void)toolbeltOpenComposerWithString:(NSString *)text escaping:(iTermSendTextEscaping)escaping;
- (void)toolbeltAddNamedMark;
- (void)toolbeltRemoveNamedMark:(id<VT100ScreenMarkReading>)mark;
- (void)toolbeltRenameNamedMark:(id<VT100ScreenMarkReading>)mark to:(NSString *)newName;
- (NSArray<NSString *> *)toolbeltSnippetTags;

@end

@protocol ToolWrapperDelegate <NSObject>

@property(nonatomic, assign) id<iTermToolbeltViewDelegate> delegate;
@property(nonatomic, readonly) BOOL haveOnlyOneTool;
@property(nonatomic, readonly) ToolCommandHistoryView *commandHistoryView;
@property(nonatomic, readonly) ToolNamedMarks *namedMarksView;
@property(nonatomic, readonly) iTermToolSnippets *snippetsView;
@property(nonatomic, readonly) iTermToolCodecierge *codeciergeView;

- (void)hideToolbelt;
- (void)toggleShowToolWithName:(NSString *)theName;

@end

@protocol ToolbeltTool <NSObject>
- (CGFloat)minimumHeight;

@optional
+ (BOOL)isDynamic;
- (NSDictionary *)restorableState;
- (void)restoreFromState:(NSDictionary *)state;
- (instancetype)initWithFrame:(NSRect)frame URL:(NSURL *)url identifier:(NSString *)identifier;
- (void)relayout;
- (void)shutdown;
- (void)windowBackgroundColorDidChange;
@end

@interface NSView (ToolWrapper)
// Call this on a tool to get its wrapper.
- (iTermToolWrapper *)toolWrapper;
@end

@interface iTermToolWrapper : NSView

@property(nonatomic) BOOL collapsed;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, readonly) NSView *container;
@property(nonatomic, weak) id<ToolWrapperDelegate> delegate;
@property(nonatomic, readonly) id<ToolbeltTool> tool;
@property(nonatomic, readonly) CGFloat minimumHeight;
@property(nonatomic, readonly) CGFloat minimumHeightWhenExpanded;

- (void)relayout;
- (void)removeToolSubviews;
- (void)temporarilyRemoveSubviews;
- (void)restoreSubviews;

@end
