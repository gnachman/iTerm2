#import <Cocoa/Cocoa.h>
#import "ToolWrapper.h"
#import "FutureMethods.h"

@class ToolCapturedOutputView;
@class ToolCommandHistoryView;
@class ToolDirectoriesView;
@class ToolbeltSplitView;
@class PseudoTerminal;

extern NSString *kCommandHistoryToolName;
extern NSString *kCapturedOutputToolName;

// Notification posted when all windows should hide their toolbelts.
extern NSString *const kToolbeltShouldHide;

@interface ToolbeltView : NSView <NSSplitViewDelegate, ToolWrapperDelegate> {
    ToolbeltSplitView *splitter_;
    NSMutableDictionary *tools_;
    PseudoTerminal *term_;   // weak
}

+ (NSArray *)configuredTools;

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

- (ToolCommandHistoryView *)commandHistoryView;
- (ToolDirectoriesView *)directoriesView;
- (ToolCapturedOutputView *)capturedOutputView;

- (void)relayoutAllTools;
- (void)update;

@end
