//
//  ToolCommandHistoryView.h
//  iTerm
//
//  Created by George Nachman on 1/15/14.
//
//

#import <Cocoa/Cocoa.h>

#import "iTermToolbeltView.h"

@class CommandUse;

@interface ToolCommandHistoryView : NSView <
  ToolbeltTool,
  NSTableViewDataSource,
  NSTableViewDelegate,
  NSTextFieldDelegate>

// For testing
@property(nonatomic, readonly) NSTableView *tableView;

- (id)initWithFrame:(NSRect)frame;
- (void)shutdown;
- (void)updateCommands;
- (CommandUse *)selectedCommandUse;

@end
