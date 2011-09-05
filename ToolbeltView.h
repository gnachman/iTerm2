//
//  ToolbeltView.h
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@protocol ToolbeltDelegate

@end

@protocol ToolbeltTool
@end

@interface ToolbeltView : NSView {
    id<ToolbeltDelegate> delegate_;
    NSSplitView *splitter_;
    NSDictionary *tools_;
}

+ (void)registerToolWithName:(NSString *)name withClass:(Class)c;

- (id)initWithFrame:(NSRect)frame delegate:(id<ToolbeltDelegate>)delegate;

@end
