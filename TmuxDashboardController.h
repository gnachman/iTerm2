//
//  TmuxDashboardController.h
//  iTerm
//
//  Created by George Nachman on 12/23/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "TmuxSessionsTable.h"

@class TmuxController;

@interface TmuxDashboardController : NSWindowController <TmuxSessionsTableProtocol> {
    TmuxController *tmuxController_;  // weak TODO make this a delegate
    IBOutlet TmuxSessionsTable *sessionsTable_;
}

@property (nonatomic, assign) TmuxController *tmuxController;

- (id)initWithTmuxController:(TmuxController *)tmuxController;

@end
