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
    NSMutableDictionary *tools_;
}

+ (void)registerToolWithName:(NSString *)name withClass:(Class)c;
+ (void)populateMenu:(NSMenu *)menu;
+ (void)toggleShouldShowTool:(NSString *)theName;
+ (int)numberOfVisibleTools;

- (id)initWithFrame:(NSRect)frame delegate:(id<ToolbeltDelegate>)delegate;


// Is the tool visible?
- (BOOL)showingToolWithName:(NSString *)theName;

- (void)toggleToolWithName:(NSString *)theName;

// Do prefs say the tool is visible?
+ (BOOL)shouldShowTool:(NSString *)name;

- (BOOL)haveMultipleTools;

@end
