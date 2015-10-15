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

@interface TmuxSessionsTable : NSObject <NSTableViewDelegate, NSTableViewDataSource>

@property(nonatomic, assign) id<TmuxSessionsTableProtocol> delegate;
@property(nonatomic, readonly) NSString *selectedSessionName;

- (void)setSessions:(NSArray *)names;
- (void)selectSessionWithName:(NSString *)name;

@end
