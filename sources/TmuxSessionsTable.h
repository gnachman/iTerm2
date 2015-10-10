//
//  TmuxSessionsTable.h
//  iTerm
//
//  Created by George Nachman on 12/23/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "FutureMethods.h"

@protocol TmuxSessionsTableProtocol <NSObject>

- (NSArray *)sessions;
- (void)renameSessionWithName:(NSString *)oldName toName:(NSString *)newName;
- (void)removeSessionWithName:(NSString *)sessionName;
- (void)addSessionWithName:(NSString *)sessionName;
- (void)attachToSessionWithName:(NSString *)sessionName;
- (NSString *)nameOfAttachedSession;
- (void)selectedSessionChangedTo:(NSString *)newName;
- (void)linkWindowId:(int)windowId
           inSession:(NSString *)sessionName
           toSession:(NSString *)targetSession;
- (void)detach;

@end

@interface TmuxSessionsTable : NSObject <NSTableViewDelegate, NSTableViewDataSource> {
    NSMutableArray *model_;
    BOOL canAttachToSelectedSession_;
    NSObject<TmuxSessionsTableProtocol> *delegate_;  // weak

    IBOutlet NSTableColumn *checkColumn_;
    IBOutlet NSTableColumn *nameColumn_;
    IBOutlet NSTableView *tableView_;
    IBOutlet NSButton *attachButton_;
    IBOutlet NSButton *detachButton_;
    IBOutlet NSButton *removeButton_;
}

@property (nonatomic, assign) NSObject<TmuxSessionsTableProtocol> *delegate;

- (void)setSessions:(NSArray *)names;
- (NSString *)selectedSessionName;
- (void)selectSessionWithName:(NSString *)name;

#pragma mark Interface Builder actions

- (IBAction)addSession:(id)sender;
- (IBAction)removeSession:(id)sender;
- (IBAction)attach:(id)sender;
- (IBAction)detach:(id)sender;

@end
