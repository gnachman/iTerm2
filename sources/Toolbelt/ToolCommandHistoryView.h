//
//  ToolCommandHistoryView.h
//  iTerm
//
//  Created by George Nachman on 1/15/14.
//
//

#import <Cocoa/Cocoa.h>

#import "iTermToolbeltView.h"

@class iTermCommandHistoryCommandUseMO;

@interface ToolCommandHistoryView : NSView <
  ToolbeltTool,
  NSTableViewDataSource,
  NSTableViewDelegate,
  NSTextFieldDelegate>

// For testing
@property(nonatomic, readonly) NSTableView *tableView;

- (instancetype)initWithFrame:(NSRect)frame;
- (void)shutdown;
- (void)updateCommands;
- (iTermCommandHistoryCommandUseMO *)selectedCommandUse;
- (void)removeSelection;

@end
