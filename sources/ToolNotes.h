//
//  ToolNotes.h
//  iTerm
//
//  Created by George Nachman on 9/19/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "iTermToolbeltView.h"
#import "FutureMethods.h"

@interface ToolNotes : NSView <ToolbeltTool, NSTextViewDelegate> {
    NSTextView *textView_;
    NSFileManager *filemanager_;
    BOOL ignoreNotification_;
}

@end
