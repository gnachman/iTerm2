//
//  ToolPasteHistory.h
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "FutureMethods.h"
#import "iTermToolbeltView.h"
#import "PasteboardHistory.h"

@interface ToolPasteHistory : NSView <ToolbeltTool, NSTableViewDataSource, NSTableViewDelegate>

- (id)initWithFrame:(NSRect)frame;
- (void)shutdown;

@end
