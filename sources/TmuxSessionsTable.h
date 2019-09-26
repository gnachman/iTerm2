//
//  TmuxSessionsTable.h
//  iTerm
//
//  Created by George Nachman on 12/23/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "FutureMethods.h"

@class TmuxSessionsTable;
@class iTermTmuxSessionObject;

@protocol TmuxSessionsTableProtocol <NSObject>

- (NSArray<iTermTmuxSessionObject *> *)sessionsTableObjects:(TmuxSessionsTable *)sender;
- (void)renameSessionWithNumber:(int)sessionNumber
                         toName:(NSString *)newName;
- (void)removeSessionWithNumber:(int)sessionNumber;
- (void)addSessionWithName:(NSString *)sessionName;
- (void)attachToSessionWithNumber:(int)sessionNumber;
- (NSNumber *)numberOfAttachedSession;
- (void)selectedSessionDidChange;
- (void)linkWindowId:(int)windowId
     inSessionNumber:(int)sourceSessionNumber
     toSessionNumber:(int)targetSessionNumber;
- (void)moveWindowId:(int)windowId
     inSessionNumber:(int)sessionNumber
     toSessionNumber:(int)targetSessionNumber;
- (void)detach;

@end

@interface TmuxSessionsTable : NSObject <NSTableViewDelegate, NSTableViewDataSource>

@property(nonatomic, assign) id<TmuxSessionsTableProtocol> delegate;
@property(nonatomic, readonly) NSNumber *selectedSessionNumber;

- (void)setSessionObjects:(NSArray<iTermTmuxSessionObject *> *)names;
- (void)selectSessionNumber:(int)number;

@end
