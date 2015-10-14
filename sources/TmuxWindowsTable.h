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

@interface TmuxWindowsTable : NSObject <NSTableViewDelegate, NSTableViewDataSource>

@property (nonatomic, assign) id<TmuxWindowsTableProtocol> delegate;

- (void)setWindows:(NSArray *)windows;
- (void)setNameOfWindowWithId:(int)wid to:(NSString *)newName;
- (NSArray<NSString *> *)names;
- (void)updateEnabledStateOfButtons;
- (void)reloadData;

#pragma mark Interface Builder actions

- (IBAction)addWindow:(id)sender;
- (IBAction)removeWindow:(id)sender;
- (IBAction)showInWindows:(id)sender;
- (IBAction)showInTabs:(id)sender;
- (IBAction)hideWindow:(id)sender;

@end
