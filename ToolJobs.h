//
//  ToolJobs.h
//  iTerm
//
//  Created by George Nachman on 9/6/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "ToolWrapper.h"
#import "FutureMethods.h"

@interface ToolJobs : NSView <ToolbeltTool, NSTableViewDelegate, NSTableViewDataSource> {
    NSScrollView *scrollView_;
    NSTableView *tableView_;
    NSButton *kill_;
    NSPopUpButton *signal_;
    NSTimer *timer_;
    NSMutableArray *names_;
    NSMutableArray *pids_;
    BOOL hasSelection;
    BOOL shutdown_;
    NSTimeInterval timerInterval_;
}

@property (nonatomic, assign) BOOL hasSelection;
@end
