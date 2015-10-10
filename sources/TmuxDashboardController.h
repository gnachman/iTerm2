//
//  TmuxDashboardController.h
//  iTerm
//
//  Created by George Nachman on 12/23/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "TmuxSessionsTable.h"
#import "TmuxWindowsTable.h"

@class TmuxController;

@interface TmuxDashboardController : NSWindowController <TmuxSessionsTableProtocol, TmuxWindowsTableProtocol> {
    IBOutlet TmuxSessionsTable *sessionsTable_;
    IBOutlet TmuxWindowsTable *windowsTable_;
    IBOutlet NSPopUpButton *connectionsButton_;
}

+ (instancetype)sharedInstance;

@end
