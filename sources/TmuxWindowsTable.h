//
//  TmuxWindowsTable.h
//  iTerm
//
//  Created by George Nachman on 12/25/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "FutureMethods.h"

extern NSString *kWindowPasteboardType;

@protocol TmuxWindowsTableProtocol <NSObject>

- (void)reloadWindows;
- (void)renameWindowWithId:(int)windowId toName:(NSString *)newName;
- (void)unlinkWindowWithId:(int)windowId;
- (void)addWindow;
- (void)showWindowsWithIds:(NSArray *)windowIds inTabs:(BOOL)inTabs;
- (void)hideWindowWithId:(int)windowId;
- (BOOL)haveSelectedSession;
- (BOOL)currentSessionSelected;
- (BOOL)haveOpenWindowWithId:(int)windowId;
- (NSString *)selectedSessionName;

@end

@interface TmuxWindowsTable : NSObject <NSTableViewDelegate, NSTableViewDataSource> {
    NSMutableArray *model_;
    NSObject<TmuxWindowsTableProtocol> *delegate_;  // weak
    NSMutableArray *filteredModel_;

    IBOutlet NSTableView *tableView_;
    IBOutlet NSButton *addWindowButton_;
    IBOutlet NSButton *removeWindowButton_;
    IBOutlet NSButton *openInTabsButton_;
    IBOutlet NSButton *openInWindowsButton_;
    IBOutlet NSButton *hideWindowButton_;
    IBOutlet NSSearchField *searchField_;
}

@property (nonatomic, assign) NSObject<TmuxWindowsTableProtocol> *delegate;

- (void)setWindows:(NSArray *)windows;
- (void)setNameOfWindowWithId:(int)wid to:(NSString *)newName;
- (NSArray *)names;
- (void)updateEnabledStateOfButtons;
- (void)reloadData;

#pragma mark Interface Builder actions

- (IBAction)addWindow:(id)sender;
- (IBAction)removeWindow:(id)sender;
- (IBAction)showInWindows:(id)sender;
- (IBAction)showInTabs:(id)sender;
- (IBAction)hideWindow:(id)sender;

@end
