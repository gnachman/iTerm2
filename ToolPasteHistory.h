//
//  ToolPasteHistory.h
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "ToolbeltView.h"
#import "PasteboardHistory.h"

@interface ToolPasteHistory : NSView <ToolbeltTool, NSTableViewDataSource, NSTableViewDelegate> {
    NSScrollView *scrollView_;
    NSTableView *tableView_;
    NSButton *clear_;
    PasteboardHistory *pasteHistory_;
    NSTimer *minuteRefreshTimer_;
    BOOL shutdown_;
}

- (id)initWithFrame:(NSRect)frame;
- (void)shutdown;

@end
