//
//  ToolbeltView.h
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class PseudoTerminal;

@protocol ToolbeltTool
@optional
- (void)relayout;

@optional
- (void)shutdown;
@end

@interface ToolbeltView : NSView {
    NSSplitView *splitter_;
    NSMutableDictionary *tools_;
    PseudoTerminal *term_;   // weak
}

+ (void)registerToolWithName:(NSString *)name withClass:(Class)c;
+ (void)populateMenu:(NSMenu *)menu;
+ (void)toggleShouldShowTool:(NSString *)theName;
+ (int)numberOfVisibleTools;

- (id)initWithFrame:(NSRect)frame term:(PseudoTerminal *)term;


// Is the tool visible?
- (BOOL)showingToolWithName:(NSString *)theName;

- (void)toggleToolWithName:(NSString *)theName;

// Do prefs say the tool is visible?
+ (BOOL)shouldShowTool:(NSString *)name;

- (BOOL)haveOnlyOneTool;
- (void)shutdown;

@end
