//
//  ToolProfiles.h
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "ToolbeltView.h"
#import "BookmarkListView.h"

@interface ToolProfiles : NSView <ToolbeltTool, BookmarkTableDelegate> {
    BookmarkListView *listView_;
    NSPopUpButton *popup_;
}

- (id)initWithFrame:(NSRect)frame;

@end
