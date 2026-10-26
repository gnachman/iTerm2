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
@class TSVDocument;

@interface TmuxDashboardController : NSWindowController <TmuxSessionsTableProtocol, TmuxWindowsTableProtocol>

+ (instancetype)sharedInstance;

// The windows of a list-windows reply (TmuxController's listWindowsDetailedFormat) to show, each
// as @[name, number]. Windows holding parked workgroup peers are left out.
+ (NSArray<NSArray<NSString *> *> *)dashboardWindowsFromDocument:(TSVDocument *)doc;
- (void)didAttachWithHiddenWindows:(BOOL)anyHidden
                    tooManyWindows:(BOOL)tooMany;

@end
